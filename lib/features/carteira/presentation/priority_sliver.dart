import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../groups/providers/group_provider.dart';
import '../../map/presentation/company_details_modal.dart';
import '../models/crm_models.dart';
import '../models/priority_models.dart';
import '../providers/carteira_provider.dart';

/// Conteúdo da visão "Prioridades" da aba Leads (um sliver, pra caber no
/// `CustomScrollView` da página). Os motivos ficam sempre visíveis: são a razão
/// de a ordem ser confiável.
class PrioritySliver extends ConsumerWidget {
  const PrioritySliver({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupId = ref.watch(activeGroupProvider)?.group.id;
    if (groupId == null) {
      return const _Message(
        'Entre em uma organização para ver as prioridades dos seus leads.',
      );
    }

    final data = ref.watch(priorityProvider(groupId));
    return data.when(
      skipLoadingOnReload: true,
      loading: () => const SliverFillRemaining(
        hasScrollBody: false,
        child: Center(child: CupertinoActivityIndicator()),
      ),
      error: (e, _) =>
          const _Message('Não foi possível carregar as prioridades.'
              ' Puxe para baixo para tentar de novo.'),
      data: (d) {
        if (d.semCrm) {
          return const _Message(
            'Conecte seu CRM para ver as prioridades. O administrador da '
            'organização faz isso na gestão do grupo.',
          );
        }
        if (d.calculando) {
          return const _Message(
            'Calculando as prioridades da sua carteira… Isso pode levar '
            'alguns minutos.',
            loading: true,
          );
        }
        if (d.resultado?.estrategia == null) {
          // Conexão com erro e nunca calculou: não há o que mostrar.
          return const _Message(
            'A integração com o CRM está com problema. Veja os detalhes na '
            'gestão do grupo.',
          );
        }
        return _PriorityList(
          result: d.resultado!,
          connectionError: d.conexao == CrmConnectionStatus.erro,
        );
      },
    );
  }
}

class _PriorityList extends StatelessWidget {
  final PriorityResult result;
  final bool connectionError;

  const _PriorityList({required this.result, required this.connectionError});

  @override
  Widget build(BuildContext context) {
    final items = result.itens;
    return SliverList(
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          if (index == 0) return _Header(result, connectionError);
          if (items.isEmpty) {
            return const Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Nenhum lead na sua carteira ainda.',
                textAlign: TextAlign.center,
                style: TextStyle(color: CupertinoColors.systemGrey),
              ),
            );
          }
          return _PriorityTile(
            item: items[index - 1],
            showScore: result.estrategia == PriorityStrategy.perfil,
          );
        },
        childCount: items.isEmpty ? 2 : items.length + 1,
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final PriorityResult result;
  final bool connectionError;

  const _Header(this.result, this.connectionError);

  @override
  Widget build(BuildContext context) {
    final interacao = result.estrategia == PriorityStrategy.interacao;
    final falta = result.clientesFaltando;
    final shown = result.itens.length;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            key: const ValueKey('priority-strategy-note'),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: CupertinoColors.activeBlue.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              interacao
                  ? 'Ordenado por interação no CRM (mais interações primeiro; '
                      'empate pelo registro mais antigo). Você tem '
                      '${result.nClientes} cliente(s); com mais $falta, '
                      'passamos a ordenar pela semelhança com o perfil dos '
                      'seus clientes.'
                  : 'Ordenado pela semelhança com o perfil dos seus '
                      '${result.nClientes} clientes. A nota compara cada lead '
                      'com os demais da carteira.',
              style: const TextStyle(fontSize: 13),
            ),
          ),
          if (connectionError) ...[
            const SizedBox(height: 8),
            const Text(
              'A última sincronização com o CRM falhou; os dados podem estar '
              'desatualizados.',
              style:
                  TextStyle(fontSize: 12, color: CupertinoColors.systemOrange),
            ),
          ],
          if (result.nLeads > shown && shown > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Mostrando os $shown primeiros de ${result.nLeads} leads.',
              style: const TextStyle(
                  fontSize: 12, color: CupertinoColors.systemGrey),
            ),
          ],
        ],
      ),
    );
  }
}

class _PriorityTile extends StatelessWidget {
  final PriorityItem item;
  final bool showScore;

  const _PriorityTile({required this.item, required this.showScore});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => showCupertinoModalPopup<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => CompanyDetailsModal(company: item.toCompany()),
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        decoration: const BoxDecoration(
          border: Border(
            bottom: BorderSide(color: CupertinoColors.separator, width: 0.5),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 36,
              child: Text(
                '#${item.posicao}',
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.systemGrey),
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.nome ?? 'Empresa',
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  if (item.local.isNotEmpty)
                    Text(item.local,
                        style: const TextStyle(
                            fontSize: 13, color: CupertinoColors.systemGrey)),
                  if (showScore && item.nota != null) ...[
                    const SizedBox(height: 6),
                    _ScoreBar(nota: item.nota!),
                  ],
                  for (final motivo in item.motivos)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(motivo, style: const TextStyle(fontSize: 13)),
                    ),
                ],
              ),
            ),
            const CupertinoListTileChevron(),
          ],
        ),
      ),
    );
  }
}

class _ScoreBar extends StatelessWidget {
  final int nota;

  const _ScoreBar({required this.nota});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(
              children: [
                Container(height: 6, color: CupertinoColors.systemGrey5),
                FractionallySizedBox(
                  widthFactor: nota.clamp(0, 100) / 100,
                  child: Container(
                    key: const ValueKey('score-bar-fill'),
                    height: 6,
                    color: CupertinoColors.activeBlue,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('$nota',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _Message extends StatelessWidget {
  final String text;
  final bool loading;

  const _Message(this.text, {this.loading = false});

  @override
  Widget build(BuildContext context) {
    return SliverFillRemaining(
      hasScrollBody: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (loading) ...[
                const CupertinoActivityIndicator(),
                const SizedBox(height: 12),
              ],
              Text(
                text,
                textAlign: TextAlign.center,
                style: const TextStyle(color: CupertinoColors.systemGrey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
