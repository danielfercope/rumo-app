import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/core/services/api_client.dart';
import 'package:rumo_app/features/auth/providers/profile_provider.dart';
import 'package:rumo_app/features/groups/models/group_member_model.dart';
import 'package:rumo_app/features/groups/providers/group_provider.dart';
import 'package:rumo_app/features/groups/services/group_service.dart';

class MockGroupService extends Mock implements GroupService {}

UserProfile _profile() => const UserProfile(
      id: 'u1',
      email: 'u1@x.com',
      nome: 'Ana',
      departamento: 'Gestão',
      nivelAcesso: 'user',
    );

Map<String, dynamic> _myGroupJson({
  required String id,
  required String role,
  bool trackingEnabled = false,
}) => {
      'role': role,
      'joined_at': '2026-10-25T12:00:00Z',
      'groups': {
        'id': id,
        'name': 'Grupo $id',
        'tracking_enabled': trackingEnabled,
        'created_by': 'u1',
        'created_at': '2026-10-25T12:00:00Z',
      },
    };

void main() {
  late MockGroupService groupService;

  setUp(() {
    groupService = MockGroupService();
  });

  ProviderContainer buildContainer() {
    final container = ProviderContainer(overrides: [
      groupServiceProvider.overrideWithValue(groupService),
      profileProvider.overrideWith((ref) async => _profile()),
      apiClientProvider.overrideWithValue(ApiClient(baseUrl: 'http://x')),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  test('shouldTrackProvider é false quando não há nenhum grupo', () async {
    when(() => groupService.listMyGroups(any())).thenAnswer((_) async => []);
    final container = buildContainer();

    await container.read(myGroupsProvider.future);

    expect(container.read(shouldTrackProvider), isFalse);
  });

  test(
      'shouldTrackProvider é true quando ao menos um grupo tem tracking_enabled',
      () async {
    when(() => groupService.listMyGroups(any())).thenAnswer(
      (_) async => [
        MyGroup.fromJson(_myGroupJson(id: 'g1', role: 'member')),
        MyGroup.fromJson(
            _myGroupJson(id: 'g2', role: 'admin', trackingEnabled: true)),
      ],
    );
    final container = buildContainer();

    await container.read(myGroupsProvider.future);

    expect(container.read(shouldTrackProvider), isTrue);
  });

  test('isActiveGroupAdminProvider reflete o papel no grupo ativo', () async {
    when(() => groupService.listMyGroups(any())).thenAnswer(
      (_) async => [MyGroup.fromJson(_myGroupJson(id: 'g1', role: 'admin'))],
    );
    final container = buildContainer();

    await container.read(myGroupsProvider.future);

    expect(container.read(isActiveGroupAdminProvider), isTrue);
  });

  test(
      'activeGroupProvider cai pro primeiro grupo quando nenhum foi escolhido',
      () async {
    when(() => groupService.listMyGroups(any())).thenAnswer(
      (_) async => [
        MyGroup.fromJson(_myGroupJson(id: 'g1', role: 'member')),
        MyGroup.fromJson(_myGroupJson(id: 'g2', role: 'admin')),
      ],
    );
    final container = buildContainer();

    await container.read(myGroupsProvider.future);

    expect(container.read(activeGroupProvider)?.group.id, 'g1');
  });

  test(
      'activeGroupProvider respeita activeGroupIdProvider quando ele existe na lista',
      () async {
    when(() => groupService.listMyGroups(any())).thenAnswer(
      (_) async => [
        MyGroup.fromJson(_myGroupJson(id: 'g1', role: 'member')),
        MyGroup.fromJson(_myGroupJson(id: 'g2', role: 'admin')),
      ],
    );
    final container = buildContainer();
    await container.read(myGroupsProvider.future);

    container.read(activeGroupIdProvider.notifier).state = 'g2';

    expect(container.read(activeGroupProvider)?.group.id, 'g2');
  });
}
