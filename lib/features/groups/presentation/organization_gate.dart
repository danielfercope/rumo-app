import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../carteira/presentation/crm_connection_wizard.dart';
import '../providers/group_provider.dart';

/// Espera saber a quais organizações o usuário pertence antes de montar o app.
/// Quem decide as abas é o `MainNavigation`: sem organização só existem Perfil
/// e Organização (criar uma ou entrar com um código); Radar e Leads só com ela.
///
/// É a barreira da interface; a de verdade fica no servidor (RLS + RPCs), que
/// recusa busca e leitura de quem não é membro mesmo que o app seja burlado.
class OrganizationGate extends ConsumerWidget {
  const OrganizationGate({super.key, required this.child});

  /// O app propriamente dito (as abas).
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = ref.watch(myGroupsProvider);

    return groups.when(
      // Recarregar a lista (ligar rastreamento, trocar papel...) não pode
      // desmontar o app e perder o estado das abas.
      skipLoadingOnReload: true,
      loading: () => const CupertinoPageScaffold(
        child: Center(child: CupertinoActivityIndicator()),
      ),
      error: (e, _) => CupertinoPageScaffold(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Não foi possível carregar suas organizações',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 17, fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Text('$e',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: CupertinoColors.systemGrey)),
                const SizedBox(height: 12),
                CupertinoButton.filled(
                  onPressed: () => ref.invalidate(myGroupsProvider),
                  child: const Text('Tentar novamente'),
                ),
              ],
            ),
          ),
        ),
      ),
      data: (_) => _OpenCrmSetupOnce(child: child),
    );
  }
}

/// Logo depois de criar uma organização, abre o assistente pra conectar o CRM
/// dela (uma vez; dá pra fechar e conectar depois pela gestão do grupo).
class _OpenCrmSetupOnce extends ConsumerStatefulWidget {
  const _OpenCrmSetupOnce({required this.child});

  final Widget child;

  @override
  ConsumerState<_OpenCrmSetupOnce> createState() => _OpenCrmSetupOnceState();
}

class _OpenCrmSetupOnceState extends ConsumerState<_OpenCrmSetupOnce> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _openIfPending());
  }

  void _openIfPending() {
    if (!mounted) return;
    final groupId = ref.read(pendingCrmSetupGroupIdProvider);
    if (groupId == null) return;
    ref.read(pendingCrmSetupGroupIdProvider.notifier).state = null;
    Navigator.of(context).push<bool>(
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (_) => CrmConnectionWizard(groupId: groupId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<String?>(pendingCrmSetupGroupIdProvider, (_, id) {
      if (id != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _openIfPending());
      }
    });
    return widget.child;
  }
}
