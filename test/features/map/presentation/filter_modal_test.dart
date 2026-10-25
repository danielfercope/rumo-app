import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/features/map/presentation/filter_modal.dart';
import 'package:rumo_app/features/map/providers/company_provider.dart';
import 'package:rumo_app/features/map/providers/filter_provider.dart';

import '../../../helpers/fakes.dart';

void main() {
  late FakeCompanyRepository repo;
  late ProviderContainer container;

  setUp(() {
    repo = FakeCompanyRepository(options: {
      'segments': ['Varejo', 'Indústria'],
      'products': ['P1'],
      'states': ['SC', 'SP'],
      'cnaes': ['4712'],
      'cities': ['Joinville', 'Santos'],
      'stateToCities': {
        'SC': ['Joinville'],
        'SP': ['Santos'],
      },
    });
  });

  Future<void> pumpModal(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    container = ProviderContainer(overrides: [
      companyRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(home: CupertinoPageScaffold(child: FilterModal())),
    ));
    await tester.pumpAndSettle();
  }

  /// Campo (GestureDetector) logo abaixo do rótulo informado.
  Finder fieldOf(String label) => find
      .descendant(
        of: find
            .ancestor(of: find.text(label), matching: find.byType(Column))
            .first,
        matching: find.byType(GestureDetector),
      )
      .first;

  Future<void> pick(WidgetTester tester, String label, String option) async {
    await tester.ensureVisible(fieldOf(label));
    await tester.pumpAndSettle();
    await tester.tap(fieldOf(label));
    await tester.pumpAndSettle();
    await tester.tap(find.text(option).last);
    await tester.pumpAndSettle();
  }

  testWidgets('mostra o carregamento e depois as seções', (tester) async {
    await pumpModal(tester);
    expect(find.text('Filtros Avançados'), findsOneWidget);
    expect(find.text('Raio de Destaque no Mapa'), findsOneWidget);
    expect(find.text('5 km'), findsOneWidget);
    expect(find.text('Segmento'), findsOneWidget);
  });

  testWidgets('mostra erro quando as opções não carregam', (tester) async {
    repo.error = Exception('falhou');
    await pumpModal(tester);
    expect(find.text('Erro ao carregar opções'), findsOneWidget);
  });

  testWidgets('Aplicar grava os filtros escolhidos no provider',
      (tester) async {
    await pumpModal(tester);

    await pick(tester, 'Segmento', 'Varejo');
    await pick(tester, 'Produto', 'P1');
    await pick(tester, 'CNAE', '4712');

    await tester.tap(find.text('Cliente'));
    await tester.pumpAndSettle();

    tester.widget<CupertinoSlider>(find.byType(CupertinoSlider)).onChanged!(500);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();

    final f = container.read(mapFiltersProvider);
    expect(f.segment, 'Varejo');
    expect(f.product, 'P1');
    expect(f.cnae, '4712');
    expect(f.type, 'client');
    expect(f.radius, 500);
  });

  testWidgets('escolher estado restringe as cidades ao estado',
      (tester) async {
    await pumpModal(tester);

    await pick(tester, 'Estado (UF)', 'SC');
    await tester.ensureVisible(fieldOf('Cidade'));
    await tester.pumpAndSettle();
    await tester.tap(fieldOf('Cidade'));
    await tester.pumpAndSettle();

    expect(find.text('Joinville'), findsOneWidget);
    expect(find.text('Santos'), findsNothing);
  });

  testWidgets('sem estado, a lista de cidades traz todas', (tester) async {
    await pumpModal(tester);
    await tester.ensureVisible(fieldOf('Cidade'));
    await tester.pumpAndSettle();
    await tester.tap(fieldOf('Cidade'));
    await tester.pumpAndSettle();
    expect(find.text('Joinville'), findsOneWidget);
    expect(find.text('Santos'), findsOneWidget);
  });

  testWidgets('o botão de limpar do campo remove o valor selecionado',
      (tester) async {
    await pumpModal(tester);
    await pick(tester, 'Segmento', 'Varejo');
    expect(find.text('Varejo'), findsOneWidget);

    await tester.tap(find.byIcon(CupertinoIcons.clear_circled_solid));
    await tester.pumpAndSettle();
    expect(find.text('Varejo'), findsNothing);
  });

  testWidgets('"Limpar Todos" zera os filtros temporários', (tester) async {
    container = ProviderContainer(overrides: [
      companyRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    container.read(mapFiltersProvider.notifier)
      ..setSegment('Varejo')
      ..setType('lead');
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(home: CupertinoPageScaffold(child: FilterModal())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Varejo'), findsOneWidget);

    await tester.ensureVisible(find.text('Limpar Todos'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Limpar Todos'));
    await tester.pumpAndSettle();
    expect(find.text('Varejo'), findsNothing);

    await tester.tap(find.text('Aplicar'));
    await tester.pumpAndSettle();
    expect(container.read(mapFiltersProvider).isEmpty, isTrue);
  });

  group('SearchSelectionSheet', () {
    testWidgets('filtra as opções pelo texto digitado e seleciona',
        (tester) async {
      String? selected;
      await tester.pumpWidget(CupertinoApp(
        home: SearchSelectionSheet(
          title: 'Segmento',
          options: const ['Varejo', 'Indústria', 'Varejista'],
          onSelected: (v) => selected = v,
        ),
      ));

      expect(find.text('Varejo'), findsOneWidget);
      expect(find.text('Indústria'), findsOneWidget);

      await tester.enterText(find.byType(CupertinoSearchTextField), 'vareji');
      await tester.pump();
      expect(find.text('Indústria'), findsNothing);
      expect(find.text('Varejo'), findsNothing);

      await tester.tap(find.text('Varejista'));
      await tester.pumpAndSettle();
      expect(selected, 'Varejista');
    });
  });
}
