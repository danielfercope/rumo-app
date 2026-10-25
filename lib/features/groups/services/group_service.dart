import '../../../core/services/api_client.dart';
import '../models/group_member_model.dart';
import '../models/group_model.dart';

/// Lançado quando uma RPC admin-only devolve "sem permissão" em vez de um
/// erro HTTP (ex. get_group_invite para quem não é admin).
class GroupPermissionError implements Exception {
  GroupPermissionError(this.message);
  final String message;

  @override
  String toString() => 'GroupPermissionError: $message';
}

class GroupService {
  final ApiClient _apiClient;

  GroupService(this._apiClient);

  Future<Group> createGroup(String name) async {
    final data = await _apiClient.rpc('create_group', {'p_name': name});
    return Group.fromJson(data as Map<String, dynamic>);
  }

  Future<Group> joinByHash(String hash) async {
    final data = await _apiClient.rpc('join_group_by_hash', {'p_hash': hash});
    return Group.fromJson(data as Map<String, dynamic>);
  }

  Future<Group> regenerateInvite(String groupId) async {
    final data = await _apiClient
        .rpc('regenerate_group_invite', {'p_group_id': groupId});
    return Group.fromJson(data as Map<String, dynamic>);
  }

  Future<String> getInvite(String groupId) async {
    final data =
        await _apiClient.rpc('get_group_invite', {'p_group_id': groupId});
    if (data == null) {
      throw GroupPermissionError(
          'Apenas administradores podem ver o convite deste grupo');
    }
    return data as String;
  }

  Future<void> setMemberRole(
          String groupId, String userId, String role) =>
      _apiClient.rpc('set_member_role', {
        'p_group_id': groupId,
        'p_user_id': userId,
        'p_role': role,
      });

  Future<Group> setTracking(String groupId, bool enabled) async {
    final data = await _apiClient.rpc('set_group_tracking', {
      'p_group_id': groupId,
      'p_enabled': enabled,
    });
    return Group.fromJson(data as Map<String, dynamic>);
  }

  Future<List<GroupMember>> listMembers(String groupId) async {
    final data = await _apiClient
        .rpc('list_group_members', {'p_group_id': groupId});
    return (data as List)
        .map((e) => GroupMember.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<TrackingPoint>> listTracking(String groupId) async {
    final data = await _apiClient
        .rpc('list_group_tracking', {'p_group_id': groupId});
    return (data as List)
        .map((e) => TrackingPoint.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Grupos do usuário logado, com o papel dele em cada um. Nunca inclui
  /// `invite_hash` no embed — a coluna não tem GRANT de SELECT pra web_user
  /// (ver db/schema/007_groups.sql), então um `groups(*)` aqui faria o
  /// PostgREST recusar a query inteira.
  Future<List<MyGroup>> listMyGroups(String userId) async {
    final data = await _apiClient.get('group_members', query: {
      'user_id': 'eq.$userId',
      'select': 'role,joined_at,groups(id,name,tracking_enabled,created_by,created_at)',
    });
    return (data as List)
        .map((e) => MyGroup.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
