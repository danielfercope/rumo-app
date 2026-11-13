import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api_client.dart';
import '../models/crm_models.dart';
import '../models/priority_models.dart';
import '../services/carteira_service.dart';

final carteiraServiceProvider = Provider<CarteiraService>((ref) {
  return CarteiraService(ref.watch(apiClientProvider));
});

/// Intervalo de atualização enquanto a carga inicial roda no servidor.
const crmPollInterval = Duration(seconds: 5);

/// Conexão da organização com o CRM (null = nunca conectou). Enquanto a carga
/// inicial está em andamento, se reconsulta sozinho até terminar — o timer morre
/// com o provider (autoDispose), então nada fica rodando com a tela fechada.
final crmConnectionProvider = FutureProvider.autoDispose
    .family<CrmConnection?, String>((ref, groupId) async {
  final disposed = _trackDisposal(ref);
  final connection =
      await ref.watch(carteiraServiceProvider).buscarConexao(groupId);
  if (connection?.status == CrmConnectionStatus.importando) {
    _pollAgain(ref, disposed);
  }
  return connection;
});

/// Marca quando o provider foi descartado. Depois de um `await`, a tela pode
/// já ter fechado: criar o Timer nesse ponto o deixaria rodando sem dono.
bool Function() _trackDisposal(Ref ref) {
  var disposed = false;
  ref.onDispose(() => disposed = true);
  return () => disposed;
}

void _pollAgain(Ref ref, bool Function() disposed) {
  if (disposed()) return;
  final timer = Timer(crmPollInterval, ref.invalidateSelf);
  ref.onDispose(timer.cancel);
}

final lastSyncProvider =
    FutureProvider.autoDispose.family<SyncLog?, String>((ref, groupId) async {
  ref.watch(crmConnectionProvider(groupId)); // atualiza junto com a conexão
  return ref.watch(carteiraServiceProvider).ultimaSincronizacao(groupId);
});

/// O que a aba de prioridades precisa saber: se há CRM conectado e o que o
/// Backend já calculou.
class PriorityScreenData {
  /// Nulo = a organização não conectou um CRM.
  final CrmConnectionStatus? conexao;
  final PriorityResult? resultado;

  const PriorityScreenData({this.conexao, this.resultado});

  bool get semCrm => conexao == null;

  /// Há CRM, mas o Backend ainda não calculou (carga inicial rodando ou
  /// primeira sincronização por vir).
  bool get calculando =>
      !semCrm &&
      conexao != CrmConnectionStatus.erro &&
      resultado?.estrategia == null;
}

/// Lista de prioridades. Enquanto o cálculo não existe, se reconsulta sozinha
/// (como `crmConnectionProvider`); sem CRM ou com a conexão em erro não fica
/// consultando à toa.
final priorityProvider = FutureProvider.autoDispose
    .family<PriorityScreenData, String>((ref, groupId) async {
  final disposed = _trackDisposal(ref);
  final connection = await ref.watch(crmConnectionProvider(groupId).future);
  if (connection == null) return const PriorityScreenData();

  final result = await ref.watch(carteiraServiceProvider).prioridade(groupId);
  final data =
      PriorityScreenData(conexao: connection.status, resultado: result);
  if (data.calculando) _pollAgain(ref, disposed);
  return data;
});

/// Explicação da nota de um lead (um por empresa aberta nos detalhes).
final priorityExplanationProvider = FutureProvider.autoDispose
    .family<PriorityExplanation?, ({String groupId, String companyId})>(
        (ref, key) {
  return ref
      .watch(carteiraServiceProvider)
      .explicarEmpresa(key.groupId, key.companyId);
});
