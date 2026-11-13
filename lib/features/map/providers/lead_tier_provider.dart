import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../carteira/providers/carteira_provider.dart';
import '../../groups/providers/group_provider.dart';
import '../models/lead_tier.dart';

/// Quantos leads priorizados o mapa pede (máximo do modo compacto do Backend). Lead que ficar
/// de fora desse corte é, por definição, dos menos prioritários: pino frio.
const int mapPriorityLimit = 5000;

/// Posição, nota e faixa dos leads da organização ativa (company_id → info).
///
/// Só LÊ o resultado já calculado pelo Backend. Qualquer falha (sem CRM, sem
/// cálculo ainda, rede) devolve vazio: o mapa continua funcionando, com todos
/// os leads em pino frio.
final leadPriorityProvider =
    FutureProvider.autoDispose<Map<String, LeadPriorityInfo>>((ref) async {
  final groupId = ref.watch(activeGroupProvider)?.group.id;
  if (groupId == null) return const {};
  try {
    final result = await ref
        .watch(carteiraServiceProvider)
        .prioridade(groupId, limit: mapPriorityLimit, compacto: true);
    return leadPriorities(result);
  } catch (_) {
    return const {};
  }
});

/// Faixa de prioridade (company_id → faixa) dos leads: o que colore os pinos.
final leadTiersProvider =
    FutureProvider.autoDispose<Map<String, LeadTier>>((ref) async {
  final infos = await ref.watch(leadPriorityProvider.future);
  return {for (final e in infos.entries) e.key: e.value.tier};
});
