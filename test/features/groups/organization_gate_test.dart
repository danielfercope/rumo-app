import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/features/auth/providers/auth_provider.dart';
import 'package:rumo_app/features/carteira/providers/carteira_provider.dart';
import 'package:rumo_app/features/carteira/services/carteira_service.dart';
import 'package:rumo_app/features/groups/models/group_member_model.dart';
import 'package:rumo_app/features/groups/models/group_model.dart';
import 'package:rumo_app/features/groups/presentation/organization_gate.dart';
import 'package:rumo_app/features/groups/presentation/group_onboarding_view.dart';
import 'package:rumo_app/features/groups/presentation/groups_home_page.dart';
import 'package:rumo_app/main.dart';
import 'package:rumo_app/features/groups/providers/group_provider.dart';
import 'package:rumo_app/features/groups/services/group_service.dart';

import '../../helpers/active_group.dart';

class MockGroupService extends Mock implements GroupService {}

/// Dependência falsa de myGroupsProvider (na vida real é o perfil): mudar isto
/// recarrega a lista como um "reload" — o caso que desmontaria o app.
final _dependencia = StateProvider<int>((ref) => 0);

class MockAuthController extends Mock implements AuthController {}

class MockCarteiraService extends Mock implements CarteiraService {}

/// Espião de ciclo de vida: conta quantas vezes o "app" foi montado.
class _AppProbe extends StatefulWidget {
  const _AppProbe(this.onInit);
  final VoidCallback onInit;

  @override
  State<_AppProbe> createState() => _AppProbeState();
}

class _AppProbeState extends State<_AppProbe> {
  @override
  void initState() {
    super.initState();
    widget.onInit();
  }

  @override
  Widget build(BuildContext context) =>
      const CupertinoPageScaffold(child: Center(child: Text('APP')));
}

void main() {
  late MockGroupService service;
  late MockAuthController auth;
  late MockCarteiraService carteira;
  late List<MyGroup> groups;
  late int appMounts;

  setUp(() {
    service = MockGroupService();
    auth = MockAuthController();
    carteira = MockCarteiraService();
    groups = [];
    appMounts = 0;
    when(() => auth.signOut()).thenAnswer((_) async {});
    when(() => service.listMembers(any())).thenAnswer((_) async => []);
    when(() => carteira.buscarConexao(any())).thenAnswer((_) async => null);
    when(() => carteira.ultimaSincronizacao(any()))
        .thenAnswer((_) async => null);
  });

  Future<ProviderContainer> pump(
    WidgetTester tester, {
    Future<List<MyGroup>> Function()? loader,
    Widget? child,
  }) async {
    tester.view.physicalSize = const Size(900, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final container = ProviderContainer(overrides: [
      groupServiceProvider.overrideWithValue(service),
      authControllerProvider.overrideWithValue(auth),
      carteiraServiceProvider.overrideWithValue(carteira),
      myGroupsProvider.overrideWith((ref) {
        ref.watch(_dependencia);
        return loader != null ? loader() : Future.value(List.of(groups));
      }),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: CupertinoApp(
        home: OrganizationGate(child: child ?? _AppProbe(() => appMounts++)),
      ),
    ));
    await tester.pump();
    await tester.pump();
    return container;
  }

  group('o app só monta depois de saber as organizações', () {
    testWidgets('enquanto carrega a lista, o app não aparece', (tester) async {
      await pump(tester, loader: () => Completer<List<MyGroup>>().future);

      expect(find.byType(CupertinoActivityIndicator), findsOneWidget);
      expect(find.text('APP'), findsNothing);
      expect(appMounts, 0);
    });

    testWidgets('falha ao carregar: não libera o app, oferece tentar de novo',
        (tester) async {
      var falhar = true;
      await pump(tester, loader: () async {
        if (falhar) throw Exception('sem rede');
        return [fakeMyGroup()];
      });

      expect(find.text('Não foi possível carregar suas organizações'),
          findsOneWidget);
      expect(find.text('APP'), findsNothing);

      falhar = false;
      await tester.tap(find.text('Tentar novamente'));
      await tester.pump();
      await tester.pump();

      expect(find.text('APP'), findsOneWidget);
    });

    testWidgets('recarregar a lista não desmonta o app (perderia o estado)',
        (tester) async {
      final lento = Completer<List<MyGroup>>();
      var primeira = true;
      final container = await pump(tester, loader: () {
        if (primeira) {
          primeira = false;
          return Future.value([fakeMyGroup()]);
        }
        return lento.future; // a 2ª carga demora
      });
      expect(appMounts, 1);

      container.read(_dependencia.notifier).state++; // ex.: o perfil mudou
      await tester.pump();

      expect(find.text('APP'), findsOneWidget);
      expect(find.byType(CupertinoActivityIndicator), findsNothing,
          reason: 'sem piscar o carregamento por cima do app');
      lento.complete([fakeMyGroup()]);
      await tester.pump();
      await tester.pump();
      expect(appMounts, 1, reason: 'o app não pode ser remontado');
    });
  });

  group('abas por situação do usuário', () {
    test('sem organização: só Organização e Perfil', () {
      expect(mainTabLabels(hasOrganization: false), ['Organização', 'Perfil']);
    });

    test('com organização: Radar, Leads, Perfil e Organização', () {
      expect(mainTabLabels(hasOrganization: true),
          ['Radar', 'Leads', 'Perfil', 'Organização']);
    });

    testWidgets('sem organização a barra não tem Radar nem Leads',
        (tester) async {
      await pump(tester, child: const MainNavigation());

      expect(find.text('Radar'), findsNothing);
      expect(find.text('Leads'), findsNothing);
      expect(find.text('Perfil'), findsOneWidget);
      expect(find.text('Organização'), findsWidgets);
      expect(find.byType(GroupOnboardingView), findsOneWidget);
      expect(find.text('Criar organização'), findsOneWidget);
      expect(find.text('Entrar na organização'), findsOneWidget);
    });
  });

  group('as duas formas de entrar numa organização', () {
    Group novo(String id) => Group(
          id: id,
          name: 'Nova',
          trackingEnabled: false,
          createdBy: 'u1',
          createdAt: DateTime(2026, 1, 1),
        );

    testWidgets('criar: abre o assistente pra conectar o CRM', (tester) async {
      when(() => service.createGroup('Agro Sul')).thenAnswer((_) async {
        groups = [fakeMyGroup(id: 'g-nova')];
        return novo('g-nova');
      });
      final container = await pump(tester, child: const GroupsHomePage());

      await tester.enterText(
          find.widgetWithText(CupertinoTextField, 'Nome da organização'),
          'Agro Sul');
      await tester.tap(find.text('Criar organização'));
      await tester.pumpAndSettle();

      verify(() => service.createGroup('Agro Sul')).called(1);
      expect(find.byType(GroupOnboardingView), findsNothing);
      expect(find.text('Passo 1 de 3'), findsOneWidget,
          reason: 'logo após criar, o assistente do CRM abre');
      expect(container.read(pendingCrmSetupGroupIdProvider), isNull,
          reason: 'abre uma vez só');
    });

    testWidgets('o assistente do CRM pode ser fechado e não reabre sozinho',
        (tester) async {
      when(() => service.createGroup(any())).thenAnswer((_) async {
        groups = [fakeMyGroup(id: 'g-nova')];
        return novo('g-nova');
      });
      final container = await pump(tester, child: const GroupsHomePage());
      await tester.enterText(
          find.widgetWithText(CupertinoTextField, 'Nome da organização'), 'X');
      await tester.tap(find.text('Criar organização'));
      await tester.pumpAndSettle();
      expect(find.text('Passo 1 de 3'), findsOneWidget);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      container.invalidate(myGroupsProvider); // recarrega a lista
      await tester.pumpAndSettle();

      expect(find.text('Passo 1 de 3'), findsNothing);
    });

    testWidgets('entrar com código: não abre o assistente do CRM',
        (tester) async {
      when(() => service.joinByHash('CODIGO')).thenAnswer((_) async {
        groups = [fakeMyGroup(id: 'g-existente', role: 'member')];
        return novo('g-existente');
      });
      final container = await pump(tester, child: const GroupsHomePage());

      await tester.enterText(
          find.widgetWithText(
              CupertinoTextField, 'Cole aqui o código de convite'),
          'CODIGO');
      await tester.tap(find.text('Entrar na organização'));
      await tester.pumpAndSettle();

      verify(() => service.joinByHash('CODIGO')).called(1);
      expect(find.byType(GroupOnboardingView), findsNothing);
      expect(find.text('Passo 1 de 3'), findsNothing,
          reason: 'quem entra numa existente não conecta CRM (já é da org)');
      expect(container.read(pendingCrmSetupGroupIdProvider), isNull);
    });

    testWidgets('código inválido: continua sem organização', (tester) async {
      when(() => service.joinByHash(any()))
          .thenThrow(Exception('convite inválido'));
      await pump(tester, child: const GroupsHomePage());

      await tester.enterText(
          find.widgetWithText(
              CupertinoTextField, 'Cole aqui o código de convite'),
          'ERRADO');
      await tester.tap(find.text('Entrar na organização'));
      await tester.pumpAndSettle();

      expect(find.textContaining('convite inválido'), findsOneWidget);
      expect(find.byType(GroupOnboardingView), findsOneWidget);
    });
  });
}
