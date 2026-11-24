import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/core/services/api_client.dart';
import 'package:rumo_app/features/company/crm_service.dart';
import 'package:rumo_app/features/diagnosis/services/diagnosis_service.dart';
import 'package:rumo_app/features/enrichment/models/enrichment_models.dart';
import 'package:rumo_app/features/enrichment/presentation/enrichment_cards.dart';
import 'package:rumo_app/features/enrichment/services/enrichment_service.dart';
import 'package:rumo_app/features/map/models/company_model.dart';
import 'package:rumo_app/features/map/presentation/company_details_modal.dart';

import '../../helpers/active_group.dart';
import '../diagnosis/diagnosis_fixtures.dart';
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
  group('porteLabel', () {
    test('traduz os portes da Receita', () {
      expect(porteLabel('DEMAIS'), 'Médio/grande (acima de EPP)');
      expect(porteLabel('05 - DEMAIS'), 'Médio/grande (acima de EPP)');
      expect(porteLabel('MICRO EMPRESA'), 'Microempresa (ME)');
      expect(porteLabel('ME'), 'Microempresa (ME)');
      expect(porteLabel('EMPRESA DE PEQUENO PORTE'), 'Pequeno porte (EPP)');
      expect(porteLabel('EPP'), 'Pequeno porte (EPP)');
    });

    test('esconde o que não informa nada', () {
      expect(porteLabel(null), isNull);
      expect(porteLabel(''), isNull);
      expect(porteLabel('NÃO INFORMADO'), isNull);
      expect(porteLabel('00 - Não informado'), isNull);
    });

    test('valor desconhecido aparece como veio, só capitalizado', () {
      expect(porteLabel('OUTRO PORTE'), 'Outro Porte');
    });
  });

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

      // O Google não é um bloco: alimenta o topo dos detalhes
      expect(find.text('No Google'), findsNothing);
      // Receita
      expect(find.text('Ativa'), findsOneWidget);
      expect(find.text('Lucro Real'), findsOneWidget);
      expect(find.text('Porte: Médio/grande (acima de EPP)'), findsOneWidget);
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

    testWidgets('cidade sem dado: o bloco de economia some', (tester) async {
      await pumpCards(
          tester,
          FakeEnrichmentService({
            EnrichmentSource.receita: envelope('receita', receitaJson),
            EnrichmentSource.compras: envelope('compras', comprasJson),
            EnrichmentSource.municipio:
                envelope('municipio', null, status: 'vazio'),
            EnrichmentSource.comex: envelope('comex', null, status: 'vazio'),
          }));
      expect(find.textContaining('Economia'), findsNothing);
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
          diagnosisServiceProvider
              .overrideWithValue(FakeDiagnosisService(diagnosisJson)),
        ],
        child: CupertinoApp(
          home: CupertinoPageScaffold(
              child: CompanyDetailsModal(company: company)),
        ),
      ));
      await tester.pumpAndSettle();
    }

    Map<EnrichmentSource, Map<String, dynamic>> semGoogle() => {
          ...allSources(),
          EnrichmentSource.google: envelope('google', null, status: 'vazio'),
        };

    testWidgets(
        'abre já consultando o Google: capa, nota, site, telefone e endereço',
        (tester) async {
      final company = Company(
        id: 'c1',
        name: 'WEG',
        cnpj: '07175725000160',
        telefone: '4733334444',
        address: 'Endereço do cadastro',
        isClient: false,
        distance: 1.5,
        latitude: -26.4,
        longitude: -49.1,
      );
      final service = FakeEnrichmentService(allSources());
      await pumpModal(tester, company, service);

      expect(
          service.calls.where((c) => c == EnrichmentSource.google).length, 1);
      expect(find.byKey(const ValueKey('google-foto')), findsOneWidget);
      expect(find.text('Foto: Alexandre de Castro · Google'), findsOneWidget);
      final nota = tester
          .widget<Text>(find.byKey(const ValueKey('google-nota')))
          .textSpan!
          .toPlainText();
      expect(nota, contains('4,7'));
      expect(nota, contains('(405)'));
      expect(nota, contains('Aberto agora'));
      expect(find.text('weg.net'), findsOneWidget);
      // Google tem prioridade sobre o cadastro e a Receita
      expect(find.text('(47) 3276-4000'), findsOneWidget);
      expect(find.text('4733334444'), findsNothing);
      expect(find.text('Av. Pref. Waldemar Grubba, 3300 - Jaraguá do Sul - SC'),
          findsOneWidget);
      expect(find.text('Endereço do cadastro'), findsNothing);
      expect(find.text('1.50 km de você'), findsOneWidget);
      // nada de bloco "No Google" nem botão pra pedir
      expect(find.text('Ver no Google'), findsNothing);
      expect(find.text('No Google'), findsNothing);
    });

    testWidgets('ordem: ações, site, contato, CRM e só depois dados públicos',
        (tester) async {
      final company = Company(
        id: 'c1',
        name: 'WEG',
        cnpj: '07175725000160',
        isClient: false,
      );
      await pumpModal(tester, company, FakeEnrichmentService(allSources()));

      double y(Finder f) => tester.getTopLeft(f).dy;
      final acoes = y(find.text('Novo Contato'));
      final site = y(find.byKey(const ValueKey('site-empresa')));
      final telefone = y(find.text('Telefone'));
      final crm = y(find.text('Contatos CRM'));
      final receita = y(find.text('Receita Federal'));
      expect(acoes, lessThan(site));
      expect(site, lessThan(telefone));
      expect(telefone, lessThan(crm));
      expect(crm, lessThan(receita));
    });

    testWidgets('tocar na capa abre a foto em tela cheia e o X fecha',
        (tester) async {
      await pumpModal(
          tester,
          Company(id: 'c1', name: 'WEG', cnpj: '07175725000160'),
          FakeEnrichmentService(allSources()));
      expect(find.byKey(const ValueKey('google-foto-ampliada')), findsNothing);

      await tester.tap(find.byKey(const ValueKey('google-foto-abrir')));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('google-foto-ampliada')), findsOneWidget);
      expect(find.byType(InteractiveViewer), findsOneWidget);
      // o crédito do autor continua visível na foto ampliada
      expect(find.text('Foto: Alexandre de Castro · Google'), findsNWidgets(2));

      await tester.tap(find.byKey(const ValueKey('google-foto-fechar')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('google-foto-ampliada')), findsNothing);
    });

    testWidgets('na foto ampliada, arrastar pra baixo fecha', (tester) async {
      await pumpModal(
          tester,
          Company(id: 'c1', name: 'WEG', cnpj: '07175725000160'),
          FakeEnrichmentService(allSources()));
      await tester.tap(find.byKey(const ValueKey('google-foto-abrir')));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(InteractiveViewer), const Offset(0, 300));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('google-foto-ampliada')), findsNothing);
    });

    testWidgets('Google sem foto: capa neutra, o resto continua',
        (tester) async {
      final semFoto = Map<String, dynamic>.from(googleJson)..remove('foto');
      await pumpModal(
          tester,
          Company(id: 'c1', name: 'WEG', cnpj: '07175725000160'),
          FakeEnrichmentService({
            ...allSources(),
            EnrichmentSource.google: envelope('google', semFoto)
          }));
      expect(find.byKey(const ValueKey('google-foto')), findsNothing);
      expect(find.byKey(const ValueKey('google-nota')), findsOneWidget);
      expect(find.text('weg.net'), findsOneWidget);
    });

    testWidgets(
        'sem Google: contatos do cadastro e da Receita; campos sem dado somem',
        (tester) async {
      final company = Company(
        id: 'c1',
        name: 'WEG EQUIPAMENTOS ELETRICOS S/A',
        cnpj: '07175725000160',
        isClient: false,
        carteiraStatus: 'lead',
        distance: 3,
      );
      await pumpModal(tester, company, FakeEnrichmentService(semGoogle()));

      expect(find.byKey(const ValueKey('google-foto')), findsNothing);
      expect(find.byKey(const ValueKey('google-nota')), findsNothing);
      expect(find.byKey(const ValueKey('site-empresa')), findsNothing);
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

    testWidgets('o telefone do cadastro vence o da Receita', (tester) async {
      await pumpModal(
          tester,
          Company(
              id: 'c1',
              name: 'WEG',
              cnpj: '07175725000160',
              telefone: '4733334444'),
          FakeEnrichmentService(semGoogle()));
      expect(find.text('4733334444'), findsOneWidget);
      expect(find.text('(47) 3276-4775'), findsNothing);
    });

    testWidgets('horário: hoje visível, a semana ao tocar', (tester) async {
      final semana = [
        'segunda-feira: 07:30–17:00',
        'terça-feira: 07:30–17:00',
        'quarta-feira: 07:30–17:00',
        'quinta-feira: 07:30–17:00',
        'sexta-feira: 07:30–17:00',
        'sábado: Fechado',
        'domingo: Fechado',
      ];
      await pumpModal(
          tester,
          Company(id: 'c1', name: 'WEG', cnpj: '07175725000160'),
          FakeEnrichmentService({
            ...allSources(),
            EnrichmentSource.google:
                envelope('google', {...googleJson, 'horarios': semana}),
          }));
      expect(find.textContaining('Hoje: '), findsOneWidget);
      expect(find.text('Segunda-feira: 07:30–17:00'), findsNothing);
      await tester.tap(find.text('Horário'));
      await tester.pump();
      expect(find.text('Segunda-feira: 07:30–17:00'), findsOneWidget);
    });
  });
}
