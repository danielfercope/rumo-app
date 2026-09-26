import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/features/auth/providers/profile_provider.dart';

void main() {
  group('UserProfile.fromJson', () {
    test('faz parse de um perfil completo', () {
      final profile = UserProfile.fromJson({
        'id': 'user-1',
        'email': 'teste@rumo.com',
        'nome': 'Fulano',
        'departamento': 'Gestão',
        'nivel_acesso': 'admin',
      });

      expect(profile.id, 'user-1');
      expect(profile.email, 'teste@rumo.com');
      expect(profile.nome, 'Fulano');
      expect(profile.departamento, 'Gestão');
      expect(profile.nivelAcesso, 'admin');
    });

    test('usa valores padrão quando campos opcionais estão ausentes', () {
      final profile = UserProfile.fromJson({'id': 'user-1'});

      expect(profile.email, '');
      expect(profile.nome, '');
      expect(profile.departamento, '');
      expect(profile.nivelAcesso, 'user');
    });
  });

  group('UserProfile.canAddCompany', () {
    const departamentosAutorizados = [
      'Pré-vendas',
      'Gestão',
      'Administração Interna'
    ];

    for (final departamento in departamentosAutorizados) {
      test('retorna true para o departamento "$departamento"', () {
        final profile = UserProfile(
          id: '1',
          email: 'a@a.com',
          nome: 'A',
          departamento: departamento,
          nivelAcesso: 'user',
        );

        expect(profile.canAddCompany, isTrue);
      });
    }

    test(
        'retorna true quando nivelAcesso é admin, independente do departamento',
        () {
      const profile = UserProfile(
        id: '1',
        email: 'a@a.com',
        nome: 'A',
        departamento: 'Departamento qualquer',
        nivelAcesso: 'admin',
      );

      expect(profile.canAddCompany, isTrue);
    });

    test('retorna false para departamento não autorizado e usuário comum', () {
      const profile = UserProfile(
        id: '1',
        email: 'a@a.com',
        nome: 'A',
        departamento: 'Executivo',
        nivelAcesso: 'user',
      );

      expect(profile.canAddCompany, isFalse);
    });
  });

  group('UserProfile.isExecutivo / isGuest', () {
    test('isExecutivo é true apenas para departamento "Executivo"', () {
      const executivo = UserProfile(
        id: '1',
        email: 'a@a.com',
        nome: 'A',
        departamento: 'Executivo',
        nivelAcesso: 'user',
      );
      const outro = UserProfile(
        id: '1',
        email: 'a@a.com',
        nome: 'A',
        departamento: 'Gestão',
        nivelAcesso: 'user',
      );

      expect(executivo.isExecutivo, isTrue);
      expect(outro.isExecutivo, isFalse);
    });

    test('isGuest é true apenas quando nivelAcesso é "guest"', () {
      const guest = UserProfile(
        id: '1',
        email: 'a@a.com',
        nome: 'A',
        departamento: 'Gestão',
        nivelAcesso: 'guest',
      );
      const naoGuest = UserProfile(
        id: '1',
        email: 'a@a.com',
        nome: 'A',
        departamento: 'Gestão',
        nivelAcesso: 'user',
      );

      expect(guest.isGuest, isTrue);
      expect(naoGuest.isGuest, isFalse);
    });
  });
}
