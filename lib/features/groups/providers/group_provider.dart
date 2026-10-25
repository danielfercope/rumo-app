import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Busca lazy do hash de convite — só é lida quando o admin abre a seção de
/// convite na UI (nunca pré-carregada em myGroupsProvider).
final groupInviteProvider =
    FutureProvider.family<String, String>((ref, groupId) {
  return ref.watch(groupServiceProvider).getInvite(groupId);
});
