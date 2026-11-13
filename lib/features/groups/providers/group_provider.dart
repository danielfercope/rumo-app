import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../../core/services/api_client.dart';
import '../../auth/providers/profile_provider.dart';
import '../models/group_member_model.dart';
import '../services/group_service.dart';

final groupServiceProvider = Provider<GroupService>((ref) {
  return GroupService(ref.watch(apiClientProvider));
});

/// Única chamada de rede que resolve: onboarding (lista vazia?), papel do
/// usuário em cada grupo, e o gate de rastreamento (shouldTrackProvider).
final myGroupsProvider = FutureProvider<List<MyGroup>>((ref) async {
  final profile = await ref.watch(profileProvider.future);
  if (profile == null) return [];
  return ref.watch(groupServiceProvider).listMyGroups(profile.id);
});

final activeGroupIdProvider = StateProvider<String?>((ref) => null);

/// Organização recém-criada cujo CRM ainda deve ser conectado: o gate abre o
/// assistente de conexão uma vez e limpa isto.
final pendingCrmSetupGroupIdProvider = StateProvider<String?>((ref) => null);

/// Grupo ativo, com fallback pro primeiro grupo da lista quando nenhum foi
/// escolhido explicitamente (ou o escolhido não existe mais na lista).
final activeGroupProvider = Provider<MyGroup?>((ref) {
  final groups = ref.watch(myGroupsProvider).value ?? [];
  if (groups.isEmpty) return null;
  final activeId = ref.watch(activeGroupIdProvider);
  return groups.firstWhere(
    (g) => g.group.id == activeId,
    orElse: () => groups.first,
  );
});

final isActiveGroupAdminProvider = Provider<bool>((ref) {
  return ref.watch(activeGroupProvider)?.isAdmin ?? false;
});

/// Gate de rastreamento consumido por radar_page.dart — substitui o antigo
/// gate por `departamento == 'Executivo'`.
final shouldTrackProvider = Provider<bool>((ref) {
  final groups = ref.watch(myGroupsProvider).value ?? [];
  return groups.any((g) => g.group.trackingEnabled);
});

final groupMembersProvider =
    FutureProvider.family<List<GroupMember>, String>((ref, groupId) {
  return ref.watch(groupServiceProvider).listMembers(groupId);
});

final groupTrackingProvider =
    FutureProvider.family<List<TrackingPoint>, String>((ref, groupId) {
  return ref.watch(groupServiceProvider).listTracking(groupId);
});

/// Cliente HTTP das fotos dos membros (sobrescrevível nos testes).
final memberPhotoClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

/// Bytes da foto de um membro (URL da conta Google), ou `null` se não baixar
/// — quem usa cai nas iniciais. Fica em memória pela sessão: o Google limita
/// (429) pedidos repetidos, então não se tenta de novo a cada rebuild.
final memberPhotoProvider =
    FutureProvider.family<Uint8List?, String>((ref, url) async {
  if (url.isEmpty) return null;
  try {
    final res = await ref
        .watch(memberPhotoClientProvider)
        .get(Uri.parse(url))
        .timeout(const Duration(seconds: 6));
    return res.statusCode == 200 && res.bodyBytes.isNotEmpty
        ? res.bodyBytes
        : null;
  } catch (_) {
    return null;
  }
});

/// Trajeto de um membro num dia (`day` = qualquer instante do dia local).
final trackingHistoryProvider = FutureProvider.family<
    List<TrackingHistoryPoint>,
    ({String groupId, String userId, DateTime day})>((ref, key) {
  final start = DateTime(key.day.year, key.day.month, key.day.day);
  final end = DateTime(start.year, start.month, start.day + 1);
  return ref
      .watch(groupServiceProvider)
      .listTrackingHistory(key.groupId, key.userId, start, end);
});

/// Busca lazy do hash de convite — só é lida quando o admin abre a seção de
/// convite na UI (nunca pré-carregada em myGroupsProvider).
final groupInviteProvider =
    FutureProvider.family<String, String>((ref, groupId) {
  return ref.watch(groupServiceProvider).getInvite(groupId);
});
