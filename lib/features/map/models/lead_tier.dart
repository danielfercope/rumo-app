import '../../carteira/models/priority_models.dart';

/// Faixa de prioridade de um lead, usada pra dar cor e tamanho ao pino no mapa.
enum LeadTier { cold, warm, hot }

/// Nota (0–100, percentil dentro da carteira) a partir da qual o lead é
/// "quente" / "morno". Abaixo disso, "frio".
const int hotMinNota = 67;
const int warmMinNota = 34;

LeadTier tierForNota(int nota) => nota >= hotMinNota
    ? LeadTier.hot
    : nota >= warmMinNota
        ? LeadTier.warm
        : LeadTier.cold;

/// Posição, nota e faixa de um lead na lista de prioridades.
class LeadPriorityInfo {
  const LeadPriorityInfo({
    required this.posicao,
    required this.tier,
    this.nota,
  });

  final int posicao;

  /// Nulo na estratégia "interação" (só existe a ordem).
  final int? nota;
  final LeadTier tier;
}

/// Prioridade de cada lead do resultado do cálculo (company_id → info).
///
/// Com nota (estratégia "perfil") a faixa vem do limiar da nota. Sem nota
/// (estratégia "interação", só existe a ordem) a lista é dividida em terços
/// pela posição. Lead fora do resultado (ex.: além do limite pedido) não entra.
Map<String, LeadPriorityInfo> leadPriorities(PriorityResult result) {
  final itens = result.itens;
  final infos = <String, LeadPriorityInfo>{};
  for (var i = 0; i < itens.length; i++) {
    final item = itens[i];
    final nota = item.nota;
    final tier = nota != null
        ? tierForNota(nota)
        : const [
            LeadTier.hot,
            LeadTier.warm,
            LeadTier.cold
          ][(i * 3) ~/ itens.length];
    infos[item.companyId] =
        LeadPriorityInfo(posicao: item.posicao, nota: nota, tier: tier);
  }
  return infos;
}

/// Só a faixa de cada lead (o que o mapa usa pra colorir os pinos).
Map<String, LeadTier> leadTiers(PriorityResult result) => {
      for (final e in leadPriorities(result).entries) e.key: e.value.tier,
    };
