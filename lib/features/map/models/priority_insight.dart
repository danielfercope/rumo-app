import '../../../core/format/br_format.dart';
import '../../carteira/models/priority_models.dart';
import 'company_model.dart';
import 'lead_tier.dart';

/// Diferença de nota (0–100) a partir da qual uma empresa é "bem" melhor ou pior
/// que outra. Abaixo disso, as duas são tratadas como equivalentes.
const int significantNotaGap = 15;

/// Diferença de posição (estratégia por interação, sem nota) com o mesmo papel.
const int significantPositionGap = 5;

/// Um lead mais perto do usuário que o aberto nos detalhes.
class NearbyLead {
  const NearbyLead(this.company, this.info);

  final Company company;

  /// Nulo = o lead não está na lista priorizada (sem nota).
  final LeadPriorityInfo? info;

  double get distanceKm => company.distance ?? double.infinity;
}

/// Os leads mais perto que [company], do mais perto pro mais longe.
List<NearbyLead> nearerLeads(
  Company company,
  Iterable<Company> all,
  Map<String, LeadPriorityInfo> priorities, {
  int limit = 3,
  double minGapKm = 0.05,
}) {
  final mine = company.distance;
  if (mine == null) return const [];
  final nearer = all
      .where((c) =>
          c.id != company.id &&
          c.isClient != true &&
          c.carteiraStatus != 'perdido' &&
          c.distance != null &&
          c.distance! < mine - minGapKm)
      .toList()
    ..sort((a, b) => a.distance!.compareTo(b.distance!));
  return [
    for (final c in nearer.take(limit)) NearbyLead(c, priorities[c.id]),
  ];
}

/// Frase que resume por que o lead tem esta nota.
String explanationSummary(PriorityExplanation e) {
  if (e.estrategia == PriorityStrategy.interacao) {
    return e.motivos.isNotEmpty
        ? e.motivos.first
        : 'Ordenada pelo histórico de interação no CRM.';
  }
  final favor = [...e.aFavor]
    ..sort((a, b) => b.contribuicao.compareTo(a.contribuicao));
  final contra = [...e.contra]
    ..sort((a, b) => a.contribuicao.compareTo(b.contribuicao));
  final parts = <String>[];
  if (favor.isEmpty) {
    parts.add('Nenhuma característica dela se destaca entre os seus clientes, '
        'por isso a nota fica perto ou abaixo da média.');
  } else {
    final top = favor.take(2).toList();
    final names = top.map((f) => '${f.campo} (${f.valor})').join(' e ');
    final vezes = top.first.vezes;
    parts.add('Parece com os seus clientes principalmente em $names'
        '${vezes != null ? ': esse valor é ${_x(vezes)} mais comum entre eles do que na base' : ''}.');
  }
  if (contra.isNotEmpty) {
    parts.add('Pesa contra: ${contra.first.campo} (${contra.first.valor}).');
  }
  return parts.join(' ');
}

/// "3,4×", sem casa decimal quando for redondo.
String _x(double v) => '${formatMultiplier(v)}×';

/// 3.4 → "3,4"; 12.0 → "12"; vírgula decimal.
String formatMultiplier(double v) {
  final text = v >= 10 ? v.round().toString() : v.toStringAsFixed(1);
  return text.replaceAll('.', ',').replaceFirst(RegExp(r',0$'), '');
}

enum TripVerdictKind { vale, melhorPerto, equivalente }

class TripVerdict {
  const TripVerdict(this.kind, this.text);

  final TripVerdictKind kind;
  final String text;
}

/// "Vale a viagem?": compara este lead com os mais perto. Nulo se não há com
/// quem comparar (nenhum lead mais perto, ou sem distância/nota).
TripVerdict? tripVerdict({
  required Company company,
  required LeadPriorityInfo? mine,
  required List<NearbyLead> nearer,
}) {
  final myDistance = company.distance;
  final ranked = nearer.where((n) => n.info != null).toList();
  if (mine == null || myDistance == null || ranked.isEmpty) return null;

  final closest = nearer.first;
  final extraKm = myDistance - closest.distanceKm;
  final extra = formatDistanceBr(extraKm * 1000);

  // "melhor" = mais parecido com os clientes. Com nota, maior; sem nota
  // (interação), posição menor.
  int gapOf(NearbyLead n) {
    final a = mine.nota, b = n.info!.nota;
    if (a != null && b != null) return a - b; // > 0: este é melhor
    return n.info!.posicao - mine.posicao; // > 0: este é melhor
  }

  final significant =
      mine.nota != null ? significantNotaGap : significantPositionGap;
  final gaps = [for (final n in ranked) (n, gapOf(n))];

  String score(LeadPriorityInfo i) =>
      i.nota != null ? 'nota ${i.nota}' : 'posição ${i.posicao}';
  // só o número, pra "nota 92, contra 18 de …"
  String bare(LeadPriorityInfo i) =>
      i.nota != null ? '${i.nota}' : '${i.posicao}';
  String name(NearbyLead n) => n.company.displayName;

  if (gaps.every((g) => g.$2 >= significant)) {
    final c = ranked.first;
    return TripVerdict(
      TripVerdictKind.vale,
      'Vale ir mais longe. Está a ${formatDistanceBr(myDistance * 1000)} de '
      'você, $extra além do lead mais próximo, mas é bem mais parecida com os '
      'seus clientes (${score(mine)}, contra ${bare(c.info!)} de ${name(c)}).',
    );
  }
  final better = gaps.where((g) => g.$2 <= -significant).toList()
    ..sort((a, b) => a.$2.compareTo(b.$2));
  if (better.isNotEmpty) {
    final n = better.first.$1;
    return TripVerdict(
      TripVerdictKind.melhorPerto,
      'Há opção melhor mais perto: ${name(n)} está a '
      '${formatDistanceBr(n.distanceKm * 1000)} e tem ${score(n.info!)} '
      '(esta tem ${score(mine)}). Priorize ela e deixe esta para depois.',
    );
  }
  final c = ranked.first;
  return TripVerdict(
    TripVerdictKind.equivalente,
    'As notas são parecidas (${score(mine)} aqui; ${score(c.info!)} em '
    '${name(c)}, a ${formatDistanceBr(c.distanceKm * 1000)}). Nesse caso '
    'compensa visitar primeiro a mais perto.',
  );
}

/// Onde este lead e outro diferem no perfil dos clientes.
class FactorDiff {
  const FactorDiff({
    required this.campo,
    required this.mine,
    required this.other,
    required this.mineIsBetter,
  });

  final String campo;
  final PriorityFactor mine;
  final PriorityFactor other;
  final bool mineIsBetter;
}

/// Os fatores em que dois leads mais se distanciam (até [limit]), do que mais
/// favorece o primeiro ao que mais favorece o segundo.
List<FactorDiff> compareFactors(
  PriorityExplanation mine,
  PriorityExplanation other, {
  int limit = 3,
  double minDiff = 0.15,
}) {
  final otherByKey = {for (final f in other.fatores) f.chave: f};
  final diffs = <(PriorityFactor, PriorityFactor, double)>[];
  for (final f in mine.fatores) {
    final o = otherByKey[f.chave];
    if (o == null) continue;
    final d = f.contribuicao - o.contribuicao;
    if (d.abs() >= minDiff && f.valor != o.valor) diffs.add((f, o, d));
  }
  diffs.sort((a, b) => b.$3.abs().compareTo(a.$3.abs()));
  return [
    for (final d in diffs.take(limit))
      FactorDiff(
        campo: d.$1.campo,
        mine: d.$1,
        other: d.$2,
        mineIsBetter: d.$3 > 0,
      ),
  ];
}
