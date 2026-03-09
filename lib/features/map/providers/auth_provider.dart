import 'dart:io'; 
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

final authControllerProvider = Provider((ref) => AuthController());

class AuthController {
  final _supabase = Supabase.instance.client;

  // Função auxiliar para gerar nonce aleatório
  String _generateRandomString() {
    final random = Random.secure();
    return base64Url.encode(List<int>.generate(16, (_) => random.nextInt(256)));
  }

  Future<void> signInWithGoogle() async {
    try {
      final webClientId = dotenv.env['SERVER_WEB_CLIENT_ID'];
      final iosClientId = dotenv.env['CLIENT_ID'];

      if (webClientId == null) {
        throw 'SERVER_WEB_CLIENT_ID não configurado no arquivo .env';
      }

      // 1. Gerar um nonce bruto
      final rawNonce = _generateRandomString();
      // 2. Criar o hash SHA256 do nonce (o que o Google espera no id_token)
      final hashedNonce = sha256.convert(utf8.encode(rawNonce)).toString();

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

      // No Supabase, para o Google, tentamos passar o nonce bruto.
      // Se o erro de mismatch persistir no iOS, o problema pode ser a configuração
      // do "Web Client ID" no painel do Supabase.
      await _supabase.auth.signInWithIdToken(
        provider: OAuthProvider.google,
        idToken: idToken,
        accessToken: accessToken,
        nonce: rawNonce, // Tente enviar o rawNonce aqui
      );

      final user = _supabase.auth.currentUser;
      if (user != null) {
        final existingProfile = await _supabase
            .from('profiles')
            .select()
            .eq('id', user.id)
            .maybeSingle();

        if (existingProfile == null) {
          await _supabase.from('profiles').insert({
            'id': user.id,
            'email': user.email,
            'nome': user.userMetadata?['full_name'] ?? googleUser.displayName,
            'departamento': 'Não definido',
            'nivel_acesso': 'user',
          });
        }
      }
    } catch (e) {
      debugPrint('Erro no login com Google: $e');
      rethrow;
    }
  }

  Future<void> signIn({required String email, required String password}) async {
    await _supabase.auth.signInWithPassword(email: email, password: password);
  }

  Future<void> signUp({
    required String name,
    required String email,
    required String password,
    required String department,
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {'full_name': name, 'department': department},
      );
      final user = response.user;
      if (user != null) {
        await _supabase.from('profiles').insert({
          'id': user.id,
          'email': email,
          'nome': name,
          'departamento': department,
          'nivel_acesso': 'user',
        });
      }
    } catch (e) {
      debugPrint('Erro no signUp: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
}
