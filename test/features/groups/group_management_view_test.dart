import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/features/groups/models/group_member_model.dart';
import 'package:rumo_app/features/groups/models/group_model.dart';
import 'package:rumo_app/features/groups/presentation/group_management_view.dart';
import 'package:rumo_app/features/groups/providers/group_provider.dart';

void main() {
  final group = Group(
    id: 'g1',
    name: 'Agro Sul',
    trackingEnabled: false,
    createdBy: 'u1',
    createdAt: DateTime(2026, 1, 1),
  );

  GroupMember member(String id, String nome, String role) => GroupMember(
        userId: id,
        nome: nome,
        email: '$id@x.com',
        departamento: 'Vendas',
        role: role,
        joinedAt: DateTime(2026, 1, 1),
      );

  Future<void> pump(WidgetTester tester, {required String role}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        myGroupsProvider.overrideWith((ref) async => [
              MyGroup(group: group, role: role, joinedAt: DateTime(2026, 1, 1)),
            ]),
        groupMembersProvider('g1').overrideWith((ref) async => [
              member('ana', 'Ana Souza', 'admin'),
              member('beto', 'Beto Lima', 'member'),
            ]),
      ],
      child: const CupertinoApp(
        home: CupertinoPageScaffold(child: GroupManagementView()),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  testWidgets('admin vê cabeçalho, membros com papel e as seções de gestão',
      (tester) async {
    await pump(tester, role: 'admin');

    expect(find.text('Agro Sul'), findsOneWidget);
    expect(find.text('2 membros · Você administra'), findsOneWidget);
    expect(find.text('Ana Souza'), findsOneWidget);
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Membro'), findsOneWidget);
    expect(find.text('Convite do grupo'), findsOneWidget);
    expect(find.text('Ativado para este grupo'), findsNothing);
    expect(find.text('Desativado para este grupo'), findsOneWidget);
    expect(find.text('Ver mapa da equipe'), findsNothing);
  });

  testWidgets('tocar num membro oferece promover/remover admin',
      (tester) async {
    await pump(tester, role: 'admin');

    await tester.tap(find.text('Beto Lima'));
    await tester.pumpAndSettle();
    expect(find.text('Promover a admin'), findsOneWidget);

    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ana Souza'));
    await tester.pumpAndSettle();
    expect(find.text('Remover admin'), findsOneWidget);
  });

  testWidgets('membro comum só vê a lista, sem ações de gestão',
      (tester) async {
    await pump(tester, role: 'member');

    expect(find.text('Ana Souza'), findsOneWidget);
    expect(find.text('Convite do grupo'), findsNothing);
    expect(find.text('Integração com CRM'), findsNothing);
    await tester.tap(find.text('Beto Lima'));
    await tester.pumpAndSettle();
    expect(find.text('Promover a admin'), findsNothing);
  });
}
