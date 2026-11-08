import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/services/api_client.dart';
import '../../map/providers/company_provider.dart';
import '../models/crm_models.dart';
import '../providers/carteira_provider.dart';
import 'crm_connection_wizard.dart';

String _formatDateTime(DateTime d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} ${two(d.hour)}:${two(d.minute)}';
}

/// Seção "Integração com CRM" da gestão do grupo (só admin): mostra o estado
/// da conexão da organização e deixa conectar, sincronizar e desconectar.
class CrmConnectionSection extends ConsumerWidget {
  const CrmConnectionSection({super.key, required this.groupId});

  final String groupId;

  Future<void> _runOrShowError(
      BuildContext context, Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (!context.mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Não foi possível concluir'),
          content: Text(e is ApiException ? e.message : '$e'),
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

  void _refresh(WidgetRef ref) {
    ref.invalidate(crmConnectionProvider(groupId));
    ref.invalidate(lastSyncProvider(groupId));
  }

  Future<void> _openWizard(BuildContext context, WidgetRef ref) async {
    final connected = await Navigator.push<bool>(
      context,
      CupertinoPageRoute(
        fullscreenDialog: true,
        builder: (_) => CrmConnectionWizard(groupId: groupId),
      ),
    );
    if (connected == true) _refresh(ref);
  }

  Future<void> _syncNow(BuildContext context, WidgetRef ref) async {
    await _runOrShowError(context, () async {
      await ref.read(carteiraServiceProvider).sincronizarAgora(groupId);
      if (!context.mounted) return;
      await showCupertinoDialog<void>(
        context: context,
        builder: (ctx) => CupertinoAlertDialog(
          title: const Text('Sincronização iniciada'),
          content: const Text('O resultado aparece aqui em instantes.'),
          actions: [
            CupertinoDialogAction(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      // A sincronização roda no servidor; dá um tempo e recarrega o status.
      await Future<void>.delayed(const Duration(seconds: 4));
      if (context.mounted) _refresh(ref);
    });
  }

  Future<void> _disconnect(BuildContext context, WidgetRef ref) async {
    // null = cancelou; false = mantém a carteira; true = apaga a importada.
    final apagar = await showCupertinoModalPopup<bool>(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: const Text('Desconectar CRM'),
        message: const Text(
            'A sincronização para. Você pode manter a carteira já importada '
            'ou apagar as empresas que vieram do CRM.'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Desconectar e manter a carteira'),
          ),
          CupertinoActionSheetAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Desconectar e apagar a carteira importada'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
      ),
    );
    if (apagar == null || !context.mounted) return;
    await _runOrShowError(context, () async {
      await ref
          .read(carteiraServiceProvider)
          .desconectar(groupId, apagarCarteira: apagar);
      _refresh(ref);
      ref.invalidate(companiesProvider);
    });
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Quando a carga inicial termina, o mapa precisa buscar de novo: é aí que
    // os status da carteira passam a aparecer.
    ref.listen<AsyncValue<CrmConnection?>>(crmConnectionProvider(groupId),
        (prev, next) {
      final before = prev?.valueOrNull?.status;
      final now = next.valueOrNull?.status;
      if (before == CrmConnectionStatus.importando &&
          now != null &&
          now != CrmConnectionStatus.importando) {
        ref.invalidate(companiesProvider);
      }
    });

    final connection = ref.watch(crmConnectionProvider(groupId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Integração com CRM',
            style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        connection.when(
          skipLoadingOnReload: true,
          loading: () => const Center(child: CupertinoActivityIndicator()),
          error: (e, _) => Text('Erro ao carregar a integração: $e'),
          data: (conn) => conn == null
              ? _buildDisconnected(context, ref)
              : _buildConnected(context, ref, conn),
        ),
      ],
    );
  }

  Widget _buildDisconnected(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Nenhum CRM conectado. Conecte o HubSpot para importar sua '
            'carteira de clientes e leads.'),
        CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: () => _openWizard(context, ref),
          child: const Text('Conectar HubSpot'),
        ),
      ],
    );
  }

  Widget _buildConnected(
      BuildContext context, WidgetRef ref, CrmConnection conn) {
    final lastSync = ref.watch(lastSyncProvider(groupId)).valueOrNull;
    final importing = conn.status == CrmConnectionStatus.importando;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        switch (conn.status) {
          CrmConnectionStatus.importando => const Row(
              children: [
                CupertinoActivityIndicator(),
                SizedBox(width: 8),
                Expanded(child: Text('Importando sua carteira…')),
              ],
            ),
          CrmConnectionStatus.conectado => Text(
              conn.ultimaSincronizacao == null
                  ? 'HubSpot conectado'
                  : 'HubSpot conectado · última sincronização em '
                      '${_formatDateTime(conn.ultimaSincronizacao!)}',
            ),
          CrmConnectionStatus.erro => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Problema na integração',
                    style: TextStyle(
                        color: CupertinoColors.destructiveRed,
                        fontWeight: FontWeight.w600)),
                if (conn.ultimoErro != null) Text(conn.ultimoErro!),
              ],
            ),
        },
        if (lastSync != null) ...[
          const SizedBox(height: 4),
          Text(
            'Última carga: ${lastSync.lidas} lidas · ${lastSync.novas} novas · '
            '${lastSync.atualizadas} atualizadas'
            '${lastSync.falhas > 0 ? ' · ${lastSync.falhas} com falha' : ''}',
            style: const TextStyle(color: CupertinoColors.systemGrey),
          ),
        ],
        const SizedBox(height: 4),
        Wrap(
          children: [
            if (!importing)
              CupertinoButton(
                padding: const EdgeInsets.only(right: 16),
                onPressed: () => _syncNow(context, ref),
                child: const Text('Sincronizar agora'),
              ),
            CupertinoButton(
              padding: const EdgeInsets.only(right: 16),
              onPressed: () => _openWizard(context, ref),
              child: const Text('Reconectar'),
            ),
            CupertinoButton(
              padding: EdgeInsets.zero,
              onPressed: () => _disconnect(context, ref),
              child: const Text('Desconectar',
                  style: TextStyle(color: CupertinoColors.destructiveRed)),
            ),
          ],
        ),
      ],
    );
  }
}
