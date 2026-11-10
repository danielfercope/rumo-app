import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/core/services/api_client.dart';
import 'package:rumo_app/features/groups/services/group_service.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient mockApiClient;
  late GroupService service;

  setUp(() {
    mockApiClient = MockApiClient();
    service = GroupService(mockApiClient);
  });

  test('createGroup chama create_group com p_name e mapeia a resposta',
      () async {
    when(() => mockApiClient.rpc('create_group', any())).thenAnswer(
      (_) async => {
        'id': 'g1',
        'name': 'Vendas',
        'tracking_enabled': false,
        'created_by': 'u1',
        'created_at': '2026-10-25T12:00:00Z',
        'invite_hash': 'abc',
      },
    );

    final group = await service.createGroup('Vendas');

    expect(group.id, 'g1');
    expect(group.inviteHash, 'abc');
    final params = verify(() => mockApiClient.rpc('create_group', captureAny()))
        .captured
        .single as Map;
    expect(params['p_name'], 'Vendas');
  });

  test('joinByHash chama join_group_by_hash com p_hash', () async {
    when(() => mockApiClient.rpc('join_group_by_hash', any())).thenAnswer(
      (_) async => {
        'id': 'g1',
        'name': 'Vendas',
        'created_by': 'u1',
        'created_at': '2026-10-25T12:00:00Z',
      },
    );

    await service.joinByHash('hash-123');

    final params =
        verify(() => mockApiClient.rpc('join_group_by_hash', captureAny()))
            .captured
            .single as Map;
    expect(params['p_hash'], 'hash-123');
  });

  test('regenerateInvite chama regenerate_group_invite com p_group_id',
      () async {
    when(() => mockApiClient.rpc('regenerate_group_invite', any())).thenAnswer(
      (_) async => {
        'id': 'g1',
        'name': 'Vendas',
        'created_by': 'u1',
        'created_at': '2026-10-25T12:00:00Z',
        'invite_hash': 'novo-hash',
      },
    );

    final group = await service.regenerateInvite('g1');

    expect(group.inviteHash, 'novo-hash');
    final params =
        verify(() => mockApiClient.rpc('regenerate_group_invite', captureAny()))
            .captured
            .single as Map;
    expect(params['p_group_id'], 'g1');
  });

  group('getInvite', () {
    test('devolve o hash quando a RPC responde com texto', () async {
      when(() => mockApiClient.rpc('get_group_invite', any()))
          .thenAnswer((_) async => 'hash-abc');

      final hash = await service.getInvite('g1');

      expect(hash, 'hash-abc');
    });

    test('lança GroupPermissionError quando a RPC devolve null', () async {
      when(() => mockApiClient.rpc('get_group_invite', any()))
          .thenAnswer((_) async => null);

      expect(
        () => service.getInvite('g1'),
        throwsA(isA<GroupPermissionError>()),
      );
    });
  });

  test('setMemberRole chama set_member_role com os parâmetros certos',
      () async {
    when(() => mockApiClient.rpc('set_member_role', any()))
        .thenAnswer((_) async => {});

    await service.setMemberRole('g1', 'u2', 'admin');

    final params =
        verify(() => mockApiClient.rpc('set_member_role', captureAny()))
            .captured
            .single as Map;
    expect(params['p_group_id'], 'g1');
    expect(params['p_user_id'], 'u2');
    expect(params['p_role'], 'admin');
  });

  test('setTracking chama set_group_tracking e mapeia a resposta', () async {
    when(() => mockApiClient.rpc('set_group_tracking', any())).thenAnswer(
      (_) async => {
        'id': 'g1',
        'name': 'Vendas',
        'tracking_enabled': true,
        'created_by': 'u1',
        'created_at': '2026-10-25T12:00:00Z',
      },
    );

    final group = await service.setTracking('g1', true);

    expect(group.trackingEnabled, isTrue);
    final params =
        verify(() => mockApiClient.rpc('set_group_tracking', captureAny()))
            .captured
            .single as Map;
    expect(params['p_enabled'], true);
  });

  test('listMembers mapeia a lista retornada pela RPC', () async {
    when(() => mockApiClient.rpc('list_group_members', any())).thenAnswer(
      (_) async => [
        {
          'user_id': 'u1',
          'nome': 'Ana',
          'email': 'ana@x.com',
          'departamento': 'Gestão',
          'role': 'admin',
          'joined_at': '2026-10-25T12:00:00Z',
        },
      ],
    );

    final members = await service.listMembers('g1');

    expect(members, hasLength(1));
    expect(members.first.nome, 'Ana');
  });

  test('listTracking mapeia a lista retornada pela RPC', () async {
    when(() => mockApiClient.rpc('list_group_tracking', any())).thenAnswer(
      (_) async => [
        {
          'user_id': 'u1',
          'nome': 'Ana',
          'email': 'ana@x.com',
          'latitude': -26.5,
          'longitude': -49.0,
          'ultimo_visto': '2026-10-25T12:00:00Z',
        },
      ],
    );

    final points = await service.listTracking('g1');

    expect(points, hasLength(1));
    expect(points.first.latitude, -26.5);
  });

  test(
      'listMyGroups chama GET group_members com embed de groups sem invite_hash',
      () async {
    when(() => mockApiClient.get('group_members', query: any(named: 'query')))
        .thenAnswer(
      (_) async => [
        {
          'role': 'admin',
          'joined_at': '2026-10-25T12:00:00Z',
          'groups': {
            'id': 'g1',
            'name': 'Vendas',
            'tracking_enabled': false,
            'created_by': 'u1',
            'created_at': '2026-10-25T12:00:00Z',
          },
        },
      ],
    );

    final groups = await service.listMyGroups('u1');

    expect(groups, hasLength(1));
    expect(groups.first.group.name, 'Vendas');
    final query = verify(() => mockApiClient.get('group_members',
            query: captureAny(named: 'query'))).captured.single
        as Map<String, String>;
    expect(query['user_id'], 'eq.u1');
    expect(query['select'], isNot(contains('invite_hash')));
    expect(query['select'], contains('groups('));
  });
}
