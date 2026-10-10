import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../app_config.dart';

/// Erro retornado pelo PostgREST/Backend, parseado do corpo
/// `{code, message, details, hint}` (formato padrão do PostgREST).
class ApiException implements Exception {
  ApiException(this.message, {this.statusCode = 0, this.code});

  final int statusCode;
  final String message;
  final String? code;

  factory ApiException.fromResponse(http.Response response) {
    try {
      final data = json.decode(response.body) as Map<String, dynamic>;
      return ApiException(
        data['message'] as String? ?? 'Erro desconhecido',
        statusCode: response.statusCode,
        code: data['code'] as String?,
      );
    } catch (_) {
      return ApiException(
        'Erro HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
  }

  @override
  String toString() =>
      'ApiException($statusCode${code != null ? ', $code' : ''}): $message';
}

/// Client HTTP fino para o novo Backend (PostgREST + serviço Python),
/// substituindo o SupabaseClient. Troca o ID Token do Firebase por um token
/// interno via `/backend/auth/exchange` (ver backend/app/main.py), cacheado
/// até expirar.
class ApiClient {
  ApiClient({required this.baseUrl});

  final String baseUrl;

  String? _cachedToken;
  int? _cachedTokenExpiresAt;

  Future<String> _accessToken() async {
    final nowSeconds = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    if (_cachedToken != null &&
        _cachedTokenExpiresAt != null &&
        nowSeconds < _cachedTokenExpiresAt! - 30) {
      return _cachedToken!;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      throw ApiException('Usuário não autenticado', statusCode: 401);
    }

    final idToken = await user.getIdToken();
    final response = await http.post(
      Uri.parse('$baseUrl/backend/auth/exchange'),
      headers: {'Authorization': 'Bearer $idToken'},
    );
    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response);
    }

    final data = json.decode(response.body) as Map<String, dynamic>;
    _cachedToken = data['token'] as String;
    _cachedTokenExpiresAt = data['expires_at'] as int;
    return _cachedToken!;
  }

  Future<Map<String, String>> _authHeaders() async => {
        'Authorization': 'Bearer ${await _accessToken()}',
        'Content-Type': 'application/json',
      };

  dynamic _decode(http.Response response) {
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return response.body.isEmpty ? null : json.decode(response.body);
    }
    throw ApiException.fromResponse(response);
  }

  Future<dynamic> get(String table, {Map<String, String>? query}) async {
    final uri =
        Uri.parse('$baseUrl/rest/$table').replace(queryParameters: query);
    final response = await http.get(uri, headers: await _authHeaders());
    return _decode(response);
  }

  Future<dynamic> post(String table, Map<String, dynamic> body) async {
    final uri = Uri.parse('$baseUrl/rest/$table');
    final response = await http.post(uri,
        headers: await _authHeaders(), body: json.encode(body));
    return _decode(response);
  }

  /// Equivalente ao `.upsert(..., onConflict: x)` do Supabase.
  Future<dynamic> upsert(
    String table,
    Map<String, dynamic> body, {
    required String onConflict,
  }) async {
    final uri = Uri.parse('$baseUrl/rest/$table')
        .replace(queryParameters: {'on_conflict': onConflict});
    final headers = await _authHeaders();
    headers['Prefer'] = 'resolution=merge-duplicates,return=representation';
    final response =
        await http.post(uri, headers: headers, body: json.encode(body));
    return _decode(response);
  }

  /// Equivalente ao `.rpc(nome, params: {...})` do Supabase — mesma forma
  /// de parâmetros, só muda o transporte.
  Future<dynamic> rpc(String fn, Map<String, dynamic> params) async {
    final uri = Uri.parse('$baseUrl/rest/rpc/$fn');
    final response = await http.post(uri,
        headers: await _authHeaders(), body: json.encode(params));
    return _decode(response);
  }

  /// Chama o Backend (empresa-aqui, hubspot) em vez de uma Edge Function.
  Future<dynamic> backend(String path, Map<String, dynamic> body) async {
    final uri = Uri.parse('$baseUrl/backend/$path');
    final response = await http.post(uri,
        headers: await _authHeaders(), body: json.encode(body));
    return _decode(response);
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(baseUrl: AppConfig.apiBaseUrl);
});
