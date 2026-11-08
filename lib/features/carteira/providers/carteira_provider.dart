import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api_client.dart';
import '../models/crm_models.dart';
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
  final connection =
      await ref.watch(carteiraServiceProvider).buscarConexao(groupId);
  if (connection?.status == CrmConnectionStatus.importando) {
    final timer = Timer(crmPollInterval, ref.invalidateSelf);
    ref.onDispose(timer.cancel);
  }
  return connection;
});

final lastSyncProvider =
    FutureProvider.autoDispose.family<SyncLog?, String>((ref, groupId) async {
  ref.watch(crmConnectionProvider(groupId)); // atualiza junto com a conexão
  return ref.watch(carteiraServiceProvider).ultimaSincronizacao(groupId);
});
