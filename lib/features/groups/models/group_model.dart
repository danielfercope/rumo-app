class Group {
  final String id;
  final String name;
  final bool trackingEnabled;
  final String createdBy;
  final DateTime createdAt;

  /// Só vem preenchido quando a própria resposta da RPC o inclui
  /// (create_group/join_group_by_hash/regenerate_group_invite/get_group_invite) —
  /// a listagem geral de grupos (myGroupsProvider) nunca o traz, porque a
  /// coluna é excluída do GRANT de SELECT (só admin vê, via RPC dedicada).
  final String? inviteHash;

  const Group({
    required this.id,
    required this.name,
    required this.trackingEnabled,
    required this.createdBy,
    required this.createdAt,
    this.inviteHash,
  });

  factory Group.fromJson(Map<String, dynamic> json) => Group(
        id: json['id'] as String,
        name: json['name'] as String,
        trackingEnabled: json['tracking_enabled'] as bool? ?? false,
        createdBy: json['created_by'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
        inviteHash: json['invite_hash'] as String?,
      );
}
