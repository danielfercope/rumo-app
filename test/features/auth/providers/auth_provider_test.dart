import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/core/services/api_client.dart';
import 'package:rumo_app/features/auth/providers/auth_provider.dart';

class MockFirebaseAuth extends Mock implements FirebaseAuth {}

class MockUserCredential extends Mock implements UserCredential {}

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockFirebaseAuth mockAuth;
  late MockApiClient mockApiClient;
  late AuthController controller;

  setUp(() {
    mockAuth = MockFirebaseAuth();
    mockApiClient = MockApiClient();
    controller = AuthController(mockApiClient, auth: mockAuth);
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

      await controller.signOut();

      verify(() => mockAuth.signOut()).called(1);
    });
  });
}
