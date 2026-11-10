import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/features/groups/models/group_model.dart';
import 'package:rumo_app/features/groups/presentation/group_onboarding_view.dart';
import 'package:rumo_app/features/groups/providers/group_provider.dart';
import 'package:rumo_app/features/groups/services/group_service.dart';

class MockGroupService extends Mock implements GroupService {}

void main() {
  late MockGroupService service;
  var groupsFetched = 0;

  final created = Group(
    id: 'g1',
    name: 'Novo',
    trackingEnabled: false,
    createdBy: 'u1',
    createdAt: DateTime(2026, 1, 1),
  );

  setUp(() {
    service = MockGroupService();
    groupsFetched = 0;
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        groupServiceProvider.overrideWithValue(service),
        myGroupsProvider.overrideWith((ref) async {
          groupsFetched++;
          return [];
        }),
      ],
      child: const CupertinoApp(
        home: CupertinoPageScaffold(child: GroupOnboardingView()),
      ),
    ));
    // alguém precisa observar myGroupsProvider pra o invalidate recarregar
    final container = ProviderScope.containerOf(
        tester.element(find.byType(GroupOnboardingView)));
    container.listen(myGroupsProvider, (_, __) {});
    await tester.pump();
  }

  Finder field(String placeholder) =>
      find.widgetWithText(CupertinoTextField, placeholder);

  testWidgets('explica o estado vazio e oferece criar ou entrar',
      (tester) async {
    await pump(tester);

    expect(
        find.text('Você ainda não faz parte de nenhum grupo'), findsOneWidget);
    expect(find.text('Criar grupo'), findsOneWidget);
    expect(find.text('Entrar no grupo'), findsOneWidget);
  });

  testWidgets('criar sem nome pede o nome e não chama o serviço',
      (tester) async {
    await pump(tester);

    await tester.tap(find.text('Criar grupo'));
    await tester.pump();

    expect(find.text('Digite um nome pro grupo'), findsOneWidget);
    verifyNever(() => service.createGroup(any()));
  });

  testWidgets('entrar sem código pede o código', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Entrar no grupo'));
    await tester.pump();

    expect(find.text('Cole o código de convite'), findsOneWidget);
    verifyNever(() => service.joinByHash(any()));
  });

  testWidgets('criar grupo envia o nome sem espaços e recarrega os grupos',
      (tester) async {
    when(() => service.createGroup(any())).thenAnswer((_) async => created);
    await pump(tester);
    final before = groupsFetched;

    await tester.enterText(field('Nome do grupo'), '  Agro Sul  ');
    await tester.tap(find.text('Criar grupo'));
    await tester.pump();
    await tester.pump();

    verify(() => service.createGroup('Agro Sul')).called(1);
    expect(groupsFetched, greaterThan(before));
    expect(find.textContaining('Não foi possível'), findsNothing);
  });

  testWidgets('entrar com convite envia o código', (tester) async {
    when(() => service.joinByHash(any())).thenAnswer((_) async => created);
    await pump(tester);

    await tester.enterText(field('Cole aqui o código de convite'), ' ABC ');
    await tester.tap(find.text('Entrar no grupo'));
    await tester.pump();
    await tester.pump();

    verify(() => service.joinByHash('ABC')).called(1);
  });

  testWidgets('falha do serviço aparece como erro e libera os botões',
      (tester) async {
    when(() => service.createGroup(any()))
        .thenThrow(Exception('convite inválido'));
    await pump(tester);

    await tester.enterText(field('Nome do grupo'), 'X');
    await tester.tap(find.text('Criar grupo'));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Não foi possível concluir'), findsOneWidget);
    expect(find.textContaining('convite inválido'), findsOneWidget);
    final button = tester.widget<CupertinoButton>(
        find.widgetWithText(CupertinoButton, 'Criar grupo'));
    expect(button.onPressed, isNotNull);
  });
}
