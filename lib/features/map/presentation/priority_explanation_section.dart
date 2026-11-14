import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/format/br_format.dart';
import '../../carteira/models/priority_models.dart';
import '../../carteira/providers/carteira_provider.dart';
import '../../groups/providers/group_provider.dart';
import '../models/company_model.dart';
import '../models/lead_tier.dart';
import '../models/priority_insight.dart';
import '../providers/company_provider.dart';
import '../providers/lead_tier_provider.dart';
import '../widgets/lead_pin.dart';

const _ink = CupertinoColors.black;
const _muted = CupertinoColors.systemGrey;
const _good = Color(0xFF1E9E54);
const _bad = Color(0xFFD64545);

/// "Por que esta prioridade": nota, faixa, o que pesa a favor e contra, e a
/// comparação com os leads mais perto ("vale a viagem?"). Só aparece pra lead.
class PriorityExplanationSection extends ConsumerWidget {
  const PriorityExplanationSection({super.key, required this.company});

  final Company company;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupId = ref.watch(activeGroupProvider)?.group.id;
    if (groupId == null || company.isClient == true) {
      return const SizedBox.shrink();
    }

    final explanation = ref.watch(
        priorityExplanationProvider((groupId: groupId, companyId: company.id)));
    return explanation.when(
      loading: () => const _Shell(
        child: Row(children: [
          CupertinoActivityIndicator(radius: 9),
          SizedBox(width: 10),
          Text('Calculando os motivos da prioridade…',
              style: TextStyle(fontSize: 14, color: _muted)),
        ]),
      ),
      error: (_, __) => const _Shell(
        child: Text('Não foi possível carregar a explicação da prioridade.',
            style: TextStyle(fontSize: 14, color: _muted)),
      ),
      data: (e) {
        if (e == null) return const SizedBox.shrink();

        final priorities = ref.watch(leadPriorityProvider).valueOrNull ?? {};
        final all = ref.watch(companiesProvider).valueOrNull ?? const [];
        final nearer = nearerLeads(company, all, priorities);

        // Pra explicar a diferença, busca os motivos do lead mais perto que
        // também tem nota.
        NearbyLead? closestRanked;
        for (final n in nearer) {
          if (n.info != null) {
            closestRanked = n;
            break;
          }
        }
        final other = closestRanked == null
            ? null
            : ref
                .watch(priorityExplanationProvider(
                    (groupId: groupId, companyId: closestRanked.company.id)))
                .valueOrNull;

        return PriorityExplanationView(
          company: company,
          explanation: e,
          mine: priorities[company.id] ?? _infoFrom(e),
          nearer: nearer,
          closestExplanation: other,
        );
      },
    );
  }

  /// Quando a lista compacta não trouxe o lead, deduz a faixa da explicação.
  LeadPriorityInfo _infoFrom(PriorityExplanation e) {
    final nota = e.nota;
    final tier = nota != null
        ? tierForNota(nota)
        : (e.totalLeads == 0
            ? LeadTier.cold
            : const [
                LeadTier.hot,
                LeadTier.warm,
                LeadTier.cold
              ][((e.posicao - 1) * 3 ~/ e.totalLeads).clamp(0, 2)]);
    return LeadPriorityInfo(posicao: e.posicao, nota: nota, tier: tier);
  }
}

/// Parte visual (sem providers), pra testar com dados prontos.
class PriorityExplanationView extends StatefulWidget {
  const PriorityExplanationView({
    super.key,
    required this.company,
    required this.explanation,
    required this.mine,
    this.nearer = const [],
    this.closestExplanation,
    this.initiallyExpanded = false,
  });

  /// Recolhida por padrão: os detalhes servem pra agir rápido; quem quiser
  /// entender a nota abre.
  final bool initiallyExpanded;

  final Company company;
  final PriorityExplanation explanation;
  final LeadPriorityInfo mine;
  final List<NearbyLead> nearer;
  final PriorityExplanation? closestExplanation;

  @override
  State<PriorityExplanationView> createState() =>
      _PriorityExplanationViewState();
}

class _PriorityExplanationViewState extends State<PriorityExplanationView> {
  static const _collapsed = 4;
  bool _showAll = false;
  late bool _expanded = widget.initiallyExpanded;

  PriorityExplanation get e => widget.explanation;

  @override
  Widget build(BuildContext context) {
    if (!_expanded) return _buildCompact();
    final verdict = tripVerdict(
      company: widget.company,
      mine: widget.mine,
      nearer: widget.nearer,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildHeadline(),
        if (e.estrategia == PriorityStrategy.perfil && e.fatores.isNotEmpty)
          _buildFactors(),
        if (e.estrategia == PriorityStrategy.interacao) _buildSignals(),
        if (widget.nearer.isNotEmpty) _buildTrip(verdict),
        const Padding(
          padding: EdgeInsets.fromLTRB(4, 2, 4, 12),
          child: Text(
            'A nota (0 a 100) mostra o quanto a empresa se parece com os seus '
            'clientes, em comparação com os outros leads. Não é a '
            'probabilidade de fechar negócio.',
            style: TextStyle(fontSize: 11, color: _muted, height: 1.3),
          ),
        ),
      ],
    );
  }

  // ─── Recolhida ─────────────────────────────────────────────────────

  Widget _buildCompact() {
    final tier = widget.mine.tier;
    final nota = e.nota;
    final verdict = tripVerdict(
      company: widget.company,
      mine: widget.mine,
      nearer: widget.nearer,
    );
    return GestureDetector(
      key: const ValueKey('priority-compact'),
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _expanded = true),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(
          color: tier.color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: tier.color.withValues(alpha: 0.35)),
        ),
        child: Row(
          children: [
            _TierPill(tier),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    nota != null
                        ? 'Nota $nota · ${e.posicao}º de ${e.totalLeads} leads'
                        : '${e.posicao}º de ${e.totalLeads} leads',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w700, color: _ink),
                  ),
                  if (verdict != null)
                    Text(
                      switch (verdict.kind) {
                        TripVerdictKind.vale => 'Vale ir mais longe por ela',
                        TripVerdictKind.melhorPerto =>
                          'Há lead melhor mais perto',
                        TripVerdictKind.equivalente =>
                          'Parecida com os leads mais perto',
                      },
                      style: const TextStyle(fontSize: 12, color: _muted),
                    ),
                ],
              ),
            ),
            const Text('Por quê?',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: CupertinoColors.activeBlue)),
            const Icon(CupertinoIcons.chevron_down,
                size: 14, color: CupertinoColors.activeBlue),
          ],
        ),
      ),
    );
  }

  // ─── Nota e resumo ─────────────────────────────────────────────────

  Widget _buildHeadline() {
    final tier = widget.mine.tier;
    final nota = e.nota;
    return _Shell(
      title: 'Por que esta prioridade',
      icon: CupertinoIcons.lightbulb_fill,
      trailing: CupertinoButton(
        padding: EdgeInsets.zero,
        minimumSize: Size.zero,
        onPressed: () => setState(() => _expanded = false),
        child: const Text('Recolher', style: TextStyle(fontSize: 13)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 68,
                height: 68,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: tier.color.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                  border: Border.all(color: tier.color, width: 3),
                ),
                child: nota != null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('$nota',
                              key: const ValueKey('priority-nota'),
                              style: const TextStyle(
                                  fontSize: 24,
                                  height: 1,
                                  fontWeight: FontWeight.w800,
                                  color: _ink)),
                          const Text('de 100',
                              style: TextStyle(fontSize: 9, color: _muted)),
                        ],
                      )
                    : Text('#${e.posicao}',
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: _ink)),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _TierPill(tier),
                    const SizedBox(height: 6),
                    Text(
                      'Posição ${e.posicao} de ${e.totalLeads} leads',
                      key: const ValueKey('priority-position'),
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: _ink),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      nota != null
                          ? 'Mais parecida com seus clientes que $nota% dos '
                              'outros leads.'
                          : 'Ordenada pelo histórico de interação no CRM.',
                      style: const TextStyle(
                          fontSize: 12, color: _muted, height: 1.25),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (nota != null) ...[
            const SizedBox(height: 14),
            _ScoreBar(nota: nota),
          ],
          const SizedBox(height: 12),
          Text(explanationSummary(e),
              key: const ValueKey('priority-summary'),
              style: const TextStyle(fontSize: 14, color: _ink, height: 1.35)),
          if (!e.confiavel) ...[
            const SizedBox(height: 10),
            _Note(
              icon: CupertinoIcons.exclamationmark_triangle_fill,
              color: CupertinoColors.systemOrange,
              text: 'Você tem poucos clientes (${e.nClientes}); a nota ainda '
                  'é pouco precisa e melhora conforme a carteira cresce.',
            ),
          ],
        ],
      ),
    );
  }

  // ─── Fatores ───────────────────────────────────────────────────────

  Widget _buildFactors() {
    final sorted = [...e.fatores]
      ..sort((a, b) => b.contribuicao.abs().compareTo(a.contribuicao.abs()));
    final shown = _showAll ? sorted : sorted.take(_collapsed).toList();
    return _Shell(
      title: 'O que pesa na nota',
      icon: CupertinoIcons.slider_horizontal_3,
      subtitle: 'Cada característica da empresa é comparada com a dos seus '
          '${e.nClientes} clientes e com a base inteira.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < shown.length; i++) ...[
            if (i > 0) const _Hairline(),
            _FactorRow(factor: shown[i], nClientes: e.nClientes),
          ],
          if (sorted.length > _collapsed)
            CupertinoButton(
              padding: const EdgeInsets.only(top: 8),
              minimumSize: Size.zero,
              onPressed: () => setState(() => _showAll = !_showAll),
              child: Text(
                _showAll
                    ? 'Mostrar menos'
                    : 'Ver os outros ${sorted.length - _collapsed} fatores',
                style: const TextStyle(fontSize: 13),
              ),
            ),
          if (e.semDado.isNotEmpty) ...[
            const SizedBox(height: 10),
            _Note(
              icon: CupertinoIcons.info_circle_fill,
              color: _muted,
              text: 'Sem dados de ${e.semDado.join(', ')}: não pesam na nota '
                  '(nem a favor, nem contra).',
            ),
          ],
        ],
      ),
    );
  }

  // ─── Sinais do CRM (estratégia por interação) ──────────────────────

  Widget _buildSignals() {
    return _Shell(
      title: 'Como a ordem foi definida',
      icon: CupertinoIcons.chat_bubble_2_fill,
      subtitle: 'Com menos clientes do que o necessário pra aprender o perfil '
          'deles, a ordem vem do quanto a empresa já foi trabalhada no CRM.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SignalLine('Interações no CRM',
              e.numInteracoes == null ? 'sem registro' : '${e.numInteracoes}'),
          _SignalLine(
              'Última atividade',
              e.ultimaInteracao == null
                  ? 'sem registro'
                  : formatDateBr(e.ultimaInteracao!)),
          _SignalLine('Cadastrada no CRM em',
              e.criadoEm == null ? 'sem registro' : formatDateBr(e.criadoEm!)),
          const SizedBox(height: 6),
          _Note(
            icon: CupertinoIcons.info_circle_fill,
            color: _muted,
            text:
                'Ao chegar a ${e.nClientes < 10 ? 10 : e.nClientes} clientes, '
                'a nota passa a comparar o perfil da empresa com o dos seus '
                'clientes.',
          ),
        ],
      ),
    );
  }

  // ─── Vale a viagem? ────────────────────────────────────────────────

  Widget _buildTrip(TripVerdict? verdict) {
    final diffs = widget.closestExplanation == null
        ? const <FactorDiff>[]
        : compareFactors(e, widget.closestExplanation!);
    final closest = widget.nearer.where((n) => n.info != null).isEmpty
        ? null
        : widget.nearer.firstWhere((n) => n.info != null);

    return _Shell(
      title: 'Vale a viagem?',
      icon: CupertinoIcons.location_north_fill,
      subtitle: 'Comparação com os leads que estão mais perto de você.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (verdict != null) _VerdictBanner(verdict),
          if (verdict != null) const SizedBox(height: 12),
          for (final n in widget.nearer) _NearbyRow(n),
          if (diffs.isNotEmpty && closest != null) ...[
            const SizedBox(height: 12),
            Text('O que muda em relação a ${closest.company.displayName}',
                style: const TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w700, color: _ink)),
            const SizedBox(height: 6),
            for (final d in diffs) _DiffRow(d),
          ],
        ],
      ),
    );
  }
}

// ─── Peças ───────────────────────────────────────────────────────────

class _Shell extends StatelessWidget {
  const _Shell(
      {required this.child,
      this.title,
      this.icon,
      this.subtitle,
      this.trailing});

  final Widget child;
  final String? title;
  final IconData? icon;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: CupertinoColors.systemGroupedBackground,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: CupertinoColors.systemGrey5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Row(children: [
                if (icon != null)
                  Icon(icon, size: 15, color: CupertinoColors.activeBlue),
                if (icon != null) const SizedBox(width: 6),
                Expanded(
                  child: Text(title!,
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: _ink)),
                ),
                if (trailing != null) trailing!,
              ]),
              if (subtitle != null) ...[
                const SizedBox(height: 3),
                Text(subtitle!,
                    style: const TextStyle(
                        fontSize: 12, color: _muted, height: 1.3)),
              ],
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      );
}

class _Hairline extends StatelessWidget {
  const _Hairline();
  @override
  Widget build(BuildContext context) => Container(
        height: 0.5,
        margin: const EdgeInsets.symmetric(vertical: 10),
        color: CupertinoColors.systemGrey4,
      );
}

class _TierPill extends StatelessWidget {
  const _TierPill(this.tier);
  final LeadTier tier;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: tier.color,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(tier.label,
            key: const ValueKey('priority-tier'),
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: CupertinoColors.white)),
      );
}

/// Barra 0–100 dividida nas três faixas, com um marcador na nota.
class _ScoreBar extends StatelessWidget {
  const _ScoreBar({required this.nota});
  final int nota;

  @override
  Widget build(BuildContext context) {
    Widget seg(LeadTier t, int flex) => Expanded(
          flex: flex,
          child: Container(height: 8, color: t.color.withValues(alpha: 0.85)),
        );
    return LayoutBuilder(builder: (context, c) {
      final x = (c.maxWidth * nota / 100).clamp(0.0, c.maxWidth);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 18,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 5,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Row(children: [
                      seg(LeadTier.cold, warmMinNota),
                      const SizedBox(width: 2),
                      seg(LeadTier.warm, hotMinNota - warmMinNota),
                      const SizedBox(width: 2),
                      seg(LeadTier.hot, 100 - hotMinNota),
                    ]),
                  ),
                ),
                Positioned(
                  left: x - 7,
                  top: 0,
                  child: Container(
                    width: 14,
                    height: 18,
                    decoration: BoxDecoration(
                      color: CupertinoColors.white,
                      borderRadius: BorderRadius.circular(7),
                      border: Border.all(color: _ink, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Frio', style: TextStyle(fontSize: 10, color: _muted)),
              Text('Morno', style: TextStyle(fontSize: 10, color: _muted)),
              Text('Quente', style: TextStyle(fontSize: 10, color: _muted)),
            ],
          ),
        ],
      );
    });
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.icon, required this.color, required this.text});
  final IconData icon;
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 14, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                style:
                    const TextStyle(fontSize: 12, color: _muted, height: 1.3)),
          ),
        ],
      );
}

String _pct(double v) {
  final p = v * 100;
  if (p > 0 && p < 1) return '<1%';
  return '${p.round()}%';
}

class _FactorRow extends StatelessWidget {
  const _FactorRow({required this.factor, required this.nClientes});
  final PriorityFactor factor;
  final int nClientes;

  @override
  Widget build(BuildContext context) {
    final f = factor;
    final (icon, color, _) = switch (f.efeito) {
      PriorityEffect.favorece => (
          CupertinoIcons.arrow_up_circle_fill,
          _good,
          'a favor'
        ),
      PriorityEffect.desfavorece => (
          CupertinoIcons.arrow_down_circle_fill,
          _bad,
          'contra'
        ),
      PriorityEffect.neutro => (
          CupertinoIcons.minus_circle_fill,
          _muted,
          'neutro'
        ),
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(f.campo,
                      style: const TextStyle(fontSize: 11, color: _muted)),
                  Text(f.valor,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: _ink)),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                factorBadge(f),
                style: TextStyle(
                    fontSize: 11, fontWeight: FontWeight.w700, color: color),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _ShareBar(
          label: 'Seus clientes',
          share: f.pctClientes,
          color: _good,
          trailing: '${_pct(f.pctClientes)} · ${f.clientesComValor} de '
              '$nClientes',
        ),
        const SizedBox(height: 4),
        _ShareBar(
          label: 'Base inteira',
          share: f.pctBase,
          color: _muted,
          trailing: _pct(f.pctBase),
        ),
      ],
    );
  }
}

/// Texto do selo de um fator: "a favor · 2,9× mais comum", "contra · nenhum
/// cliente assim", "neutro".
String factorBadge(PriorityFactor f) {
  final vezes = f.vezes;
  switch (f.efeito) {
    case PriorityEffect.neutro:
      return 'neutro';
    case PriorityEffect.favorece:
      return vezes == null
          ? 'a favor'
          : 'a favor · ${formatMultiplier(vezes)}× mais comum';
    case PriorityEffect.desfavorece:
      if (f.pctClientes == 0) return 'contra · nenhum cliente assim';
      return vezes == null || vezes <= 0
          ? 'contra'
          : 'contra · ${formatMultiplier(1 / vezes)}× mais raro';
  }
}

class _ShareBar extends StatelessWidget {
  const _ShareBar({
    required this.label,
    required this.share,
    required this.color,
    required this.trailing,
  });
  final String label;
  final double share;
  final Color color;
  final String trailing;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          SizedBox(
            width: 82,
            child: Text(label,
                style: const TextStyle(fontSize: 11, color: _muted)),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 6,
                child: Stack(children: [
                  const Positioned.fill(
                      child: ColoredBox(color: CupertinoColors.systemGrey5)),
                  FractionallySizedBox(
                    widthFactor: share.clamp(0.02, 1.0),
                    child: ColoredBox(color: color),
                  ),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 92,
            child: Text(trailing,
                textAlign: TextAlign.right,
                style: const TextStyle(fontSize: 11, color: _ink)),
          ),
        ],
      );
}

class _SignalLine extends StatelessWidget {
  const _SignalLine(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Expanded(
              child: Text(label,
                  style: const TextStyle(fontSize: 13, color: _muted))),
          Text(value,
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: _ink)),
        ]),
      );
}

class _VerdictBanner extends StatelessWidget {
  const _VerdictBanner(this.verdict);
  final TripVerdict verdict;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (verdict.kind) {
      TripVerdictKind.vale => (CupertinoIcons.checkmark_seal_fill, _good),
      TripVerdictKind.melhorPerto => (
          CupertinoIcons.arrow_turn_up_left,
          CupertinoColors.systemOrange
        ),
      TripVerdictKind.equivalente => (CupertinoIcons.equal_circle_fill, _muted),
    };
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(verdict.text,
                key: const ValueKey('trip-verdict'),
                style:
                    const TextStyle(fontSize: 13, color: _ink, height: 1.35)),
          ),
        ],
      ),
    );
  }
}

class _NearbyRow extends StatelessWidget {
  const _NearbyRow(this.nearby);
  final NearbyLead nearby;

  @override
  Widget build(BuildContext context) {
    final info = nearby.info;
    final tier = info?.tier ?? LeadTier.cold;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: tier.color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(nearby.company.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, color: _ink)),
        ),
        const SizedBox(width: 8),
        Text(formatDistanceBr(nearby.distanceKm * 1000),
            style: const TextStyle(fontSize: 12, color: _muted)),
        const SizedBox(width: 10),
        SizedBox(
          width: 64,
          child: Text(
            info == null
                ? 'sem nota'
                : info.nota != null
                    ? 'nota ${info.nota}'
                    : '#${info.posicao}',
            textAlign: TextAlign.right,
            style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: info == null ? _muted : tier.color),
          ),
        ),
      ]),
    );
  }
}

class _DiffRow extends StatelessWidget {
  const _DiffRow(this.diff);
  final FactorDiff diff;

  @override
  Widget build(BuildContext context) {
    final color = diff.mineIsBetter ? _good : _bad;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(diff.campo, style: const TextStyle(fontSize: 11, color: _muted)),
          const SizedBox(height: 2),
          Text.rich(
            TextSpan(children: [
              TextSpan(
                text: '${diff.mine.valor} (${_pct(diff.mine.pctClientes)} dos '
                    'clientes)',
                style: TextStyle(fontWeight: FontWeight.w700, color: color),
              ),
              const TextSpan(text: '  ×  '),
              TextSpan(
                text: '${diff.other.valor} (${_pct(diff.other.pctClientes)})',
              ),
            ]),
            style: const TextStyle(fontSize: 13, color: _ink, height: 1.3),
          ),
        ],
      ),
    );
  }
}
