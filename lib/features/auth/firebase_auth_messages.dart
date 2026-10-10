import 'package:firebase_auth/firebase_auth.dart';

/// Traduz os códigos mais comuns do FirebaseAuthException pra mensagens em
/// português — substitui o antigo `AuthException.message` do Supabase.
String firebaseAuthErrorMessage(FirebaseAuthException e) {
  switch (e.code) {
    case 'user-not-found':
    case 'wrong-password':
    case 'invalid-credential':
      return 'E-mail ou senha incorretos.';
    case 'invalid-email':
      return 'E-mail inválido.';
    case 'user-disabled':
      return 'Esta conta foi desativada.';
    case 'email-already-in-use':
      return 'Já existe uma conta com esse e-mail.';
    case 'weak-password':
      return 'Senha muito fraca — use ao menos 6 caracteres.';
    case 'too-many-requests':
      return 'Muitas tentativas. Tente novamente em alguns minutos.';
    case 'network-request-failed':
      return 'Falha de conexão. Verifique sua internet.';
    default:
      return e.message ?? 'Ocorreu um erro inesperado. Tente novamente.';
  }
}
