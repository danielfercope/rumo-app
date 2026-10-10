import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/app_config.dart';
import '../../../core/services/api_client.dart';

/// StreamProvider sobre idTokenChanges (não authStateChanges) pra também
/// capturar refresh de token e invalidar o cache do ApiClient junto.
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.idTokenChanges();
});

final authControllerProvider = Provider((ref) {
  return AuthController(ref.watch(apiClientProvider));
});

class AuthController {
  AuthController(this._apiClient);

  final ApiClient _apiClient;
  final _auth = FirebaseAuth.instance;

  Future<void> _ensureProfileExists(String? nome,
      {String? departamento}) async {
    await _apiClient.rpc('ensure_profile', {
      'p_nome': nome ?? 'Sem nome',
      'p_departamento': departamento,
    });
  }

  Future<void> signInWithGoogle() async {
    try {
      const webClientId = AppConfig.serverWebClientId;
      const iosClientId = AppConfig.clientId;

      if (webClientId.isEmpty) {
        throw 'SERVER_WEB_CLIENT_ID não configurado';
      }

      final googleSignIn = GoogleSignIn(
        clientId: kIsWeb || Platform.isIOS ? iosClientId : null,
        serverClientId: webClientId,
      );

      final googleUser = await googleSignIn.signIn();
      if (googleUser == null) return;

      final googleAuth = await googleUser.authentication;
      final accessToken = googleAuth.accessToken;
      final idToken = googleAuth.idToken;

      if (idToken == null) {
        throw 'ID Token não encontrado.';
      }

      await _auth.signInWithCredential(
        GoogleAuthProvider.credential(
            idToken: idToken, accessToken: accessToken),
      );

      await _ensureProfileExists(googleUser.displayName);
    } catch (e) {
      debugPrint('Erro no login com Google: $e');
      rethrow;
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> signUp({
    required String name,
    required String email,
    required String password,
    required String department,
  }) async {
    try {
      await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
      await _ensureProfileExists(name, departamento: department);
    } catch (e) {
      debugPrint('Erro no signUp: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}
