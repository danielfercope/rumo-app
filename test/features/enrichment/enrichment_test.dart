import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/core/services/api_client.dart';
import 'package:rumo_app/features/company/crm_service.dart';
import 'package:rumo_app/features/enrichment/models/enrichment_models.dart';
import 'package:rumo_app/features/enrichment/presentation/enrichment_cards.dart';
import 'package:rumo_app/features/enrichment/services/enrichment_service.dart';
import 'package:rumo_app/features/map/models/company_model.dart';
import 'package:rumo_app/features/map/presentation/company_details_modal.dart';

import '../../helpers/active_group.dart';
import 'enrichment_fixtures.dart';

class MockApiClient extends Mock implements ApiClient {}

class MockCrmService extends Mock implements CrmService {}

Future<void> pumpCards(
    WidgetTester tester, FakeEnrichmentService service) async {
  tester.view.physicalSize = const Size(800, 4000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [enrichmentServiceProvider.overrideWithValue(service)],
    child: const CupertinoApp(
      home: CupertinoPageScaffold(
        child: SingleChildScrollView(
          child: CompanyEnrichmentCards(groupId: 'g1', cnpj: '07175725000160'),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('modelos', () {
    test('Receita: regime atual, endereço numa linha e sócios', () {
      final d = ReceitaData.fromJson(receitaJson);
      expect(d.ativa, isTrue);
      expect(d.regimeAtual, 'Lucro Real');
      expect(d.endereco,
          'Avenida Prefeito Waldemar Grubba, 3000, Vila Lalau, Jaragua do Sul - SC, 89256-900');
      expect(d.socios.map((s) => s.tipo), ['PF', 'PJ']);
      expect(d.cnaesSecundarios, hasLength(8));
      expect(d.telefones.first, '(47) 3276-4775');
    });

    test('Receita: MEI e Simples vencem a forma declarada', () {
      final mei = ReceitaData.fromJson({
        ...receitaJson,
        'mei': {'optante': true},
        'simples': {'optante': true},
      });
      expect(mei.regimeAtual, 'MEI');
      final simples = ReceitaData.fromJson({
        ...receitaJson,
        'simples': {'optante': true}
      });
      expect(simples.regimeAtual, 'Simples Nacional');
    });

    test('Compras: variação contra os 12 meses anteriores', () {
      final c = ComprasData.fromJson(comprasJson);
      expect(c.recente.vendeu, isTrue);
      expect(c.variacao, closeTo(0.04, 0.001));
      expect(c.contratacoes.single.data, DateTime(2026, 4, 30));
      expect(ComprasData.fromJson({'ultimos_12_meses': null}).variacao, isNull);
    });

    test('envelope: status desconhecido vira indisponível', () {
      final r = EnrichmentResult.fromJson(
          EnrichmentSource.google, {'status': 'xpto', 'dados': null});
      expect(r.status, EnrichmentStatus.indisponivel);
      expect(r.hasData, isFalse);
    });

    test('serviço chama a rota da fonte com organização e CNPJ', () async {
      final api = MockApiClient();
      when(() => api.backendRequest('GET', 'enriquecimento/compras',
              body: any(named: 'body'), query: any(named: 'query')))
          .thenAnswer((_) async => envelope('compras', comprasJson));

      final r = await EnrichmentService(api)
          .fetch('g1', '07175725000160', EnrichmentSource.compras);

      final query = verify(() => api.backendRequest(
          'GET', 'enriquecimento/compras',
          body: any(named: 'body'),
          query: captureAny(named: 'query'))).captured.single;
      expect(query, {'group_id': 'g1', 'cnpj': '07175725000160'});
      expect(r.hasData, isTrue);
      expect(r.origem, 'Compras.gov.br e PNCP');
    });
  });

  group('blocos', () {
    testWidgets('resumos ficam visíveis sem abrir nada', (tester) async {
      await pumpCards(tester, FakeEnrichmentService(allSources()));

      // Google: só um convite, sem consultar (é cobrado)
      expect(find.text('No Google'), findsOneWidget);
      expect(find.text('Ver no Google'), findsOneWidget);
      expect(find.text('4,7'), findsNothing);
      // Receita
      expect(find.text('Ativa'), findsOneWidget);
      expect(find.text('Lucro Real'), findsOneWidget);
      expect(find.text('Porte: Demais'), findsOneWidget);
      expect(find.textContaining('Capital R\$ 9,3 bi'), findsOneWidget);
      expect(find.textContaining('2 sócios/administradores'), findsOneWidget);
      // Compras
      expect(find.byKey(const ValueKey('compras-total')), findsOneWidget);
      expect(find.text('R\$ 1,2 mi'), findsOneWidget);
      expect(find.text('+4% vs. ano anterior'), findsOneWidget);
      expect(find.text('Habilitada no SICAF'), findsOneWidget);
      expect(find.text('29'), findsOneWidget);
      // Economia
      expect(find.text('Economia de Jaragua Do Sul (SC)'), findsOneWidget);
      expect(find.text('203 mil'), findsOneWidget);
      expect(find.text('US\$ 976 mi'), findsOneWidget);
      // detalhes fechados
      expect(find.text('Quadro de sócios e administradores'.toUpperCase()),
          findsNothing);
    });

    testWidgets('Google só é consultado ao tocar em "Ver no Google"',
        (tester) async {
      final service = FakeEnrichmentService(allSources());
      await pumpCards(tester, service);
      expect(service.calls, isNot(contains(EnrichmentSource.google)));

      await tester.tap(find.text('Ver no Google'));
      await tester.pumpAndSettle();

      expect(
          service.calls.where((c) => c == EnrichmentSource.google).length, 1);
      expect(find.byKey(const ValueKey('google-foto')), findsOneWidget);
      expect(find.text('Foto: Alexandre de Castro · Google'), findsOneWidget);
      expect(find.text('WEG S/A'), findsOneWidget);
      expect(find.text('4,7'), findsOneWidget);
      expect(find.text('  (405 avaliações)'), findsOneWidget);
      expect(find.text('Aberto agora'), findsOneWidget);
      expect(find.text('Maps'), findsOneWidget);
      expect(find.text('Site'), findsOneWidget);
    });

    testWidgets('Google sem foto: só os dados', (tester) async {
      final semFoto = Map<String, dynamic>.from(googleJson)..remove('foto');
      await pumpCards(
          tester,
          FakeEnrichmentService({
            ...allSources(),
            EnrichmentSource.google: envelope('google', semFoto)
          }));
      await tester.tap(find.text('Ver no Google'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('google-foto')), findsNothing);
      expect(find.text('4,7'), findsOneWidget);
    });

    testWidgets('Google: empresa não encontrada', (tester) async {
      await pumpCards(
          tester,
          FakeEnrichmentService({
            ...allSources(),
            EnrichmentSource.google: envelope('google', null, status: 'vazio'),
          }));
      await tester.tap(find.text('Ver no Google'));
      await tester.pumpAndSettle();
      expect(find.text('Empresa não encontrada no Google.'), findsOneWidget);
    });

    testWidgets('tocar abre os detalhes: sócios, CNAEs, tributação',
        (tester) async {
      await pumpCards(tester, FakeEnrichmentService(allSources()));

      await tester.tap(find.text('Receita Federal'));
      await tester.pump();

      expect(find.text('QUADRO DE SÓCIOS E ADMINISTRADORES'), findsOneWidget);
      expect(find.text('Alberto Yoshikazu Kuba'), findsOneWidget);
      expect(find.text('Diretor · desde 2020 · Entre 41 a 50 anos'),
          findsOneWidget);
      expect(find.text('e mais 2 atividades secundárias'), findsOneWidget);
      expect(find.text('Lucro Real (2023–2024) · Lucro Presumido (2021)'),
          findsOneWidget);
      expect(find.text('R\$ 9.350.000.000,00'), findsOneWidget);
    });

    testWidgets('vendas ao governo: maiores vendas com link do PNCP',
        (tester) async {
      await pumpCards(tester, FakeEnrichmentService(allSources()));
      await tester.tap(find.text('Vendas ao governo'));
      await tester.pump();

      expect(find.text('Tribunal de Contas do Estado do Tocantins'),
          findsOneWidget);
      expect(find.text('Ver no PNCP'), findsOneWidget);
      expect(find.text('BA, DF, PR, SP'), findsOneWidget);
    });

    testWidgets('sem vendas ao governo diz isso numa linha', (tester) async {
      await pumpCards(
          tester,
          FakeEnrichmentService({
            ...allSources(),
            EnrichmentSource.compras: envelope('compras', {
              'sicaf': {'cadastrado': false, 'habilitado': false},
              'ultimos_12_meses': {'contratacoes': 0, 'valor': 0},
              '12_meses_anteriores': {'contratacoes': 0, 'valor': 0},
              'contratacoes': [],
            }),
          }));
      expect(find.text('Nenhuma venda a órgãos públicos nos últimos 24 meses.'),
          findsOneWidget);
      expect(find.text('Sem cadastro no SICAF'), findsOneWidget);
    });

    testWidgets('Google desligado (após pedir) e cidade sem dado: blocos somem',
        (tester) async {
      await pumpCards(
          tester,
          FakeEnrichmentService({
            EnrichmentSource.receita: envelope('receita', receitaJson),
            EnrichmentSource.compras: envelope('compras', comprasJson),
            EnrichmentSource.google:
                envelope('google', null, status: 'desativado'),
            EnrichmentSource.municipio:
                envelope('municipio', null, status: 'vazio'),
            EnrichmentSource.comex: envelope('comex', null, status: 'vazio'),
          }));
      expect(find.textContaining('Economia'), findsNothing);
      await tester.tap(find.text('Ver no Google'));
      await tester.pumpAndSettle();
      expect(find.text('No Google'), findsNothing);
      expect(find.text('Receita Federal'), findsOneWidget);
    });

    testWidgets('fonte fora do ar: aviso e "Tentar de novo" reconsulta',
        (tester) async {
      final service = FakeEnrichmentService({
        ...allSources(),
        EnrichmentSource.compras: envelope('compras', null,
            status: 'indisponivel', mensagem: 'A fonte não respondeu agora.'),
      });
      await pumpCards(tester, service);
      expect(find.text('A fonte não respondeu agora.'), findsOneWidget);

      final before =
          service.calls.where((c) => c == EnrichmentSource.compras).length;
      service.responses[EnrichmentSource.compras] =
          envelope('compras', comprasJson);
      await tester.tap(find.text('Tentar de novo'));
      await tester.pumpAndSettle();
      expect(service.calls.where((c) => c == EnrichmentSource.compras).length,
          before + 1);
      expect(find.text('R\$ 1,2 mi'), findsOneWidget);
    });

    testWidgets('dado antigo vem marcado como desatualizado', (tester) async {
      await pumpCards(
          tester,
          FakeEnrichmentService({
            ...allSources(),
            EnrichmentSource.receita:
                envelope('receita', receitaJson, stale: true),
          }));
      expect(find.text('desatualizado'), findsOneWidget);
    });
  });

  group('detalhes da empresa', () {
    late MockCrmService crm;

    setUp(() {
      crm = MockCrmService();
      when(() => crm.getNotesWithOwners(any())).thenAnswer((_) async => []);
      when(() => crm.getContacts(any())).thenAnswer((_) async => []);
    });

    Future<void> pumpModal(WidgetTester tester, Company company,
        FakeEnrichmentService service) async {
      tester.view.physicalSize = const Size(800, 5000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          crmServiceProvider.overrideWithValue(crm),
          activeGroupOverride(),
          enrichmentServiceProvider.overrideWithValue(service),
        ],
        child: CupertinoApp(
          home: CupertinoPageScaffold(
              child: CompanyDetailsModal(company: company)),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets(
        'empresa sem contato no cadastro usa os da Receita; '
        'campos sem dado não aparecem; o Google não é consultado sozinho',
        (tester) async {
      final company = Company(
        id: 'c1',
        name: 'WEG EQUIPAMENTOS ELETRICOS S/A',
        cnpj: '07175725000160',
        isClient: false,
        carteiraStatus: 'lead',
        distance: 3,
      );
      final service = FakeEnrichmentService(allSources());
      await pumpModal(tester, company, service);

      expect(service.calls, isNot(contains(EnrichmentSource.google)));
      expect(find.text('Contatos e Endereço'), findsOneWidget);
      expect(find.text('(47) 3276-4775'), findsOneWidget);
      expect(find.text('fiscal@weg.net'), findsOneWidget);
      expect(find.textContaining('Avenida Prefeito Waldemar Grubba, 3000'),
          findsOneWidget);
      // sem segmento/faturamento/funcionários e sem crédito: nada disso aparece
      expect(find.text('Segmento'), findsNothing);
      expect(find.text('Fat. Estimado'), findsNothing);
      expect(find.text('Funcionários'), findsNothing);
      expect(find.text('Dados de Crédito e Dívida'), findsNothing);
      expect(find.text('N/A'), findsNothing);
      expect(find.text('Não informado'), findsNothing);
      // CNAE e natureza já estão no bloco da Receita
      expect(find.text('Informações'), findsNothing);
    });

    testWidgets('contatos vêm antes dos blocos de dados públicos',
        (tester) async {
      final company = Company(
        id: 'c1',
        name: 'WEG',
        cnpj: '07175725000160',
        telefone: '4733334444',
        isClient: false,
      );
      await pumpModal(tester, company, FakeEnrichmentService(allSources()));

      final contatos = tester.getTopLeft(find.text('Contatos e Endereço')).dy;
      final receita = tester.getTopLeft(find.text('Receita Federal')).dy;
      final google = tester.getTopLeft(find.text('No Google')).dy;
      expect(contatos, lessThan(google));
      expect(google, lessThan(receita));
      // o telefone do cadastro tem prioridade sobre o da Receita
      expect(find.text('4733334444'), findsOneWidget);
      expect(find.text('(47) 3276-4775'), findsNothing);
    });
  });
}
