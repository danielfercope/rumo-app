import 'package:flutter_test/flutter_test.dart';
import 'package:rumo_app/features/carteira/models/priority_models.dart';
import 'package:rumo_app/features/map/models/company_model.dart';
import 'package:rumo_app/features/map/models/lead_tier.dart';
import 'package:rumo_app/features/map/models/priority_insight.dart';

PriorityFactor factor(String chave, String valor, double contribuicao,
        {double clientes = 0.4, double base = 0.1, double? vezes}) =>
    PriorityFactor(
      chave: chave,
      campo: chave == 'uf'
          ? 'Estado'
          : chave == 'porte'
              ? 'Porte'
              : 'Segmento',
      valor: valor,
      efeito: contribuicao > 0.1
          ? PriorityEffect.favorece
          : contribuicao < -0.1
              ? PriorityEffect.desfavorece
              : PriorityEffect.neutro,
      contribuicao: contribuicao,
      pctClientes: clientes,
      pctBase: base,
      clientesComValor: (clientes * 50).round(),
      vezes: vezes ?? (base == 0 ? null : clientes / base),
    );

PriorityExplanation explanation(List<PriorityFactor> fatores,
        {int nota = 92, PriorityStrategy e = PriorityStrategy.perfil}) =>
    PriorityExplanation(
      estrategia: e,
      posicao: 5,
      nota: nota,
      totalLeads: 351,
      nClientes: 50,
      confiavel: true,
      motivos: const ['Ordenada por interações'],
      fatores: fatores,
      semDado: const [],
    );

Company lead(String id, String nome, double km) => Company(
    id: id, name: nome, distance: km, isClient: false, carteiraStatus: 'lead');

LeadPriorityInfo info(int nota, {int posicao = 1}) =>
    LeadPriorityInfo(posicao: posicao, nota: nota, tier: tierForNota(nota));

void main() {
  group('explanationSummary', () {
    test('cita os 2 fatores que mais ajudam e o que pesa contra', () {
      final e = explanation([
        factor('segmento', 'Tecnologia', 0.9, clientes: 0.62, base: 0.18),
        factor('uf', 'PR', 0.4),
        factor('porte', 'Demais', -0.5, clientes: 0.02, base: 0.3),
      ]);
      final text = explanationSummary(e);
      expect(text, contains('Segmento (Tecnologia) e Estado (PR)'));
      expect(text, contains('3,4× mais comum'));
      expect(text, contains('Pesa contra: Porte (Demais).'));
    });

    test('sem nenhum fator a favor, diz isso claramente', () {
      final e = explanation([factor('porte', 'Demais', -0.5)], nota: 4);
      expect(explanationSummary(e),
          contains('Nenhuma característica dela se destaca'));
    });

    test('por interação usa o motivo do CRM', () {
      final e = explanation(const [], e: PriorityStrategy.interacao);
      expect(explanationSummary(e), 'Ordenada por interações');
    });
  });

  test('formatMultiplier usa vírgula e some com ",0"', () {
    expect(formatMultiplier(3.4), '3,4');
    expect(formatMultiplier(2.0), '2');
    expect(formatMultiplier(12.7), '13');
  });

  group('nearerLeads', () {
    final me = lead('me', 'Longe', 12);
    final all = [
      lead('a', 'Perto', 1.2),
      lead('b', 'Médio', 5),
      lead('c', 'Mais longe', 20),
      Company(id: 'd', name: 'Cliente', distance: 0.5, isClient: true),
      Company(
          id: 'e', name: 'Perdida', distance: 0.8, carteiraStatus: 'perdido'),
      me,
    ];

    test('só leads mais perto, do mais perto ao mais longe, sem clientes', () {
      final r = nearerLeads(me, all, {'a': info(10)});
      expect(r.map((n) => n.company.id), ['a', 'b']);
      expect(r.first.info!.nota, 10);
      expect(r.last.info, isNull);
    });

    test('sem distância não há com o que comparar', () {
      expect(nearerLeads(Company(id: 'x', name: 'x'), all, {}), isEmpty);
    });

    test('respeita o limite', () {
      expect(nearerLeads(me, all, {}, limit: 1).length, 1);
    });
  });

  group('tripVerdict', () {
    final me = lead('me', 'Longe', 12);
    NearbyLead n(String id, String nome, double km, int? nota) =>
        NearbyLead(lead(id, nome, km), nota == null ? null : info(nota));

    test('vale a viagem quando é bem melhor que todos os mais perto', () {
      final v = tripVerdict(
          company: me,
          mine: info(92),
          nearer: [n('a', 'Padaria Sol', 1.4, 18), n('b', 'Loja', 5, 40)])!;
      expect(v.kind, TripVerdictKind.vale);
      expect(v.text, contains('Vale ir mais longe'));
      expect(v.text, contains('nota 92, contra 18 de Padaria Sol'));
      expect(v.text, contains('12 km'));
    });

    test('há opção melhor mais perto: manda priorizar ela', () {
      final v = tripVerdict(
          company: me, mine: info(30), nearer: [n('a', 'Mercado Bom', 2, 85)])!;
      expect(v.kind, TripVerdictKind.melhorPerto);
      expect(v.text, contains('Mercado Bom'));
      expect(v.text, contains('nota 85'));
    });

    test('notas parecidas: compensa a mais perto', () {
      final v = tripVerdict(
          company: me, mine: info(60), nearer: [n('a', 'Perto', 2, 55)])!;
      expect(v.kind, TripVerdictKind.equivalente);
    });

    test('sem nota (interação) compara pela posição', () {
      const noNota = LeadPriorityInfo(posicao: 2, tier: LeadTier.hot);
      final v = tripVerdict(company: me, mine: noNota, nearer: [
        NearbyLead(lead('a', 'Perto', 1),
            const LeadPriorityInfo(posicao: 40, tier: LeadTier.cold))
      ])!;
      expect(v.kind, TripVerdictKind.vale);
      expect(v.text, contains('posição 2'));
    });

    test('sem ninguém mais perto com nota, não há veredito', () {
      expect(
          tripVerdict(
              company: me, mine: info(90), nearer: [n('a', 'x', 1, null)]),
          isNull);
      expect(
          tripVerdict(company: me, mine: info(90), nearer: const []), isNull);
      expect(tripVerdict(company: me, mine: null, nearer: [n('a', 'x', 1, 5)]),
          isNull);
    });
  });

  group('compareFactors', () {
    test(
        'lista onde os dois leads mais se distanciam, maior diferença primeiro',
        () {
      final mine = explanation([
        factor('segmento', 'Tecnologia', 0.9, clientes: 0.62, base: 0.18),
        factor('uf', 'PR', 0.4),
        factor('porte', 'Micro', 0.0),
      ]);
      final other = explanation([
        factor('segmento', 'Varejo', -0.4, clientes: 0.04, base: 0.3),
        factor('uf', 'PR', 0.4),
        factor('porte', 'Micro', 0.0),
      ]);

      final diffs = compareFactors(mine, other);

      expect(diffs.length, 1); // só o segmento muda de valor e de peso
      expect(diffs.single.campo, 'Segmento');
      expect(diffs.single.mineIsBetter, isTrue);
      expect(diffs.single.other.valor, 'Varejo');
    });

    test('mesmo valor ou diferença pequena não entra', () {
      final a = explanation([factor('uf', 'PR', 0.4)]);
      final b = explanation([factor('uf', 'PR', 0.1)]);
      expect(compareFactors(a, b), isEmpty);
    });
  });
}
