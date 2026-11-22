import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../enrichment/presentation/enrichment_cards.dart';
import '../models/tax_diagnosis.dart';
import '../providers/diagnosis_provider.dart';

const _ink = CupertinoColors.black;
const _muted = CupertinoColors.systemGrey;
const _iconColor = Color(0xFF1E9E54);
const _title = 'Oportunidade tributária';

Color confidenceColor(Confidence c) => switch (c) {
      Confidence.alta => const Color(0xFF1E9E54),
      Confidence.media => CupertinoColors.systemOrange,
      Confidence.baixa => CupertinoColors.systemGrey,
    };

String confidenceLabel(Confidence c) => switch (c) {
      Confidence.alta => 'Confiança alta',
      Confidence.media => 'Confiança média',
      Confidence.baixa => 'Confiança baixa',
    };

/// "Por onde atacar": a provável principal oportunidade de recuperação
/// tributária da empresa, com as evidências e como abordar.
class TaxOpportunityCard extends ConsumerWidget {
  const TaxOpportunityCard(
      {super.key, required this.groupId, required this.cnpj});

  final String groupId;
  final String cnpj;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (groupId: groupId, cnpj: cnpj);
    final async = ref.watch(taxDiagnosisProvider(key));

    Widget line(String text, {Widget? trailing}) => DetailCard(
          icon: CupertinoIcons.scope,
          iconColor: _iconColor,
          title: _title,
          summary: Row(children: [
            Expanded(
              child: Text(text,
                  style: const TextStyle(fontSize: 13, color: _muted)),
            ),
            if (trailing != null) trailing,
          ]),
        );
    final retry = CupertinoButton(
      padding: EdgeInsets.zero,
      minimumSize: Size.zero,
      onPressed: () => ref.invalidate(taxDiagnosisProvider(key)),
      child: const Text('Tentar de novo', style: TextStyle(fontSize: 13)),
    );

    return async.when(
      loading: () => line('Analisando os dados públicos…',
          trailing: const CupertinoActivityIndicator(radius: 8)),
      error: (_, __) =>
          line('Não foi possível analisar agora.', trailing: retry),
      data: (d) {
        if (d.status == DiagnosisStatus.indisponivel) {
          return line('A Receita Federal não respondeu agora.',
              trailing: retry);
        }
        if (d.status == DiagnosisStatus.vazio) return const SizedBox.shrink();
        if (d.bloqueio != null) return line(d.bloqueio!);
        final principal = d.principal;
        if (principal == null) {
          return line(
              'Nenhum sinal de imposto pago a mais nos dados públicos desta empresa.');
        }
        return TaxOpportunityView(diagnosis: d, principal: principal);
      },
    );
  }
}

class TaxOpportunityView extends StatelessWidget {
  const TaxOpportunityView(
      {super.key, required this.diagnosis, required this.principal});

  final TaxDiagnosis diagnosis;
  final TaxFinding principal;

  @override
  Widget build(BuildContext context) {
    final p = principal;
    final footer = [
      if (diagnosis.aviso != null) diagnosis.aviso!,
      if (diagnosis.fontesFaltando.contains('compras'))
        'Compras públicas indisponíveis agora: a tese de retenções não foi avaliada.',
    ].join(' ');
    return DetailCard(
      icon: CupertinoIcons.scope,
      iconColor: _iconColor,
      title: _title,
      footer: footer.isEmpty ? null : footer,
      summary: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(p.titulo,
              style: const TextStyle(
                  fontSize: 16, fontWeight: FontWeight.w700, color: _ink)),
          const SizedBox(height: 8),
          Wrap(spacing: 6, runSpacing: 6, children: [
            Pill(confidenceLabel(p.confianca),
                color: confidenceColor(p.confianca)),
            if (p.periodo != null)
              Pill('Período ${p.periodo}', icon: CupertinoIcons.calendar),
            if (p.tributos.isNotEmpty) Pill(p.tributos.join(', ')),
          ]),
          const SizedBox(height: 10),
          for (final e in p.evidencias.take(3)) _Bullet(e.texto),
          const SizedBox(height: 2),
          const Text('Toque para ver como abordar',
              style: TextStyle(fontSize: 11, color: _muted)),
        ],
      ),
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Section('Por que', child: _Paragraph(p.resumo)),
          if (p.comoAbordar != null)
            _Section('Como abordar', child: _Paragraph(p.comoAbordar!)),
          if (p.perguntas.isNotEmpty)
            _Section('Perguntas para validar na visita',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [for (final q in p.perguntas) _Bullet(q)],
                )),
          if (p.evidencias.length > 3)
            _Section('Outras evidências',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final e in p.evidencias.skip(3)) _Bullet(e.texto)
                  ],
                )),
          if (p.baseLegal != null)
            _Section('Base legal',
                child: _Paragraph([
                  p.baseLegal!,
                  if (p.situacaoJuridica != null) p.situacaoJuridica!,
                ].join('. '))),
          if (diagnosis.outras.isNotEmpty)
            _Section('Outras possibilidades',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final o in diagnosis.outras) _OtherFinding(o)
                  ],
                )),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.title, {required this.child});
  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title.toUpperCase(),
                style: const TextStyle(
                    fontSize: 11,
                    letterSpacing: 0.4,
                    fontWeight: FontWeight.w700,
                    color: _muted)),
            const SizedBox(height: 6),
            child,
          ],
        ),
      );
}

class _Paragraph extends StatelessWidget {
  const _Paragraph(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: const TextStyle(fontSize: 13, color: _ink, height: 1.35));
}

class _Bullet extends StatelessWidget {
  const _Bullet(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.only(top: 6, right: 8),
              child: SizedBox(
                width: 5,
                height: 5,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: _iconColor, shape: BoxShape.circle)),
              ),
            ),
            Expanded(
              child: Text(text,
                  style:
                      const TextStyle(fontSize: 13, color: _ink, height: 1.3)),
            ),
          ],
        ),
      );
}

class _OtherFinding extends StatelessWidget {
  const _OtherFinding(this.finding);
  final TaxFinding finding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(finding.titulo,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _ink)),
              ),
              const SizedBox(width: 8),
              Pill(
                  confidenceLabel(finding.confianca)
                      .replaceFirst('Confiança ', ''),
                  color: confidenceColor(finding.confianca)),
            ]),
            if (finding.evidencias.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(finding.evidencias.first.texto,
                    style: const TextStyle(fontSize: 12, color: _muted)),
              ),
          ],
        ),
      );
}
