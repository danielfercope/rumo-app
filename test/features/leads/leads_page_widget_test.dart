import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/features/leads/leads_page.dart';
import 'package:rumo_app/features/map/models/company_model.dart';
import 'package:rumo_app/features/map/presentation/filter_modal.dart';
import 'package:rumo_app/features/map/providers/company_provider.dart';
import 'package:rumo_app/features/map/providers/filter_provider.dart';

import '../../helpers/fakes.dart';

void main() {
  late FakeCompanyRepository repo;

  Future<ProviderContainer> pumpPage(WidgetTester tester) async {
    final container = ProviderContainer(overrides: [
      companyRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const CupertinoApp(home: LeadsPage()),
    ));
    await tester.pump();
    return container;
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(CupertinoSearchTextField), text);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
  }

  setUp(() {
    repo = FakeCompanyRepository(
      companies: [
        buildCompany(id: '1', fantasyName: 'Alfa', isClient: false),
        buildCompany(id: '2', fantasyName: 'Beta', isClient: true),
      ],
      options: {
        'segments': ['Varejo'],
        'products': ['P1'],
        'states': ['SC'],
        'cnaes': ['4712'],
        'cities': ['Joinville'],
        'stateToCities': {
          'SC': ['Joinville']
        },
      },
    );
  });

  testWidgets('mostra a mensagem inicial sem busca nem filtros',
      (tester) async {
    await pumpPage(tester);
    expect(find.textContaining('Digite um nome ou CNPJ'), findsOneWidget);
    expect(find.text('Meus Leads'), findsWidgets);
  });

  testWidgets('busca por nome mostra o chip e lista os resultados',
      (tester) async {
    await pumpPage(tester);
    await search(tester, 'alfa');

    expect(find.text('Buscando por nome'), findsOneWidget);
    expect(find.text('Alfa'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
    expect(repo.lastQuery, 'alfa');
    expect(repo.lastIsCnpj, isFalse);
  });

  testWidgets('busca numérica entra no modo CNPJ', (tester) async {
    await pumpPage(tester);
    await search(tester, '12.345.678');

    expect(find.text('Buscando por CNPJ'), findsOneWidget);
    expect(repo.lastIsCnpj, isTrue);
  });

  testWidgets('segmentos Ativos e Ganhos filtram por tipo de cliente',
      (tester) async {
    await pumpPage(tester);
    await search(tester, 'a');

    await tester.tap(find.text('Ativos'));
    await tester.pumpAndSettle();
    expect(find.text('Alfa'), findsOneWidget);
    expect(find.text('Beta'), findsNothing);

    await tester.tap(find.text('Ganhos'));
    await tester.pumpAndSettle();
    expect(find.text('Alfa'), findsNothing);
    expect(find.text('Beta'), findsOneWidget);

    await tester.tap(find.text('Todos'));
    await tester.pumpAndSettle();
    expect(find.text('Alfa'), findsOneWidget);
    expect(find.text('Beta'), findsOneWidget);
  });

  testWidgets('mostra mensagem quando nenhuma empresa é encontrada',
      (tester) async {
    repo.companies = <Company>[];
    await pumpPage(tester);
    await search(tester, 'zzz');
    expect(find.text('Nenhuma empresa encontrada.'), findsOneWidget);
  });

  testWidgets('mostra mensagem de erro quando a busca falha', (tester) async {
    repo.error = Exception('falhou');
    await pumpPage(tester);
    await search(tester, 'zzz');
    expect(find.text('Erro ao carregar empresas'), findsOneWidget);
  });

  testWidgets('limpar a busca volta ao estado inicial', (tester) async {
    await pumpPage(tester);
    await search(tester, 'alfa');
    expect(find.text('Alfa'), findsOneWidget);

    await tester.tap(find.byIcon(CupertinoIcons.xmark_circle_fill));
    await tester.pump();
    await tester.pump();

    expect(find.textContaining('Digite um nome ou CNPJ'), findsOneWidget);
    expect(find.text('Buscando por nome'), findsNothing);
  });

  testWidgets('filtros ativos aparecem como chips removíveis e "Limpar tudo"',
      (tester) async {
    final container = await pumpPage(tester);
    container.read(mapFiltersProvider.notifier)
      ..setSegment('Varejo')
      ..setProduct('P1')
      ..setType('client')
      ..setUf('SC')
      ..setCity('Joinville')
      ..setCnae('4712-1/00-muito-longo')
      ..setRadius(20);
    await tester.pumpAndSettle();

    expect(find.text('Varejo'), findsWidgets);
    expect(find.text('P1'), findsWidgets);
    expect(find.text('Cliente'), findsOneWidget);
    expect(find.text('SC'), findsWidgets);
    expect(find.text('Joinville'), findsWidgets);
    expect(find.textContaining('CNAE: 4712-1/00-mu…'), findsOneWidget);
    expect(find.text('20 km'), findsOneWidget);
    expect(find.text('7'), findsOneWidget); // badge de contagem

    await tester.ensureVisible(find.text('Limpar tudo'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Limpar tudo'));
    await tester.pumpAndSettle();
    expect(container.read(mapFiltersProvider).isEmpty, isTrue);
  });

  testWidgets('remover cada chip limpa o filtro correspondente',
      (tester) async {
    final container = await pumpPage(tester);
    container.read(mapFiltersProvider.notifier)
      ..setSegment('Varejo')
      ..setProduct('P1')
      ..setType('lead')
      ..setUf('SC')
      ..setCity('Joinville')
      ..setCnae('4712')
      ..setRadius(20);
    await tester.pumpAndSettle();
    expect(find.text('Lead'), findsOneWidget);

    // Remover o estado também descarta a cidade, então o número de toques
    // não é fixo: remove até não sobrar chip.
    for (var i = 0;
        i < 7 && find.byIcon(CupertinoIcons.xmark).evaluate().isNotEmpty;
        i++) {
      await tester.ensureVisible(find.byIcon(CupertinoIcons.xmark).first);
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(CupertinoIcons.xmark).first);
      await tester.pumpAndSettle();
    }
    expect(container.read(mapFiltersProvider).isEmpty, isTrue);
  });

  testWidgets('toque no filtro abre o FilterModal', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byIcon(CupertinoIcons.slider_horizontal_3));
    await tester.pumpAndSettle();
    expect(find.byType(FilterModal), findsOneWidget);
  });
}
