
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final authStateProvider = StreamProvider<AuthState>((ref) {
  return Supabase.instance.client.auth.onAuthStateChange;
});

final authControllerProvider = Provider((ref) => AuthController());

class AuthController {
  final _supabase = Supabase.instance.client;

  Future<void> signIn({
    required String email,
    required String password,
  }) async {
    await _supabase.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  Future<void> signUp({
    required String name,
    required String email,
    required String password,
    required String department,
  }) async {
    try {
      // 1. Criar o usuário no Supabase Auth
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
        data: {
          'full_name': name,
          'department': department,
        },
      );

      final user = response.user;
      
      // 2. Tentar inserir na tabela 'profiles'
      if (user != null) {
        try {
          await _supabase.from('profiles').insert({
            'id': user.id,
            'email': email,
            'nome': name,
            'departamento': department,
            'nivel_acesso': 'user',
          });
        } catch (dbError) {
          // Se falhar aqui, o usuário foi criado no Auth, mas o perfil não.
          // Isso pode acontecer se o RLS estiver ativado e exigir autenticação, 
          // mas o usuário ainda não confirmou o e-mail.
          debugPrint('Erro ao criar perfil no banco: $dbError');
          // Opcional: Você pode querer deletar o usuário do auth se o perfil falhar,
          // mas o Supabase Auth não permite isso facilmente pelo client SDK por segurança.
          rethrow; 
        }
      }
    } catch (e) {
      debugPrint('Erro no processo de signUp: $e');
      rethrow;
    }
  }

  Future<void> signOut() async {
    await _supabase.auth.signOut();
  }
}
