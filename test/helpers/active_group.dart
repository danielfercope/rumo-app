import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rumo_app/features/groups/models/group_member_model.dart';
import 'package:rumo_app/features/groups/models/group_model.dart';
import 'package:rumo_app/features/groups/providers/group_provider.dart';

/// Organização de teste. As buscas do app só rodam com uma organização ativa.
MyGroup fakeMyGroup({String id = 'g1', String role = 'admin'}) => MyGroup(
      group: Group(
        id: id,
        name: 'Agro Sul',
        trackingEnabled: false,
        createdBy: 'u1',
        createdAt: DateTime(2026, 1, 1),
      ),
      role: role,
      joinedAt: DateTime(2026, 1, 1),
    );

/// Override que deixa `g1` como a organização ativa.
Override activeGroupOverride([MyGroup? group]) =>
    activeGroupProvider.overrideWithValue(group ?? fakeMyGroup());

/// Override de quem ainda não pertence a nenhuma organização.
Override noActiveGroupOverride() => activeGroupProvider.overrideWithValue(null);
