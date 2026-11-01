import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/features/groups/models/group_member_model.dart';
import 'package:rumo_app/features/groups/models/group_model.dart';

void main() {
  group('Group.fromJson', () {
    test('faz parse completo, incluindo invite_hash quando presente', () {
      final group = Group.fromJson({
        'id': 'g1',
        'name': 'Vendas SC',
        'tracking_enabled': true,
        'created_by': 'u1',
        'created_at': '2026-10-25T12:00:00Z',
        'invite_hash': 'abc123',
      });

      expect(group.id, 'g1');
      expect(group.name, 'Vendas SC');
      expect(group.trackingEnabled, isTrue);
      expect(group.createdBy, 'u1');
      expect(group.inviteHash, 'abc123');
    });

    test('inviteHash e trackingEnabled usam padrão quando ausentes', () {
      final group = Group.fromJson({
        'id': 'g1',
        'name': 'Vendas SC',
        'created_by': 'u1',
        'created_at': '2026-10-25T12:00:00Z',
      });

      expect(group.trackingEnabled, isFalse);
      expect(group.inviteHash, isNull);
    });
  });

  group('GroupMember.fromJson', () {
    test('faz parse completo e isAdmin reflete o role', () {
      final admin = GroupMember.fromJson({
        'user_id': 'u1',
        'nome': 'Ana',
        'email': 'ana@x.com',
        'departamento': 'Gestão',
        'role': 'admin',
        'joined_at': '2026-10-25T12:00:00Z',
      });
      final member = GroupMember.fromJson({
        'user_id': 'u2',
        'role': 'member',
        'joined_at': '2026-10-25T12:00:00Z',
      });

      expect(admin.isAdmin, isTrue);
      expect(member.isAdmin, isFalse);
      expect(member.nome, '');
    });
  });

  group('MyGroup.fromJson', () {
    test('faz parse do embed role/joined_at/groups', () {
      final myGroup = MyGroup.fromJson({
        'role': 'admin',
        'joined_at': '2026-10-25T12:00:00Z',
        'groups': {
          'id': 'g1',
          'name': 'Vendas SC',
          'tracking_enabled': false,
          'created_by': 'u1',
          'created_at': '2026-10-25T12:00:00Z',
        },
      });

      expect(myGroup.isAdmin, isTrue);
      expect(myGroup.group.name, 'Vendas SC');
    });
  });

  group('TrackingPoint.fromJson', () {
    test('faz parse de latitude/longitude numéricas e ultimo_visto nulo', () {
      final point = TrackingPoint.fromJson({
        'user_id': 'u1',
        'nome': 'Ana',
        'email': 'ana@x.com',
        'latitude': -26.5,
        'longitude': -49,
        'ultimo_visto': null,
      });

      expect(point.latitude, -26.5);
      expect(point.longitude, -49.0);
      expect(point.ultimoVisto, isNull);
    });
  });
}
