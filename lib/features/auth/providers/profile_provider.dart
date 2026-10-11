import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api_client.dart';

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
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return null;

  final apiClient = ref.watch(apiClientProvider);
  final data = await apiClient.get('profiles', query: {'id': 'eq.${user.uid}'});
  final rows = data as List;
  return rows.isEmpty
      ? null
      : UserProfile.fromJson(rows.first as Map<String, dynamic>);
});
