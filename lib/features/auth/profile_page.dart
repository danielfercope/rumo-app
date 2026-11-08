import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../groups/providers/group_provider.dart';
import '../map/widgets/user_avatar.dart';
import 'privacy_policy_page.dart';
import 'providers/auth_provider.dart';
import 'providers/profile_provider.dart';

/// Aba "Perfil": identidade do usuário, o que ele pode fazer no app, os
/// grupos a que pertence e as ações da conta.
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final ok = await showCupertinoDialog<bool>(
      context: context,
      builder: (ctx) => CupertinoAlertDialog(
        title: const Text('Sair da conta'),
        content: const Text('Você precisará entrar novamente para usar o app.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sair'),
          ),
        ],
      ),
    );
    if (ok == true) await ref.read(authControllerProvider).signOut();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(profileProvider);
    final groupsAsync = ref.watch(myGroupsProvider);

    return CupertinoPageScaffold(
      navigationBar: const CupertinoNavigationBar(middle: Text('Perfil')),
      child: SafeArea(
        child: profileAsync.when(
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text('Erro ao carregar o perfil: $e',
                  textAlign: TextAlign.center),
            ),
          ),
          data: (profile) => ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              if (profile != null) ...[
                _Header(
                  profile: profile,
                  photoUrl: ref.watch(userPhotoUrlProvider),
                ),
                CupertinoListSection.insetGrouped(
                  header: const Text('Conta'),
                  children: [
                    _InfoTile(
                      icon: CupertinoIcons.mail,
                      label: 'E-mail',
                      value: profile.email.isEmpty ? '—' : profile.email,
                    ),
                    _InfoTile(
                      icon: CupertinoIcons.briefcase,
                      label: 'Departamento',
                      value: profile.departamento.isEmpty
                          ? '—'
                          : profile.departamento,
                    ),
                    _InfoTile(
                      icon: CupertinoIcons.shield,
                      label: 'Nível de acesso',
                      value: _accessLabel(profile.nivelAcesso),
                    ),
                    _InfoTile(
                      icon: CupertinoIcons.building_2_fill,
                      label: 'Cadastrar empresas',
                      value:
                          profile.canAddCompany ? 'Permitido' : 'Sem permissão',
                    ),
                  ],
                ),
              ],
              CupertinoListSection.insetGrouped(
                header: const Text('Grupos'),
                children: groupsAsync.when(
                  loading: () => const [
                    CupertinoListTile(title: CupertinoActivityIndicator()),
                  ],
                  error: (_, __) => const [
                    CupertinoListTile(
                        title: Text('Não foi possível carregar os grupos')),
                  ],
                  data: (groups) => groups.isEmpty
                      ? const [
                          CupertinoListTile(
                              title:
                                  Text('Você não participa de nenhum grupo')),
                        ]
                      : [
                          for (final g in groups)
                            CupertinoListTile(
                              leading: const Icon(CupertinoIcons.person_2),
                              title: Text(g.group.name),
                              additionalInfo:
                                  Text(g.isAdmin ? 'Admin' : 'Membro'),
                            ),
                        ],
                ),
              ),
              CupertinoListSection.insetGrouped(
                header: const Text('Sobre'),
                children: [
                  CupertinoListTile.notched(
                    leading: const Icon(CupertinoIcons.doc_text),
                    title: const Text('Política de Privacidade'),
                    trailing: const CupertinoListTileChevron(),
                    onTap: () => Navigator.push(
                      context,
                      CupertinoPageRoute(
                          builder: (_) => const PrivacyPolicyPage()),
                    ),
                  ),
                ],
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: CupertinoButton(
                  color: CupertinoColors.destructiveRed,
                  onPressed: () => _confirmSignOut(context, ref),
                  child: const Text('Sair da conta'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _accessLabel(String nivel) => switch (nivel) {
        'admin' => 'Administrador',
        'guest' => 'Convidado',
        _ => 'Usuário',
      };
}

class _Header extends StatelessWidget {
  const _Header({required this.profile, this.photoUrl});

  final UserProfile profile;
  final String? photoUrl;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        UserAvatar(
          initials: userInitials(profile.nome),
          photoUrl: photoUrl,
          size: 84,
          borderWidth: 2,
        ),
        const SizedBox(height: 12),
        Text(
          profile.nome.isEmpty ? 'Sem nome' : profile.nome,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          profile.email,
          style: const TextStyle(color: CupertinoColors.systemGrey),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return CupertinoListTile(
      leading: Icon(icon, color: CupertinoColors.activeBlue),
      title: Text(label),
      additionalInfo: Text(value),
    );
  }
}
