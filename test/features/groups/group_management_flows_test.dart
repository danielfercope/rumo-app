import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/features/carteira/providers/carteira_provider.dart';
import 'package:rumo_app/features/carteira/services/carteira_service.dart';
import 'package:rumo_app/features/groups/models/group_member_model.dart';
import 'package:rumo_app/features/groups/models/group_model.dart';
import 'package:rumo_app/features/groups/presentation/group_management_view.dart';
import 'package:rumo_app/features/groups/providers/group_provider.dart';
import 'package:rumo_app/features/groups/services/group_service.dart';

class MockGroupService extends Mock implements GroupService {}

class MockCarteiraService extends Mock implements CarteiraService {}

void main() {
  late MockGroupService service;
  late MockCarteiraService carteira;
  var groupsFetched = 0;

  Group makeGroup(String id, String name, {bool tracking = false}) => Group(
        id: id,
        name: name,
        trackingEnabled: tracking,
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

  MyGroup mine(Group g, String role) =>
      MyGroup(group: g, role: role, joinedAt: DateTime(2026, 1, 1));

  setUp(() {
    service = MockGroupService();
    carteira = MockCarteiraService();
    groupsFetched = 0;
    when(() => carteira.buscarConexao(any())).thenAnswer((_) async => null);
    when(() => carteira.ultimaSincronizacao(any()))
        .thenAnswer((_) async => null);
  });

  Future<void> pump(
    WidgetTester tester, {
    List<MyGroup>? groups,
    Future<List<GroupMember>> Function()? members,
    List<Override> extra = const [],
  }) async {
    final list = groups ?? [mine(makeGroup('g1', 'Agro Sul'), 'admin')];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        groupServiceProvider.overrideWithValue(service),
        carteiraServiceProvider.overrideWithValue(carteira),
        myGroupsProvider.overrideWith((ref) async {
          groupsFetched++;
          return list;
        }),
        for (final g in list)
          groupMembersProvider(g.group.id).overrideWith((ref) => members != null
              ? members()
              : Future.value([
                  member('ana', 'Ana Souza', 'admin'),
                  member('beto', 'Beto Lima', 'member'),
                ])),
        ...extra,
      ],
      child: const CupertinoApp(
        home: CupertinoPageScaffold(child: GroupManagementView()),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  group('rastreamento', () {
    testWidgets('o interruptor liga o rastreamento e recarrega os grupos',
        (tester) async {
      when(() => service.setTracking('g1', true))
          .thenAnswer((_) async => makeGroup('g1', 'Agro Sul', tracking: true));
      await pump(tester);
      final before = groupsFetched;

      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pump();
      await tester.pump();

      verify(() => service.setTracking('g1', true)).called(1);
      expect(groupsFetched, greaterThan(before));
    });

    testWidgets('com rastreamento ativo mostra o atalho do mapa da equipe',
        (tester) async {
      await pump(tester, groups: [
        mine(makeGroup('g1', 'Agro Sul', tracking: true), 'admin'),
      ]);

      expect(find.text('Ativado para este grupo'), findsOneWidget);
      expect(find.text('Ver mapa da equipe'), findsOneWidget);
    });

    testWidgets('falha ao ligar mostra o erro', (tester) async {
      when(() => service.setTracking(any(), any()))
          .thenThrow(Exception('sem permissão'));
      await pump(tester);

      await tester.tap(find.byType(CupertinoSwitch));
      await tester.pumpAndSettle();

      expect(find.text('Não foi possível concluir'), findsOneWidget);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      expect(find.text('Não foi possível concluir'), findsNothing);
    });
  });

  group('papéis dos membros', () {
    Future<void> openRoleMenu(WidgetTester tester, String name) async {
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }

    testWidgets('promover pede confirmação e então chama o serviço',
        (tester) async {
      when(() => service.setMemberRole(any(), any(), any()))
          .thenAnswer((_) async {});
      await pump(tester);

      await openRoleMenu(tester, 'Beto Lima');
      await tester.tap(find.text('Promover a admin'));
      await tester.pumpAndSettle();
      expect(find.textContaining('passará a administrar'), findsOneWidget);
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      verify(() => service.setMemberRole('g1', 'beto', 'admin')).called(1);
    });

    testWidgets('remover admin é uma ação destrutiva com outro texto',
        (tester) async {
      when(() => service.setMemberRole(any(), any(), any()))
          .thenAnswer((_) async {});
      await pump(tester);

      await openRoleMenu(tester, 'Ana Souza');
      await tester.tap(find.text('Remover admin'));
      await tester.pumpAndSettle();
      expect(
          find.textContaining('deixará de ser administrador'), findsOneWidget);
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      verify(() => service.setMemberRole('g1', 'ana', 'member')).called(1);
    });

    testWidgets('cancelar na confirmação não altera nada', (tester) async {
      await pump(tester);

      await openRoleMenu(tester, 'Beto Lima');
      await tester.tap(find.text('Promover a admin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      verifyNever(() => service.setMemberRole(any(), any(), any()));
    });

    testWidgets('falha do serviço mostra o diálogo de erro', (tester) async {
      when(() => service.setMemberRole(any(), any(), any()))
          .thenThrow(Exception('último admin'));
      await pump(tester);

      await openRoleMenu(tester, 'Ana Souza');
      await tester.tap(find.text('Remover admin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      expect(find.text('Não foi possível concluir'), findsOneWidget);
      expect(find.textContaining('último admin'), findsOneWidget);
    });
  });

  group('convite', () {
    Future<void> openInvite(WidgetTester tester) async {
      await pump(tester, extra: [
        groupInviteProvider('g1').overrideWith((ref) async => 'CONVITE-123'),
      ]);
      await tester.tap(find.text('Convite do grupo'));
      await tester.pumpAndSettle();
    }

    testWidgets('mostra o código e copia para a área de transferência',
        (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await openInvite(tester);

      expect(find.text('CONVITE-123'), findsOneWidget);
      await tester.tap(find.text('Copiar'));
      await tester.pumpAndSettle();

      expect(copied, 'CONVITE-123');
      expect(find.text('CONVITE-123'), findsNothing); // folha fechou
    });

    testWidgets('regenerar pede confirmação e invalida o código antigo',
        (tester) async {
      when(() => service.regenerateInvite('g1'))
          .thenAnswer((_) async => makeGroup('g1', 'Agro Sul'));
      await openInvite(tester);

      await tester.tap(find.text('Regenerar'));
      await tester.pumpAndSettle();
      expect(find.textContaining('deixará de funcionar'), findsOneWidget);
      await tester.tap(find.text('Regenerar').last);
      await tester.pumpAndSettle();

      verify(() => service.regenerateInvite('g1')).called(1);
    });

    testWidgets('cancelar a regeneração mantém o código', (tester) async {
      await openInvite(tester);

      await tester.tap(find.text('Regenerar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      verifyNever(() => service.regenerateInvite(any()));
    });

    testWidgets('Fechar dispensa a folha sem copiar', (tester) async {
      await openInvite(tester);

      await tester.tap(find.text('Fechar'));
      await tester.pumpAndSettle();

      expect(find.text('Convite do grupo'), findsOneWidget); // só a linha
      expect(find.text('CONVITE-123'), findsNothing);
    });
  });

  group('vários grupos e estados', () {
    testWidgets('sem seletor de segmentos; "Trocar" muda a organização ativa',
        (tester) async {
      await pump(tester, groups: [
        mine(makeGroup('g1', 'Agro Sul'), 'admin'),
        mine(makeGroup('g2', 'Agro Norte'), 'member'),
      ]);
      expect(
          find.byType(CupertinoSlidingSegmentedControl<String>), findsNothing);
      expect(find.text('Convite do grupo'), findsOneWidget); // admin em g1

      await tester.tap(find.text('Trocar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agro Norte'));
      await tester.pumpAndSettle();

      // em g2 o usuário é só membro: some a gestão
      expect(find.text('Convite do grupo'), findsNothing);
    });

    testWidgets('uma organização só: sem botão Trocar e com aviso de carteira',
        (tester) async {
      await pump(tester);

      expect(find.text('Trocar'), findsNothing);
      expect(find.textContaining('pertencem só a esta organização'),
          findsOneWidget);
    });

    testWidgets('um membro só: texto no singular', (tester) async {
      await pump(tester,
          members: () async => [member('ana', 'Ana Souza', 'admin')]);

      expect(find.text('1 membro · Você administra'), findsOneWidget);
    });

    testWidgets('mostra o indicador enquanto carrega os membros',
        (tester) async {
      await pump(tester, members: () => Completer<List<GroupMember>>().future);

      expect(find.byType(CupertinoActivityIndicator), findsWidgets);
      expect(find.text('Ana Souza'), findsNothing);
    });

    testWidgets('erro ao carregar os membros aparece na lista', (tester) async {
      await pump(tester, members: () async => throw Exception('falhou'));

      expect(find.textContaining('Erro ao carregar membros'), findsOneWidget);
    });

    testWidgets('membro sem nome mostra o e-mail como título', (tester) async {
      await pump(tester, members: () async => [member('x', '', 'member')]);

      expect(find.text('x@x.com'), findsWidgets);
      expect(find.text('?'), findsWidgets); // inicial do avatar sem nome
    });
  });
}
