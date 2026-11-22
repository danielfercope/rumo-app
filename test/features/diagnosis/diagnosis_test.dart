import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:rumo_app/core/services/api_client.dart';
import 'package:rumo_app/features/diagnosis/models/tax_diagnosis.dart';
import 'package:rumo_app/features/diagnosis/presentation/tax_opportunity_card.dart';
import 'package:rumo_app/features/diagnosis/services/diagnosis_service.dart';

import 'diagnosis_fixtures.dart';

class MockApiClient extends Mock implements ApiClient {}

Future<void> pumpCard(WidgetTester tester, FakeDiagnosisService service) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [diagnosisServiceProvider.overrideWithValue(service)],
    child: const CupertinoApp(
      home: CupertinoPageScaffold(
        child: SingleChildScrollView(
          child: TaxOpportunityCard(groupId: 'g1', cnpj: '07175725000160'),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  group('modelo', () {
    test('lê a tese principal, as outras e as evidências', () {
      final d = TaxDiagnosis.fromJson(diagnosisJson);
      expect(d.status, DiagnosisStatus.ok);
      expect(
          d.principal!.titulo, 'PIS/COFINS monofásico pago de novo no Simples');
      expect(d.principal!.confianca, Confidence.alta);
      expect(d.principal!.periodo, '2022–2026');
      expect(d.principal!.evidencias.map((e) => e.texto),
          contains('CNAE principal 47.71-7/01: revenda de medicamentos'));
      expect(d.principal!.perguntas, hasLength(2));
      expect(d.outras.single.confianca, Confidence.media);
      expect(d.bloqueio, isNull);
    });

    test('bloqueio, status e campos ausentes', () {
      final d = TaxDiagnosis.fromJson({
        'status': 'ok',
        'principal': null,
        'bloqueio': {'motivo': 'MEI recolhe valor fixo'},
      });
      expect(d.principal, isNull);
      expect(d.outras, isEmpty);
      expect(d.bloqueio, 'MEI recolhe valor fixo');
      expect(TaxDiagnosis.fromJson({'status': 'indisponivel'}).status,
          DiagnosisStatus.indisponivel);
      expect(TaxDiagnosis.fromJson({}).status, DiagnosisStatus.vazio);
    });
  });

  test('serviço chama a rota com organização e CNPJ', () async {
    final api = MockApiClient();
    when(() => api.backendRequest('GET', 'diagnostico/tributario',
        body: any(named: 'body'),
        query: any(named: 'query'))).thenAnswer((_) async => diagnosisJson);

    final d = await DiagnosisService(api).fetch('g1', '07175725000160');

    final query = verify(() => api.backendRequest(
        'GET', 'diagnostico/tributario',
        body: any(named: 'body'),
        query: captureAny(named: 'query'))).captured.single;
    expect(query, {'group_id': 'g1', 'cnpj': '07175725000160'});
    expect(d.principal, isNotNull);
  });

  group('card', () {
    testWidgets('mostra a tese, a confiança e as evidências; abre ao tocar',
        (tester) async {
      await pumpCard(tester, FakeDiagnosisService(diagnosisJson));

      expect(find.text('Oportunidade tributária'), findsOneWidget);
      expect(find.text('PIS/COFINS monofásico pago de novo no Simples'),
          findsOneWidget);
      expect(find.text('Confiança alta'), findsOneWidget);
      expect(find.text('Período 2022–2026'), findsOneWidget);
      expect(find.text('CNAE principal 47.71-7/01: revenda de medicamentos'),
          findsOneWidget);
      expect(find.text('COMO ABORDAR'), findsNothing);

      await tester.tap(find.text('Oportunidade tributária'));
      await tester.pumpAndSettle();
      expect(find.text('COMO ABORDAR'), findsOneWidget);
      expect(find.text('PERGUNTAS PARA VALIDAR NA VISITA'), findsOneWidget);
      expect(find.text('OUTRAS POSSIBILIDADES'), findsOneWidget);
      expect(find.text('ICMS-ST pago de novo no DAS'), findsOneWidget);
      expect(find.textContaining('Hipótese a partir de dados públicos'),
          findsOneWidget);
    });

    testWidgets('empresa bloqueada mostra o motivo', (tester) async {
      await pumpCard(
          tester,
          FakeDiagnosisService({
            'status': 'ok',
            'principal': null,
            'outras': [],
            'bloqueio': {'motivo': 'Situação cadastral inapta.'},
          }));
      expect(find.text('Situação cadastral inapta.'), findsOneWidget);
    });

    testWidgets('sem tese e sem dado', (tester) async {
      await pumpCard(
          tester, FakeDiagnosisService({'status': 'ok', 'principal': null}));
      expect(find.textContaining('Nenhum sinal de imposto pago a mais'),
          findsOneWidget);

      await pumpCard(tester, FakeDiagnosisService({'status': 'vazio'}));
      expect(find.text('Oportunidade tributária'), findsNothing);
    });

    testWidgets('falha mostra "Tentar de novo" e reconsulta', (tester) async {
      final service = FakeDiagnosisService(diagnosisJson, fail: true);
      await pumpCard(tester, service);
      expect(find.text('Não foi possível analisar agora.'), findsOneWidget);

      service.fail = false;
      await tester.tap(find.text('Tentar de novo'));
      await tester.pumpAndSettle();
      expect(find.text('Confiança alta'), findsOneWidget);
      expect(service.calls, 2);
    });
  });
}
