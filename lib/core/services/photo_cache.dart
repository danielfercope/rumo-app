import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Cache da foto do usuário.
///
/// O Google limita (429) os pedidos às fotos de perfil, e o app pedia a imagem
/// a cada carga, uma vez pro avatar e outra pro marcador do mapa. Aqui ela é
/// baixada uma vez, guardada em memória e em disco (some só quando vence ou a
/// URL muda) e, se o Google recusar depois, serve-se a cópia guardada, mesmo
/// vencida. Só a foto do usuário logado fica guardada.
class PhotoCache {
  PhotoCache({
    http.Client? client,
    Future<SharedPreferences> Function()? prefs,
    DateTime Function()? now,
    this.ttl = const Duration(hours: 24),
    this.retryAfterFailure = const Duration(minutes: 10),
    this.timeout = const Duration(seconds: 6),
  })  : _client = client ?? http.Client(),
        _prefs = prefs ?? SharedPreferences.getInstance,
        _now = now ?? DateTime.now;

  static const _storageKey = 'user_photo_cache_v1';

  final http.Client _client;
  final Future<SharedPreferences> Function() _prefs;
  final DateTime Function() _now;
  final Duration ttl;
  final Duration retryAfterFailure;
  final Duration timeout;

  _Entry? _memory;
  final Map<String, DateTime> _failedAt = {};
  final Map<String, Future<Uint8List?>> _inFlight = {};

  /// A foto de [url], ou `null` se não houver URL nem cópia guardada (quem
  /// chama cai nas iniciais). Pedidos simultâneos à mesma URL dividem uma só
  /// ida à rede.
  Future<Uint8List?> load(String? url) {
    if (url == null || url.isEmpty) return Future.value(null);
    return _inFlight[url] ??= _load(url).whenComplete(() {
      // bloco, não seta: `remove` devolve o próprio Future e travaria a espera
      _inFlight.remove(url);
    });
  }

  Future<Uint8List?> _load(String url) async {
    final stored = _memory?.url == url ? _memory : await _read(url);
    if (stored != null) {
      _memory = stored;
      if (_now().difference(stored.fetchedAt) < ttl) return stored.bytes;
    }

    // Depois de uma falha, não insiste a cada carga: era isso que alimentava o 429.
    final failed = _failedAt[url];
    if (failed != null && _now().difference(failed) < retryAfterFailure) {
      return stored?.bytes;
    }

    final fetched = await _fetch(url);
    if (fetched == null) {
      _failedAt[url] = _now();
      return stored?.bytes;
    }
    _failedAt.remove(url);
    final entry = _Entry(url, fetched, _now());
    _memory = entry;
    await _write(entry);
    return fetched;
  }

  Future<Uint8List?> _fetch(String url) async {
    try {
      final res = await _client.get(Uri.parse(url)).timeout(timeout);
      return res.statusCode == 200 && res.bodyBytes.isNotEmpty
          ? res.bodyBytes
          : null;
    } catch (_) {
      return null;
    }
  }

  // O armazenamento pode faltar ou lançar (janela privada, dados bloqueados):
  // sem ele o cache vale só em memória.
  Future<_Entry?> _read(String url) async {
    try {
      final raw = (await _prefs()).getString(_storageKey);
      if (raw == null) return null;
      final json = jsonDecode(raw) as Map<String, dynamic>;
      if (json['url'] != url) return null;
      return _Entry(
        url,
        base64Decode(json['bytes'] as String),
        DateTime.fromMillisecondsSinceEpoch(json['at'] as int),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(_Entry entry) async {
    try {
      await (await _prefs()).setString(
        _storageKey,
        jsonEncode({
          'url': entry.url,
          'at': entry.fetchedAt.millisecondsSinceEpoch,
          'bytes': base64Encode(entry.bytes),
        }),
      );
    } catch (_) {}
  }

  /// Esquece a foto guardada (ao sair da conta).
  Future<void> clear() async {
    _memory = null;
    _failedAt.clear();
    try {
      await (await _prefs()).remove(_storageKey);
    } catch (_) {}
  }
}

class _Entry {
  const _Entry(this.url, this.bytes, this.fetchedAt);

  final String url;
  final Uint8List bytes;
  final DateTime fetchedAt;
}
