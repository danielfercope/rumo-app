import 'package:flutter/cupertino.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/features/carteira/models/priority_models.dart';
import 'package:rumo_app/features/map/models/company_model.dart';
import 'package:rumo_app/features/map/models/lead_tier.dart';
import 'package:rumo_app/features/map/models/priority_insight.dart';
import 'package:rumo_app/features/map/presentation/priority_explanation_section.dart';

PriorityFactor factor(
        String chave, String campo, String valor, PriorityEffect ef,
        {double c = 0.5,
        double clientes = 0.5,
        double base = 0.1,
        double? vezes,
        int n = 25}) =>
    PriorityFactor(
        chave: chave,
        campo: campo,
        valor: valor,
        efeito: ef,
        contribuicao: c,
        pctClientes: clientes,
        pctBase: base,
        clientesComValor: n,
        vezes: vezes);

PriorityExplanation build({
  int? nota = 92,
  PriorityStrategy estrategia = PriorityStrategy.perfil,
  List<PriorityFactor>? fatores,
  bool confiavel = true,
  List<String> semDado = const ['Faturamento'],
}) =>
    PriorityExplanation(
      estrategia: estrategia,
      posicao: 5,
      nota: nota,
      totalLeads: 351,
      nClientes: 50,
      confiavel: confiavel,
      motivos: const ['Mais interações no CRM'],
      fatores: fatores ??
          [
            factor(
                'segmento', 'Segmento', 'Tecnologia', PriorityEffect.favorece,
                c: 0.9, clientes: 0.62, base: 0.18, vezes: 3.44, n: 31),
            factor('uf', 'Estado', 'PR', PriorityEffect.favorece,
                c: 0.4, vezes: 1.57),
            factor('porte', 'Porte', 'Demais', PriorityEffect.desfavorece,
                c: -0.5, clientes: 0.0, base: 0.2, vezes: 0.0, n: 0),
            factor(
                'idade', 'Tempo de abertura', '20+ anos', PriorityEffect.neutro,
                c: 0.02),
            factor(
                'municipio', 'Cidade', 'Curitiba (PR)', PriorityEffect.favorece,
                c: 0.3),
            factor('natureza_juridica', 'Natureza jurídica', 'Ltda',
                PriorityEffect.neutro,
                c: 0.0),
          ],
      semDado: semDado,
      numInteracoes: 7,
    );

Company lead(String id, String nome, double km) => Company(
    id: id, name: nome, distance: km, isClient: false, carteiraStatus: 'lead');

Future<void> pump(WidgetTester tester, Widget view) async {
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(CupertinoApp(
    home: CupertinoPageScaffold(child: SingleChildScrollView(child: view)),
  ));
}

void main() {
  const hot = LeadPriorityInfo(posicao: 5, nota: 92, tier: LeadTier.hot);

  testWidgets('mostra nota, faixa, posição e o resumo do porquê',
      (tester) async {
    await pump(
        tester,
        PriorityExplanationView(
            initiallyExpanded: true,
            company: lead('me', 'WEG', 12),
            explanation: build(),
            mine: hot));

    expect(find.text('Por que esta prioridade'), findsOneWidget);
    expect(find.text('92'), findsOneWidget);
    expect(find.text('Lead quente'), findsOneWidget);
    expect(find.text('Posição 5 de 351 leads'), findsOneWidget);
    expect(find.textContaining('Mais parecida com seus clientes que 92%'),
        findsOneWidget);
    expect(find.textContaining('Segmento (Tecnologia) e Estado (PR)'),
        findsOneWidget);
    expect(
        find.textContaining('probabilidade de fechar negócio'), findsOneWidget);
  });

  testWidgets('fatores: a favor, contra, números dos clientes e da base',
      (tester) async {
    await pump(
        tester,
        PriorityExplanationView(
            initiallyExpanded: true,
            company: lead('me', 'WEG', 12),
            explanation: build(),
            mine: hot));

    expect(find.text('O que pesa na nota'), findsOneWidget);
    expect(find.text('Tecnologia'), findsOneWidget);
    expect(find.text('a favor · 3,4× mais comum'), findsOneWidget);
    expect(find.text('contra · nenhum cliente assim'), findsOneWidget);
    expect(find.text('62% · 31 de 50'), findsOneWidget);
    expect(find.text('18%'), findsWidgets);
    // só os 4 mais fortes aparecem; o resto fica atrás do botão
    expect(find.text('Natureza jurídica'), findsNothing);
    await tester.tap(find.text('Ver os outros 2 fatores'));
    await tester.pump();
    expect(find.text('Natureza jurídica'), findsOneWidget);
    await tester.tap(find.text('Mostrar menos'));
    await tester.pump();
    expect(find.text('Natureza jurídica'), findsNothing);
  });

  testWidgets(
      'avisa o que não pesa por falta de dado e quando há poucos clientes',
      (tester) async {
    await pump(
        tester,
        PriorityExplanationView(
            initiallyExpanded: true,
            company: lead('me', 'WEG', 12),
            explanation: build(
                confiavel: false, semDado: const ['Faturamento', 'Segmento']),
            mine: hot));

    expect(find.textContaining('Sem dados de Faturamento, Segmento'),
        findsOneWidget);
    expect(find.textContaining('poucos clientes (50)'), findsOneWidget);
  });

  testWidgets('vale a viagem: veredito, lista dos mais perto e o que muda',
      (tester) async {
    final other = build(nota: 18, fatores: [
      factor('segmento', 'Segmento', 'Varejo', PriorityEffect.desfavorece,
          c: -0.4, clientes: 0.04, base: 0.3, vezes: 0.13, n: 2),
      factor('uf', 'Estado', 'PR', PriorityEffect.favorece, c: 0.4),
    ]);
    await pump(
        tester,
        PriorityExplanationView(
          initiallyExpanded: true,
          company: lead('me', 'WEG', 12),
          explanation: build(),
          mine: hot,
          nearer: [
            NearbyLead(
                lead('a', 'Padaria Sol', 1.4),
                const LeadPriorityInfo(
                    posicao: 300, nota: 18, tier: LeadTier.cold)),
            NearbyLead(lead('b', 'Loja Sem Nota', 5), null),
          ],
          closestExplanation: other,
        ));

    expect(find.text('Vale a viagem?'), findsOneWidget);
    expect(find.byKey(const ValueKey('trip-verdict')), findsOneWidget);
    expect(find.textContaining('Vale ir mais longe'), findsOneWidget);
    expect(find.text('Padaria Sol'), findsOneWidget);
    expect(find.text('nota 18'), findsOneWidget);
    expect(find.text('sem nota'), findsOneWidget);
    expect(find.text('O que muda em relação a Padaria Sol'), findsOneWidget);
    expect(
        find.textContaining('Tecnologia (62% dos clientes)'), findsOneWidget);
  });

  testWidgets('sem leads mais perto não mostra a comparação', (tester) async {
    await pump(
        tester,
        PriorityExplanationView(
            initiallyExpanded: true,
            company: lead('me', 'WEG', 0.2),
            explanation: build(),
            mine: hot));
    expect(find.text('Vale a viagem?'), findsNothing);
  });

  testWidgets('por interação: mostra os sinais do CRM e não os fatores',
      (tester) async {
    await pump(
        tester,
        PriorityExplanationView(
          initiallyExpanded: true,
          company: lead('me', 'WEG', 3),
          explanation: build(
              nota: null,
              estrategia: PriorityStrategy.interacao,
              fatores: const []),
          mine: const LeadPriorityInfo(posicao: 5, tier: LeadTier.hot),
        ));

    expect(find.text('Como a ordem foi definida'), findsOneWidget);
    expect(find.text('Interações no CRM'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
    expect(find.text('O que pesa na nota'), findsNothing);
    expect(find.text('Posição 5 de 351 leads'), findsOneWidget);
  });

  testWidgets('recolhida por padrão: uma linha, abre em "Por quê?" e recolhe',
      (tester) async {
    await pump(
        tester,
        PriorityExplanationView(
          company: lead('me', 'WEG', 12),
          explanation: build(),
          mine: hot,
          nearer: [
            NearbyLead(
                lead('a', 'Padaria Sol', 1.4),
                const LeadPriorityInfo(
                    posicao: 300, nota: 18, tier: LeadTier.cold)),
          ],
        ));

    expect(find.byKey(const ValueKey('priority-compact')), findsOneWidget);
    expect(find.text('Nota 92 · 5º de 351 leads'), findsOneWidget);
    expect(find.text('Vale ir mais longe por ela'), findsOneWidget);
    expect(find.text('O que pesa na nota'), findsNothing);

    await tester.tap(find.text('Por quê?'));
    await tester.pump();
    expect(find.text('O que pesa na nota'), findsOneWidget);
    expect(find.text('Vale a viagem?'), findsOneWidget);

    await tester.tap(find.text('Recolher'));
    await tester.pump();
    expect(find.text('O que pesa na nota'), findsNothing);
    expect(find.byKey(const ValueKey('priority-compact')), findsOneWidget);
  });
}
