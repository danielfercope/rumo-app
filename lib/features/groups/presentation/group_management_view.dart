import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../carteira/presentation/crm_connection_section.dart';
import '../models/group_member_model.dart';
import '../models/group_model.dart';
import '../providers/group_provider.dart';
import 'team_map_page.dart';

class GroupManagementView extends ConsumerWidget {
  const GroupManagementView({super.key});

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    bool destructive = false,
  }) async {
    final confirmed = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: destructive,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirmar'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _runOrShowError(
      BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (!context.mounted) return;
      showCupertinoDialog(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Não foi possível concluir'),
          content: Text('$e'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }
  }

  Future<void> _showInvite(
      BuildContext context, WidgetRef ref, Group group) async {
    await showCupertinoModalPopup(
      context: context,
      builder: (ctx) => _InviteSheet(groupId: group.id),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myGroups = ref.watch(myGroupsProvider).value ?? [];
    final active = ref.watch(activeGroupProvider);
    final isAdmin = ref.watch(isActiveGroupAdminProvider);

    if (active == null) {
      return const Center(child: CupertinoActivityIndicator());
    }

    final group = active.group;
    final membersAsync = ref.watch(groupMembersProvider(group.id));

    Future<void> changeRole(GroupMember m, String role) async {
      final destructive = role == 'member';
      final ok = await _confirm(
        context,
        title: destructive ? 'Remover admin' : 'Promover a admin',
        message: destructive
            ? '${m.nome} deixará de ser administrador deste grupo.'
            : '${m.nome} passará a administrar este grupo.',
        destructive: destructive,
      );
      if (!ok || !context.mounted) return;
      await _runOrShowError(context, () async {
        await ref
            .read(groupServiceProvider)
            .setMemberRole(group.id, m.userId, role);
        ref.invalidate(groupMembersProvider(group.id));
      });
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: [
        if (myGroups.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: CupertinoSlidingSegmentedControl<String>(
              groupValue: group.id,
              children: {
                for (final g in myGroups)
                  g.group.id: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text(g.group.name, overflow: TextOverflow.ellipsis),
                  ),
              },
              onValueChanged: (id) {
                if (id != null) {
                  ref.read(activeGroupIdProvider.notifier).state = id;
                }
              },
            ),
          ),
        _GroupHeader(
          name: group.name,
          isAdmin: isAdmin,
          memberCount: membersAsync.valueOrNull?.length,
        ),
        CupertinoListSection.insetGrouped(
          header: const Text('Membros'),
          children: membersAsync.when(
            data: (members) => [
              for (final m in members)
                _MemberRow(
                  member: m,
                  isAdmin: isAdmin,
                  onTap: () => _pickRoleAction(context, m, changeRole),
                ),
            ],
            loading: () => const [
              CupertinoListTile.notched(
                title: Center(child: CupertinoActivityIndicator()),
              ),
            ],
            error: (e, _) => [
              CupertinoListTile.notched(
                title: Text('Erro ao carregar membros: $e',
                    style:
                        const TextStyle(color: CupertinoColors.destructiveRed)),
              ),
            ],
          ),
        ),
        if (isAdmin) ...[
          CupertinoListSection.insetGrouped(
            header: const Text('Convite'),
            footer: const Text(
                'Quem tiver o código entra no grupo. Regenere se ele vazar.'),
            children: [
              CupertinoListTile.notched(
                leading: const _IconBadge(CupertinoIcons.person_badge_plus,
                    CupertinoColors.systemBlue),
                title: const Text('Convite do grupo'),
                subtitle: const Text('Ver, copiar ou regenerar o código'),
                trailing: const CupertinoListTileChevron(),
                onTap: () => _showInvite(context, ref, group),
              ),
            ],
          ),
          CupertinoListSection.insetGrouped(
            header: const Text('Rastreamento de localização'),
            footer: const Text(
                'Quando ativado, a posição dos membros aparece no mapa da equipe.'),
            children: [
              CupertinoListTile.notched(
                leading: const _IconBadge(
                    CupertinoIcons.location_fill, CupertinoColors.systemGreen),
                title: const Text('Rastreamento'),
                subtitle: Text(group.trackingEnabled
                    ? 'Ativado para este grupo'
                    : 'Desativado para este grupo'),
                trailing: CupertinoSwitch(
                  value: group.trackingEnabled,
                  onChanged: (enabled) => _runOrShowError(context, () async {
                    await ref
                        .read(groupServiceProvider)
                        .setTracking(group.id, enabled);
                    ref.invalidate(myGroupsProvider);
                  }),
                ),
              ),
              if (group.trackingEnabled)
                CupertinoListTile.notched(
                  leading: const _IconBadge(
                      CupertinoIcons.map_fill, CupertinoColors.systemOrange),
                  title: const Text('Ver mapa da equipe'),
                  trailing: const CupertinoListTileChevron(),
                  onTap: () => Navigator.push(
                    context,
                    CupertinoPageRoute(
                      builder: (_) => TeamMapPage(groupId: group.id),
                    ),
                  ),
                ),
            ],
          ),
          CrmConnectionSection(groupId: group.id),
        ],
      ],
    );
  }

  Future<void> _pickRoleAction(
    BuildContext context,
    GroupMember m,
    Future<void> Function(GroupMember, String) changeRole,
  ) async {
    final role = await showCupertinoModalPopup<String>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(m.nome),
        message: Text(m.email),
        actions: [
          CupertinoActionSheetAction(
            isDestructiveAction: m.isAdmin,
            onPressed: () => Navigator.pop(ctx, m.isAdmin ? 'member' : 'admin'),
            child: Text(m.isAdmin ? 'Remover admin' : 'Promover a admin'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
      ),
    );
    if (role != null) await changeRole(m, role);
  }
}

class _GroupHeader extends StatelessWidget {
  const _GroupHeader({
    required this.name,
    required this.isAdmin,
    required this.memberCount,
  });

  final String name;
  final bool isAdmin;
  final int? memberCount;

  @override
  Widget build(BuildContext context) {
    final parts = [
      if (memberCount != null)
        memberCount == 1 ? '1 membro' : '$memberCount membros',
      if (isAdmin) 'Você administra',
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: CupertinoColors.systemBlue,
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(_initial(name),
                style: const TextStyle(
                    color: CupertinoColors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 22, fontWeight: FontWeight.w700)),
                if (parts.isNotEmpty)
                  Text(parts.join(' · '),
                      style: const TextStyle(
                          fontSize: 14, color: CupertinoColors.systemGrey)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _initial(String name) {
  final t = name.trim();
  return t.isEmpty ? '?' : t.characters.first.toUpperCase();
}

class _IconBadge extends StatelessWidget {
  const _IconBadge(this.icon, this.color);

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(7),
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 18, color: CupertinoColors.white),
      );
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.member,
    required this.isAdmin,
    required this.onTap,
  });

  final GroupMember member;
  final bool isAdmin;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final role = Text(
      member.isAdmin ? 'Admin' : 'Membro',
      style: TextStyle(
        fontSize: 13,
        fontWeight: member.isAdmin ? FontWeight.w600 : FontWeight.w400,
        color: member.isAdmin
            ? CupertinoColors.activeBlue
            : CupertinoColors.systemGrey,
      ),
    );
    return CupertinoListTile.notched(
      leading: Container(
        decoration: BoxDecoration(
          color: CupertinoColors.systemGrey4.resolveFrom(context),
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Text(_initial(member.nome),
            style: const TextStyle(fontWeight: FontWeight.w600)),
      ),
      title: Text(member.nome.isEmpty ? member.email : member.nome),
      subtitle: Text(member.email),
      additionalInfo: role,
      trailing: isAdmin ? const CupertinoListTileChevron() : null,
      onTap: isAdmin ? onTap : null,
    );
  }
}

class _InviteSheet extends ConsumerWidget {
  const _InviteSheet({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inviteAsync = ref.watch(groupInviteProvider(groupId));

    return CupertinoActionSheet(
      title: const Text('Convite do grupo'),
      message: inviteAsync.when(
        data: (hash) => SelectableText(hash),
        loading: () => const CupertinoActivityIndicator(),
        error: (e, _) => Text('Erro: $e'),
      ),
      actions: [
        CupertinoActionSheetAction(
          onPressed: () {
            final hash = inviteAsync.value;
            if (hash != null) {
              Clipboard.setData(ClipboardData(text: hash));
            }
            Navigator.pop(context);
          },
          child: const Text('Copiar'),
        ),
        CupertinoActionSheetAction(
          onPressed: () async {
            final confirmed = await showCupertinoDialog<bool>(
              context: context,
              builder: (ctx) => CupertinoAlertDialog(
                title: const Text('Regenerar convite'),
                content: const Text(
                    'O código atual deixará de funcionar imediatamente.'),
                actions: [
                  CupertinoDialogAction(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Cancelar'),
                  ),
                  CupertinoDialogAction(
                    isDestructiveAction: true,
                    onPressed: () => Navigator.pop(ctx, true),
                    child: const Text('Regenerar'),
                  ),
                ],
              ),
            );
            if (confirmed == true) {
              await ref.read(groupServiceProvider).regenerateInvite(groupId);
              ref.invalidate(groupInviteProvider(groupId));
            }
          },
          child: const Text('Regenerar'),
        ),
      ],
      cancelButton: CupertinoActionSheetAction(
        onPressed: () => Navigator.pop(context),
        child: const Text('Fechar'),
      ),
    );
  }
}
