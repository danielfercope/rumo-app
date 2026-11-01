import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (myGroups.length > 1) ...[
          CupertinoSlidingSegmentedControl<String>(
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
          const SizedBox(height: 20),
        ] else
          Text(group.name,
              style:
                  const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        const SizedBox(height: 16),
        const Text('Membros', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        membersAsync.when(
          data: (members) => Column(
            children: members
                .map((m) => _MemberRow(
                      groupId: group.id,
                      member: m,
                      isAdmin: isAdmin,
                      onChangeRole: (role) async {
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
                      },
                    ))
                .toList(),
          ),
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => Text('Erro ao carregar membros: $e'),
        ),
        if (isAdmin) ...[
          const SizedBox(height: 24),
          const Text('Convite', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          CupertinoButton(
            padding: EdgeInsets.zero,
            onPressed: () => _showInvite(context, ref, group),
            child: const Text('Mostrar convite'),
          ),
          const SizedBox(height: 24),
          const Text('Rastreamento de localização',
              style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(group.trackingEnabled
                    ? 'Ativado para este grupo'
                    : 'Desativado para este grupo'),
              ),
              CupertinoSwitch(
                value: group.trackingEnabled,
                onChanged: (enabled) => _runOrShowError(context, () async {
                  await ref
                      .read(groupServiceProvider)
                      .setTracking(group.id, enabled);
                  ref.invalidate(myGroupsProvider);
                }),
              ),
            ],
          ),
          if (group.trackingEnabled) ...[
            const SizedBox(height: 8),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => Navigator.push(
                context,
                CupertinoPageRoute(
                  builder: (_) => TeamMapPage(groupId: group.id),
                ),
              ),
              child: const Text('Ver mapa da equipe'),
            ),
          ],
        ],
      ],
    );
  }
}

class _MemberRow extends StatelessWidget {
  const _MemberRow({
    required this.groupId,
    required this.member,
    required this.isAdmin,
    required this.onChangeRole,
  });

  final String groupId;
  final GroupMember member;
  final bool isAdmin;
  final void Function(String role) onChangeRole;

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      title: Text(member.nome),
      subtitle: Text(member.email),
      trailing: isAdmin
          ? CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () =>
                  onChangeRole(member.isAdmin ? 'member' : 'admin'),
              child: Text(member.isAdmin ? 'Despromover' : 'Promover'),
            )
          : Text(member.isAdmin ? 'Admin' : 'Membro'),
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
