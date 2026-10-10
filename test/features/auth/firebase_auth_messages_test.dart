import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/features/auth/firebase_auth_messages.dart';

void main() {
  group('firebaseAuthErrorMessage', () {
    const casos = {
      'user-not-found': 'E-mail ou senha incorretos.',
      'wrong-password': 'E-mail ou senha incorretos.',
      'invalid-credential': 'E-mail ou senha incorretos.',
      'invalid-email': 'E-mail inválido.',
      'user-disabled': 'Esta conta foi desativada.',
      'email-already-in-use': 'Já existe uma conta com esse e-mail.',
      'weak-password': 'Senha muito fraca — use ao menos 6 caracteres.',
      'too-many-requests':
          'Muitas tentativas. Tente novamente em alguns minutos.',
      'network-request-failed': 'Falha de conexão. Verifique sua internet.',
    };

    casos.forEach((code, mensagemEsperada) {
      test('traduz o código "$code"', () {
        final exception = FirebaseAuthException(code: code);
        expect(firebaseAuthErrorMessage(exception), mensagemEsperada);
      });
    });

    test('usa a mensagem original pra código desconhecido', () {
      final exception = FirebaseAuthException(
          code: 'algum-codigo-novo', message: 'mensagem original');
      expect(firebaseAuthErrorMessage(exception), 'mensagem original');
    });

    test('usa mensagem genérica quando não há código nem mensagem reconhecidos',
        () {
      final exception = FirebaseAuthException(code: 'algum-codigo-novo');
      expect(firebaseAuthErrorMessage(exception),
          'Ocorreu um erro inesperado. Tente novamente.');
    });
  });
}
