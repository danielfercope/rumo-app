import 'group_model.dart';

class GroupMember {
  final String userId;
  final String nome;
  final String email;
  final String departamento;
  final String role;
  final DateTime joinedAt;

  const GroupMember({
    required this.userId,
    required this.nome,
    required this.email,
    required this.departamento,
    required this.role,
    required this.joinedAt,
  });

  bool get isAdmin => role == 'admin';

  factory GroupMember.fromJson(Map<String, dynamic> json) => GroupMember(
        userId: json['user_id'] as String,
        nome: json['nome'] as String? ?? '',
        email: json['email'] as String? ?? '',
        departamento: json['departamento'] as String? ?? '',
        role: json['role'] as String,
        joinedAt: DateTime.parse(json['joined_at'] as String),
      );
}

/// Resultado do embed `GET /rest/group_members?select=role,joined_at,groups(...)`
/// — o papel do usuário logado num grupo específico, junto com os dados do
/// grupo em si.
class MyGroup {
  final Group group;
  final String role;
  final DateTime joinedAt;

  const MyGroup(
      {required this.group, required this.role, required this.joinedAt});

  bool get isAdmin => role == 'admin';

  factory MyGroup.fromJson(Map<String, dynamic> json) => MyGroup(
        group: Group.fromJson(json['groups'] as Map<String, dynamic>),
        role: json['role'] as String,
        joinedAt: DateTime.parse(json['joined_at'] as String),
      );
}

/// Posição de um membro da equipe (retorno de `list_group_tracking`).
class TrackingPoint {
  final String userId;
  final String nome;
  final String email;
  final double latitude;
  final double longitude;
  final DateTime? ultimoVisto;

  /// URL da foto da conta Google; `null` cai nas iniciais.
  final String? fotoUrl;

  const TrackingPoint({
    required this.userId,
    required this.nome,
    required this.email,
    required this.latitude,
    required this.longitude,
    this.ultimoVisto,
    this.fotoUrl,
  });

  factory TrackingPoint.fromJson(Map<String, dynamic> json) => TrackingPoint(
        userId: json['user_id'] as String,
        nome: json['nome'] as String? ?? '',
        email: json['email'] as String? ?? '',
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        ultimoVisto: json['ultimo_visto'] == null
            ? null
            : DateTime.parse(json['ultimo_visto'] as String).toLocal(),
        fotoUrl: json['foto_url'] as String?,
      );
}

/// Uma posição do histórico de deslocamento de um membro (`tracking_history`).
class TrackingHistoryPoint {
  final double latitude;
  final double longitude;
  final DateTime capturedAt;

  const TrackingHistoryPoint({
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
  });

  factory TrackingHistoryPoint.fromJson(Map<String, dynamic> json) =>
      TrackingHistoryPoint(
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        capturedAt: DateTime.parse(json['captured_at'] as String).toLocal(),
      );
}
