import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../../../core/app_config.dart';
import '../../../core/services/api_client.dart';
import '../../../core/services/photo_cache.dart';
import 'profile_provider.dart';

/// StreamProvider sobre idTokenChanges (não authStateChanges) pra também
/// capturar refresh de token e invalidar o cache do ApiClient junto.
final authStateProvider = StreamProvider<User?>((ref) {
  return FirebaseAuth.instance.idTokenChanges();
});

/// Foto da conta Google do usuário, ou `null` (e-mail/senha, ou conta sem foto:
/// quem usa isso cai nas iniciais). O Firebase às vezes só preenche a foto nos
/// dados do provedor, então olha `photoURL` e depois cada provedor vinculado.
final userPhotoUrlProvider = Provider<String?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return null;
  final direct = user.photoURL;
  if (direct != null && direct.isNotEmpty) return direct;
  for (final info in user.providerData) {
    final url = info.photoURL;
    if (url != null && url.isNotEmpty) return url;
  }
  return null;
});

final photoCacheProvider = Provider<PhotoCache>((ref) => PhotoCache());

/// Bytes da foto do usuário, vindos do cache (ver [PhotoCache]); `null` cai nas
/// iniciais. Avatar do perfil e marcador do mapa leem daqui: um só pedido.
final userPhotoProvider = FutureProvider<Uint8List?>((ref) {
  return ref.watch(photoCacheProvider).load(ref.watch(userPhotoUrlProvider));
});

final authControllerProvider = Provider((ref) {
  return AuthController(ref.watch(apiClientProvider), ref: ref);
});

class AuthController {
  AuthController(this._apiClient, {FirebaseAuth? auth, Ref? ref})
      : _auth = auth ?? FirebaseAuth.instance,
        _ref = ref;

  final ApiClient _apiClient;
  final FirebaseAuth _auth;
  final Ref? _ref;

  Future<void> _ensureProfileExists(String? nome,
      {String? departamento}) async {
    await _apiClient.rpc('ensure_profile', {
      'p_nome': nome ?? 'Sem nome',
      'p_departamento': departamento,
    });
    // profileProvider pode já ter rodado (e cacheado null) antes desta RPC
    // commitar — ex.: RadarPage observa profileProvider desde o boot, e
    // pode vencer a corrida contra este ensure_profile. Sem invalidar aqui,
    // esse null ficaria cacheado pelo resto da sessão (nada mais invalida
    // profileProvider sozinho).
    _ref?.invalidate(profileProvider);
  }

  Future<void> signInWithGoogle() async {
    try {
      // google_sign_in_web (0.12.x) não devolve idToken em signIn() — só
      // accessToken —, então no Web o login passa direto pelo Firebase.
      if (kIsWeb) {
        await _auth.signInWithPopup(GoogleAuthProvider());
        await _ensureProfileExists(_auth.currentUser?.displayName);
        return;
      }

      const webClientId = AppConfig.serverWebClientId;
      const iosClientId = AppConfig.clientId;

      if (webClientId.isEmpty) {
        throw 'SERVER_WEB_CLIENT_ID não configurado';
      }

      // No iOS, clientId é o Client ID nativo do app e serverClientId é o
      // Web Client ID (necessário pro backend validar o idToken).
      final googleSignIn = GoogleSignIn(
        clientId: Platform.isIOS ? iosClientId : null,
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
    _apiClient.clearCache();
    await _ref?.read(photoCacheProvider).clear();
  }
}
