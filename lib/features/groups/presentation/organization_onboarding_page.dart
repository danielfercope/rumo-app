import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/providers/auth_provider.dart';
import '../providers/group_provider.dart';
import 'group_onboarding_view.dart';

/// Primeira tela de quem ainda não pertence a nenhuma organização. É a ÚNICA
/// coisa que esse usuário enxerga: sem organização não há mapa, busca nem leads,
/// porque a base de clientes é da organização e só os membros dela a veem.
///
/// Duas saídas: criar uma organização (e conectar o CRM dela em seguida) ou
/// entrar numa que já existe, colando o código de convite.
class OrganizationOnboardingPage extends ConsumerWidget {
  const OrganizationOnboardingPage({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
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
    return CupertinoPageScaffold(
      navigationBar: CupertinoNavigationBar(
        middle: const Text('Bem-vindo ao RUMO'),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => _signOut(context, ref),
          child: const Text('Sair'),
        ),
      ),
      child: SafeArea(
        child: Column(
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Column(
                children: [
                  Icon(CupertinoIcons.building_2_fill,
                      size: 44, color: CupertinoColors.systemYellow),
                  SizedBox(height: 12),
                  Text(
                    'Para começar, escolha uma organização',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Os clientes e leads ficam na carteira da organização, e só '
                    'quem faz parte dela os vê. Crie a sua e conecte o seu CRM, '
                    'ou entre em uma que já existe com o código de convite.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 14, color: CupertinoColors.systemGrey),
                  ),
                ],
              ),
            ),
            Expanded(
              child: GroupOnboardingView(
                showHeader: false,
                // depois de criar, o gate abre o assistente pra conectar o CRM
                onCreated: (group) => ref
                    .read(pendingCrmSetupGroupIdProvider.notifier)
                    .state = group.id,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
