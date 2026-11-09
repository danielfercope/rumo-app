import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/core/services/api_client.dart';
import 'package:rumo_app/core/services/photo_cache.dart';
import 'package:rumo_app/features/auth/providers/auth_provider.dart';
import 'package:rumo_app/features/auth/providers/profile_provider.dart';

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUserCredential extends Mock implements UserCredential {}

class MockApiClient extends Mock implements ApiClient {}

class MockRef extends Mock implements Ref {}

class MockPhotoCache extends Mock implements PhotoCache {}

void main() {
  late MockFirebaseAuth mockAuth;
  late MockApiClient mockApiClient;
  late MockRef mockRef;
  late MockPhotoCache mockPhotoCache;
  late AuthController controller;

  setUp(() {
    mockAuth = MockFirebaseAuth();
    mockApiClient = MockApiClient();
    mockRef = MockRef();
    mockPhotoCache = MockPhotoCache();
    when(() => mockRef.invalidate(profileProvider)).thenReturn(null);
    when(() => mockRef.read(photoCacheProvider)).thenReturn(mockPhotoCache);
    when(() => mockPhotoCache.clear()).thenAnswer((_) async {});
    controller = AuthController(mockApiClient, auth: mockAuth, ref: mockRef);
  });

  group('signIn', () {
    test('chama signInWithEmailAndPassword com o e-mail e a senha informados',
        () async {
      when(() => mockAuth.signInWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenAnswer((_) async => MockUserCredential());

      await controller.signIn(email: 'a@a.com', password: '123456');

      verify(() => mockAuth.signInWithEmailAndPassword(
            email: 'a@a.com',
            password: '123456',
          )).called(1);
    });

    test('propaga FirebaseAuthException sem tratar', () async {
      when(() => mockAuth.signInWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenThrow(FirebaseAuthException(code: 'wrong-password'));

      expect(
        () => controller.signIn(email: 'a@a.com', password: 'errada'),
        throwsA(isA<FirebaseAuthException>()),
      );
    });
  });

  group('signUp', () {
    test('cria o usuário e chama ensure_profile com nome e departamento',
        () async {
      when(() => mockAuth.createUserWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenAnswer((_) async => MockUserCredential());
      when(() => mockApiClient.rpc('ensure_profile', any()))
          .thenAnswer((_) async => {});

      await controller.signUp(
        name: 'Fulano',
        email: 'a@a.com',
        password: '123456',
        department: 'Gestão',
      );

      verify(() => mockAuth.createUserWithEmailAndPassword(
            email: 'a@a.com',
            password: '123456',
          )).called(1);

      final params =
          verify(() => mockApiClient.rpc('ensure_profile', captureAny()))
              .captured
              .single as Map;
      expect(params['p_nome'], 'Fulano');
      expect(params['p_departamento'], 'Gestão');
    });

    test(
        'invalida profileProvider após ensure_profile — sem isso, uma leitura '
        'de profileProvider que vencesse a corrida contra essa RPC ficaria '
        'com null cacheado pelo resto da sessão', () async {
      when(() => mockAuth.createUserWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenAnswer((_) async => MockUserCredential());
      when(() => mockApiClient.rpc('ensure_profile', any()))
          .thenAnswer((_) async => {});

      await controller.signUp(
        name: 'Fulano',
        email: 'a@a.com',
        password: '123456',
        department: 'Gestão',
      );

      verify(() => mockRef.invalidate(profileProvider)).called(1);
    });

    test('propaga a exceção quando a criação do usuário falha', () async {
      when(() => mockAuth.createUserWithEmailAndPassword(
            email: any(named: 'email'),
            password: any(named: 'password'),
          )).thenThrow(FirebaseAuthException(code: 'email-already-in-use'));

      expect(
        () => controller.signUp(
          name: 'Fulano',
          email: 'a@a.com',
          password: '123456',
          department: 'Gestão',
        ),
        throwsA(isA<FirebaseAuthException>()),
      );
      verifyNever(() => mockApiClient.rpc('ensure_profile', any()));
    });
  });

  group('signOut', () {
    test('chama signOut do FirebaseAuth', () async {
      when(() => mockAuth.signOut()).thenAnswer((_) async {});
      when(() => mockApiClient.clearCache()).thenReturn(null);

      await controller.signOut();

      verify(() => mockAuth.signOut()).called(1);
    });

    test(
        'limpa o token cacheado do ApiClient — sem isso, trocar de conta '
        'sem reiniciar o app reaproveitaria o token da conta anterior',
        () async {
      when(() => mockAuth.signOut()).thenAnswer((_) async {});
      when(() => mockApiClient.clearCache()).thenReturn(null);

      await controller.signOut();

      verify(() => mockApiClient.clearCache()).called(1);
    });

    test('esquece a foto guardada — a próxima conta não herda a foto desta',
        () async {
      when(() => mockAuth.signOut()).thenAnswer((_) async {});
      when(() => mockApiClient.clearCache()).thenReturn(null);

      await controller.signOut();

      verify(() => mockPhotoCache.clear()).called(1);
    });
  });
}
