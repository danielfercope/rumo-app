import 'package:flutter/cupertino.dart';

import '../../../core/format/br_format.dart';
import '../models/crm_models.dart';

/// Texto da linha de andamento da carga inicial ("230 de 502 empresas · faltam
/// ~4 min"). Separado do widget pra ser testado sem desenhar nada.
String importProgressLine(SyncLog? log, DateTime now) {
  if (log == null || (log.processadas == 0 && log.estimado == null)) {
    return 'Preparando a importação…';
  }
  final total = log.estimado;
  final base = total == null
      ? '${log.processadas} empresas processadas'
      : '${log.processadas} de $total empresas';
  final restante = log.tempoRestante(now);
  if (restante != null) return '$base · faltam ${_aprox(restante)}';
  if (log.processadas == 0) return '$base · iniciando…';
  return base;
}

String _aprox(Duration d) =>
    d.inMinutes < 1 ? 'menos de 1 min' : '~${formatDurationBr(d)}';

/// Andamento da carga inicial: percentual, barra e estimativa de término.
class ImportProgress extends StatelessWidget {
  const ImportProgress({super.key, required this.log, this.now});

  final SyncLog? log;

  /// Relógio injetável (testes).
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final accent = CupertinoTheme.of(context).primaryColor;
    final progress = log?.progresso;
    final secondary = CupertinoColors.secondaryLabel.resolveFrom(context);
    final falhas = log?.falhas ?? 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const CupertinoActivityIndicator(radius: 9),
              const SizedBox(width: 10),
              const Expanded(
                child: Text('Importando sua carteira',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              ),
              if (progress != null)
                Text('${(progress * 100).floor()}%',
                    key: const ValueKey('import-percent'),
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: SizedBox(
              height: 8,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: ColoredBox(
                        color: CupertinoColors.tertiarySystemFill
                            .resolveFrom(context)),
                  ),
                  if (progress != null)
                    FractionallySizedBox(
                      widthFactor: progress,
                      child: ColoredBox(color: accent),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(importProgressLine(log, now ?? DateTime.now()),
              key: const ValueKey('import-line'),
              style: TextStyle(fontSize: 14, color: secondary)),
          if (log != null && (log!.novas > 0 || falhas > 0)) ...[
            const SizedBox(height: 2),
            Text(
              '${log!.novas} importadas'
              '${falhas > 0 ? ' · $falhas com falha (serão tentadas de novo)' : ''}',
              style: TextStyle(
                  fontSize: 13,
                  color: falhas > 0 ? CupertinoColors.systemOrange : secondary),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            'Pode sair desta tela: a importação continua no servidor.',
            style: TextStyle(fontSize: 12, color: secondary),
          ),
        ],
      ),
    );
  }
}
