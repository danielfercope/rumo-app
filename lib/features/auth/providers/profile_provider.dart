import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class UserProfile {
  final String id;
  final String email;
  final String nome;
  final String departamento;
  final String nivelAcesso;

  const UserProfile({
    required this.id,
    required this.email,
    required this.nome,
    required this.departamento,
    required this.nivelAcesso,
  });

  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
        id: json['id'] as String,
        email: json['email'] as String? ?? '',
        nome: json['nome'] as String? ?? '',
        departamento: json['departamento'] as String? ?? '',
        nivelAcesso: json['nivel_acesso'] as String? ?? 'user',
      );

  bool get isExecutivo => departamento == 'Executivo';
  bool get isGuest => nivelAcesso == 'guest';

  bool get canAddCompany =>
      departamento == 'Pré-vendas' ||
      departamento == 'Gestão' ||
      departamento == 'Administração Interna' ||
      nivelAcesso == 'admin';
}

final profileProvider = FutureProvider<UserProfile?>((ref) async {
  final user = Supabase.instance.client.auth.currentUser;
  if (user == null) return null;

  final data = await Supabase.instance.client
      .from('profiles')
      .select()
      .eq('id', user.id)
      .maybeSingle();

  return data == null ? null : UserProfile.fromJson(data);
});
