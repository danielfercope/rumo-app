import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/format/br_format.dart';
import '../models/enrichment_models.dart';
import '../providers/enrichment_provider.dart';

const _ink = CupertinoColors.black;
const _muted = CupertinoColors.systemGrey;
const _good = Color(0xFF1E9E54);
const _bad = Color(0xFFD64545);
const _accent = CupertinoColors.activeBlue;

Future<void> _open(String url) async {
  final uri = Uri.tryParse(url);
  if (uri != null) await launchUrl(uri, mode: LaunchMode.externalApplication);
}

String _count(num v) => formatCompactBr(v, prefix: '').trim();

/// Os blocos de dados públicos dos detalhes, na ordem: Google, Receita,
/// vendas ao governo e economia do município. Cada um carrega sozinho.
class CompanyEnrichmentCards extends StatelessWidget {
  const CompanyEnrichmentCards(
      {super.key, required this.groupId, required this.cnpj});

  final String groupId;
  final String cnpj;

  EnrichmentKey _k(EnrichmentSource s) =>
      (groupId: groupId, cnpj: cnpj, fonte: s);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GoogleCard(sourceKey: _k(EnrichmentSource.google)),
        ReceitaCard(sourceKey: _k(EnrichmentSource.receita)),
        ComprasCard(sourceKey: _k(EnrichmentSource.compras)),
        EconomiaCard(
          municipioKey: _k(EnrichmentSource.municipio),
          comexKey: _k(EnrichmentSource.comex),
        ),
      ],
    );
  }
}

// ─── Peças de layout ─────────────────────────────────────────────────

/// Bloco com resumo sempre visível e detalhes que abrem ao tocar.
class DetailCard extends StatefulWidget {
  const DetailCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.summary,
    this.details,
    this.footer,
    this.stale = false,
    this.initiallyExpanded = false,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget summary;
  final Widget? details;
  final String? footer;
  final bool stale;
  final bool initiallyExpanded;

  @override
  State<DetailCard> createState() => _DetailCardState();
}

class _DetailCardState extends State<DetailCard> {
  late bool _expanded = widget.initiallyExpanded;

  @override
  Widget build(BuildContext context) {
    final canExpand = widget.details != null;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: CupertinoColors.systemGroupedBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: CupertinoColors.systemGrey5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap:
                canExpand ? () => setState(() => _expanded = !_expanded) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 26,
                      height: 26,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: widget.iconColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child:
                          Icon(widget.icon, size: 15, color: widget.iconColor),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(widget.title,
                          style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                              color: _ink)),
                    ),
                    if (widget.stale)
                      const Padding(
                        padding: EdgeInsets.only(right: 6),
                        child: Text('desatualizado',
                            style: TextStyle(
                                fontSize: 10,
                                color: CupertinoColors.systemOrange)),
                      ),
                    if (canExpand)
                      Icon(
                        _expanded
                            ? CupertinoIcons.chevron_up
                            : CupertinoIcons.chevron_down,
                        size: 14,
                        color: _muted,
                      ),
                  ]),
                  const SizedBox(height: 10),
                  widget.summary,
                ],
              ),
            ),
          ),
          if (_expanded && canExpand) ...[
            Container(height: 0.5, color: CupertinoColors.systemGrey4),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: widget.details!,
            ),
          ],
          if (widget.footer != null && (_expanded || !canExpand))
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
              child: Text(widget.footer!,
                  style: const TextStyle(fontSize: 10, color: _muted)),
            ),
        ],
      ),
    );
  }
}

class Pill extends StatelessWidget {
  const Pill(this.text, {super.key, this.color = _muted, this.icon});
  final String text;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
          ],
          Text(text,
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: color)),
        ]),
      );
}

/// Número grande + legenda (resumo dos blocos).
class Stat extends StatelessWidget {
  const Stat(this.value, this.label, {super.key});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value,
              style: const TextStyle(
                  fontSize: 17, fontWeight: FontWeight.w800, color: _ink)),
          Text(label, style: const TextStyle(fontSize: 11, color: _muted)),
        ],
      );
}

class _Kv extends StatelessWidget {
  const _Kv(this.label, this.value);
  final String label;
  final String? value;

  @override
  Widget build(BuildContext context) {
    if (value == null || value!.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(label,
                style: const TextStyle(fontSize: 12, color: _muted)),
          ),
          Expanded(
            child: Text(value!,
                style: const TextStyle(fontSize: 13, color: _ink, height: 1.3)),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 8),
        child: Text(text.toUpperCase(),
            style: const TextStyle(
                fontSize: 11,
                letterSpacing: 0.4,
                fontWeight: FontWeight.w700,
                color: _muted)),
      );
}

class _LinkButton extends StatelessWidget {
  const _LinkButton(this.label, this.icon, this.url);
  final String label;
  final IconData icon;
  final String url;

  @override
  Widget build(BuildContext context) => CupertinoButton(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        minimumSize: Size.zero,
        color: _accent.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
        onPressed: () => _open(url),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: _accent),
          const SizedBox(width: 4),
          Text(label,
              style: const TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w600, color: _accent)),
        ]),
      );
}

/// Barra horizontal de participação (produtos, países).
class _ShareRow extends StatelessWidget {
  const _ShareRow(this.label, this.share, this.trailing,
      {this.color = _accent});
  final String label;
  final double share;
  final String trailing;
  final Color color;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: _ink)),
              ),
              const SizedBox(width: 8),
              Text(trailing,
                  style: const TextStyle(fontSize: 11, color: _muted)),
            ]),
            const SizedBox(height: 3),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 5,
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
          ],
        ),
      );
}

String _footer(EnrichmentResult r, [String? extra]) {
  final when = r.atualizadoEm == null
      ? null
      : 'consultado em ${formatDateBr(r.atualizadoEm!)}';
  return [
    if (r.origem != null) 'Fonte: ${r.origem}',
    if (when != null) when,
    if (extra != null) extra,
  ].join(' · ');
}

/// Estados comuns (carregando, fora do ar) de um bloco de uma fonte.
class _SourceState extends ConsumerWidget {
  const _SourceState({
    required this.sourceKey,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.builder,
    this.emptyText,
  });

  final EnrichmentKey sourceKey;
  final IconData icon;
  final Color iconColor;
  final String title;
  final Widget Function(EnrichmentResult) builder;

  /// Texto quando a fonte não tem dado; nulo = o bloco some.
  final String? emptyText;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(enrichmentProvider(sourceKey));
    Widget line(String text, {Widget? trailing}) => DetailCard(
          icon: icon,
          iconColor: iconColor,
          title: title,
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
      onPressed: () => ref.invalidate(enrichmentProvider(sourceKey)),
      child: const Text('Tentar de novo', style: TextStyle(fontSize: 13)),
    );

    return async.when(
      loading: () => line('Consultando…',
          trailing: const CupertinoActivityIndicator(radius: 8)),
      error: (_, __) =>
          line('Não foi possível consultar agora.', trailing: retry),
      data: (r) => switch (r.status) {
        EnrichmentStatus.ok when r.dados != null => builder(r),
        EnrichmentStatus.desativado => const SizedBox.shrink(),
        EnrichmentStatus.indisponivel =>
          line(r.mensagem ?? 'Fonte indisponível agora.', trailing: retry),
        _ => emptyText == null ? const SizedBox.shrink() : line(emptyText!),
      },
    );
  }
}

// ─── Google ──────────────────────────────────────────────────────────

/// Sob demanda: cada consulta ao Google é cobrada, então só busca quando a
/// pessoa toca em "Ver no Google" (e busca de novo a cada abertura: pelos
/// termos do Google, o conteúdo não pode ficar guardado).
class GoogleCard extends StatefulWidget {
  const GoogleCard({super.key, required this.sourceKey});
  final EnrichmentKey sourceKey;

  @override
  State<GoogleCard> createState() => _GoogleCardState();
}

class _GoogleCardState extends State<GoogleCard> {
  bool _requested = false;

  static const _icon = CupertinoIcons.star_fill;
  static const _color = CupertinoColors.systemOrange;

  @override
  Widget build(BuildContext context) {
    if (!_requested) {
      return DetailCard(
        key: const ValueKey('card-google-pedir'),
        icon: _icon,
        iconColor: _color,
        title: 'No Google',
        summary: Row(
          children: [
            const Expanded(
              child: Text(
                'Foto, nota, avaliações, horário e site da empresa.',
                style: TextStyle(fontSize: 13, color: _muted, height: 1.3),
              ),
            ),
            const SizedBox(width: 10),
            CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              minimumSize: Size.zero,
              color: _accent,
              borderRadius: BorderRadius.circular(16),
              onPressed: () => setState(() => _requested = true),
              child: const Text('Ver no Google',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: CupertinoColors.white)),
            ),
          ],
        ),
      );
    }
    return _SourceState(
      sourceKey: widget.sourceKey,
      icon: _icon,
      iconColor: _color,
      title: 'No Google',
      emptyText: 'Empresa não encontrada no Google.',
      builder: (r) => GoogleView(result: r),
    );
  }
}

class GoogleView extends StatelessWidget {
  const GoogleView({super.key, required this.result});
  final EnrichmentResult result;

  @override
  Widget build(BuildContext context) {
    final g = GooglePlaceData.fromJson(result.dados!);
    final closed = g.situacao != null && g.situacao != 'Em funcionamento';
    return DetailCard(
      key: const ValueKey('card-google'),
      icon: _GoogleCardState._icon,
      iconColor: _GoogleCardState._color,
      title: 'No Google',
      initiallyExpanded: false,
      footer: _footer(result, 'confira se é a mesma empresa'),
      summary: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (g.fotoUrl != null) _CoverPhoto(g),
          if (g.nome != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(g.nome!,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: _ink)),
            ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (g.nota != null)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(CupertinoIcons.star_fill,
                      size: 15, color: CupertinoColors.systemYellow),
                  const SizedBox(width: 3),
                  Text(g.nota!.toStringAsFixed(1).replaceAll('.', ','),
                      style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: _ink)),
                  if (g.avaliacoes != null)
                    Text('  (${formatThousandsBr(g.avaliacoes!)} avaliações)',
                        style: const TextStyle(fontSize: 12, color: _muted)),
                ]),
              if (closed)
                Pill(g.situacao!, color: _bad)
              else if (g.abertoAgora == true)
                const Pill('Aberto agora', color: _good)
              else if (g.abertoAgora == false)
                const Pill('Fechado agora'),
              if (g.tipo != null) Pill(g.tipo!, color: _accent),
            ],
          ),
          if (g.mapsUrl != null || g.site != null || g.telefone != null) ...[
            const SizedBox(height: 10),
            Wrap(spacing: 8, runSpacing: 6, children: [
              if (g.mapsUrl != null)
                _LinkButton('Maps', CupertinoIcons.map_fill, g.mapsUrl!),
              if (g.site != null)
                _LinkButton('Site', CupertinoIcons.globe, g.site!),
              if (g.telefone != null)
                _LinkButton('Ligar', CupertinoIcons.phone_fill,
                    'tel:${g.telefone!.replaceAll(RegExp(r'[^0-9+]'), '')}'),
            ]),
          ],
        ],
      ),
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Kv('Endereço', g.endereco),
          _Kv('Telefone', g.telefone),
          _Kv('Site', g.site),
          if (g.horarios.isNotEmpty) ...[
            const _Heading('Horário de funcionamento'),
            for (final h in g.horarios)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(_cap(h),
                    style: const TextStyle(fontSize: 12, color: _ink)),
              ),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }
}

/// Foto de capa com o crédito do autor (exigido pelo Google). Se a imagem não
/// carregar, some sem deixar buraco.
class _CoverPhoto extends StatelessWidget {
  const _CoverPhoto(this.g);
  final GooglePlaceData g;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: Image.network(
                g.fotoUrl!,
                key: const ValueKey('google-foto'),
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const ColoredBox(
                        color: CupertinoColors.systemGrey5,
                        child: Center(child: CupertinoActivityIndicator()),
                      ),
                errorBuilder: (_, __, ___) => const ColoredBox(
                  color: CupertinoColors.systemGrey5,
                  child: Center(
                    child: Icon(CupertinoIcons.photo,
                        color: CupertinoColors.systemGrey2),
                  ),
                ),
              ),
            ),
          ),
          if (g.fotoAutor != null)
            GestureDetector(
              onTap:
                  g.fotoAutorUrl == null ? null : () => _open(g.fotoAutorUrl!),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('Foto: ${g.fotoAutor} · Google',
                    style: const TextStyle(fontSize: 10, color: _muted)),
              ),
            ),
        ],
      ),
    );
  }
}

String _cap(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

// ─── Receita ─────────────────────────────────────────────────────────

class ReceitaCard extends StatelessWidget {
  const ReceitaCard({super.key, required this.sourceKey});
  final EnrichmentKey sourceKey;

  @override
  Widget build(BuildContext context) {
    return _SourceState(
      sourceKey: sourceKey,
      icon: CupertinoIcons.building_2_fill,
      iconColor: _accent,
      title: 'Receita Federal',
      emptyText: 'CNPJ não encontrado na base da Receita.',
      builder: (r) => ReceitaView(result: r),
    );
  }
}

class ReceitaView extends StatelessWidget {
  const ReceitaView({super.key, required this.result});
  final EnrichmentResult result;

  @override
  Widget build(BuildContext context) {
    final d = ReceitaData.fromJson(result.dados!);
    final idade = d.abertura == null ? null : yearsBetween(d.abertura!);
    final regime = d.regimeAtual;

    return DetailCard(
      key: const ValueKey('card-receita'),
      icon: CupertinoIcons.building_2_fill,
      iconColor: _accent,
      title: 'Receita Federal',
      stale: result.desatualizado,
      footer: _footer(result),
      summary: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(spacing: 6, runSpacing: 6, children: [
            if (d.situacao != null)
              Pill(titleCaseBr(d.situacao!),
                  color: d.ativa ? _good : _bad,
                  icon: d.ativa
                      ? CupertinoIcons.checkmark_seal_fill
                      : CupertinoIcons.xmark_octagon_fill),
            if (idade != null)
              Pill(idade == 0
                  ? 'Aberta há menos de 1 ano'
                  : '$idade ${idade == 1 ? 'ano' : 'anos'}'),
            if (d.porte != null) Pill('Porte: ${titleCaseBr(d.porte!)}'),
            if (regime != null) Pill(regime, color: _accent),
            if (!d.matriz) const Pill('Filial'),
          ]),
          if (d.cnaePrincipal != null) ...[
            const SizedBox(height: 8),
            Text(d.cnaePrincipal!.descricao,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 13, color: _ink, height: 1.3)),
          ],
          if (d.socios.isNotEmpty || d.capitalSocial != null) ...[
            const SizedBox(height: 6),
            Text(
              [
                if (d.capitalSocial != null && d.capitalSocial! > 0)
                  'Capital ${formatCompactBr(d.capitalSocial!)}',
                if (d.socios.isNotEmpty)
                  '${d.socios.length} ${d.socios.length == 1 ? 'sócio/administrador' : 'sócios/administradores'}',
              ].join(' · '),
              style: const TextStyle(fontSize: 12, color: _muted),
            ),
          ],
        ],
      ),
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Kv('Razão social', d.razaoSocial),
          _Kv('Natureza jurídica', d.naturezaJuridica),
          _Kv('Abertura',
              d.abertura == null ? null : formatDateBr(d.abertura!)),
          _Kv(
              'Capital social',
              d.capitalSocial == null || d.capitalSocial == 0
                  ? null
                  : formatMoneyBr(d.capitalSocial!)),
          if (!d.ativa)
            _Kv(
                'Situação',
                [
                  d.situacao,
                  if (d.situacaoDesde != null)
                    'desde ${formatDateBr(d.situacaoDesde!)}',
                  if (d.situacaoMotivo != null &&
                      d.situacaoMotivo!.toUpperCase() != 'SEM MOTIVO')
                    d.situacaoMotivo,
                ].whereType<String>().join(' · ')),
          _Kv('Simples Nacional', _simples(d)),
          _Kv('Tributação', _regimeHistory(d.regimes)),
          if (d.cnaePrincipal != null) ...[
            const _Heading('Atividades (CNAE)'),
            _CnaeLine(d.cnaePrincipal!, principal: true),
            ...d.cnaesSecundarios.take(6).map((c) => _CnaeLine(c)),
            if (d.cnaesSecundarios.length > 6)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                    'e mais ${d.cnaesSecundarios.length - 6} atividades secundárias',
                    style: const TextStyle(fontSize: 12, color: _muted)),
              ),
          ],
          if (d.socios.isNotEmpty) ...[
            const _Heading('Quadro de sócios e administradores'),
            ...d.socios.map(_SocioRow.new),
          ],
        ],
      ),
    );
  }

  static String? _simples(ReceitaData d) {
    if (d.meiOptante == true) return 'Optante pelo MEI';
    if (d.simplesOptante == true) {
      return d.simplesDesde == null
          ? 'Optante'
          : 'Optante desde ${formatDateBr(d.simplesDesde!)}';
    }
    if (d.simplesOptante == false) return 'Não optante';
    return null;
  }

  /// "Lucro Real (2016–2024)" — agrupa anos seguidos com a mesma forma.
  static String? _regimeHistory(List<(int, String)> regimes) {
    if (regimes.isEmpty) return null;
    final asc = [...regimes]..sort((a, b) => a.$1.compareTo(b.$1));
    final groups = <(String, int, int)>[];
    for (final (ano, forma) in asc) {
      if (groups.isNotEmpty &&
          groups.last.$1 == forma &&
          groups.last.$3 == ano - 1) {
        groups[groups.length - 1] = (forma, groups.last.$2, ano);
      } else {
        groups.add((forma, ano, ano));
      }
    }
    return groups.reversed
        .map((g) =>
            '${titleCaseBr(g.$1)} (${g.$2 == g.$3 ? '${g.$2}' : '${g.$2}–${g.$3}'})')
        .join(' · ');
  }
}

class _CnaeLine extends StatelessWidget {
  const _CnaeLine(this.cnae, {this.principal = false});
  final Cnae cnae;
  final bool principal;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 76,
              child: Text(cnae.codigo ?? '',
                  style: TextStyle(
                      fontSize: 11,
                      color: principal ? _accent : _muted,
                      fontWeight:
                          principal ? FontWeight.w700 : FontWeight.normal)),
            ),
            Expanded(
              child: Text(cnae.descricao,
                  style: TextStyle(
                      fontSize: 12,
                      color: _ink,
                      fontWeight:
                          principal ? FontWeight.w600 : FontWeight.normal)),
            ),
          ],
        ),
      );
}

class _SocioRow extends StatelessWidget {
  const _SocioRow(this.socio);
  final Socio socio;

  @override
  Widget build(BuildContext context) {
    final meta = [
      socio.qualificacao,
      if (socio.desde != null) 'desde ${socio.desde!.year}',
      socio.faixaEtaria,
    ].whereType<String>().join(' · ');
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            socio.tipo == 'PJ'
                ? CupertinoIcons.building_2_fill
                : CupertinoIcons.person_crop_circle_fill,
            size: 22,
            color: _accent.withValues(alpha: 0.7),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(titleCaseBr(socio.nome),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _ink)),
                if (meta.isNotEmpty)
                  Text(meta,
                      style: const TextStyle(fontSize: 11, color: _muted)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Vendas ao governo ───────────────────────────────────────────────

class ComprasCard extends StatelessWidget {
  const ComprasCard({super.key, required this.sourceKey});
  final EnrichmentKey sourceKey;

  @override
  Widget build(BuildContext context) {
    return _SourceState(
      sourceKey: sourceKey,
      icon: CupertinoIcons.briefcase_fill,
      iconColor: const Color(0xFF6E56CF),
      title: 'Vendas ao governo',
      builder: (r) => ComprasView(result: r),
    );
  }
}

class ComprasView extends StatelessWidget {
  const ComprasView({super.key, required this.result});
  final EnrichmentResult result;

  static const _color = Color(0xFF6E56CF);

  @override
  Widget build(BuildContext context) {
    final c = ComprasData.fromJson(result.dados!);
    final rec = c.recente;
    final variacao = c.variacao;

    final sicaf = c.sicafHabilitado == true
        ? const Pill('Habilitada no SICAF',
            color: _good, icon: CupertinoIcons.checkmark_seal_fill)
        : c.sicafCadastrado == true
            ? const Pill('Cadastrada no SICAF')
            : c.sicafCadastrado == false
                ? const Pill('Sem cadastro no SICAF')
                : null;

    final Widget summary;
    if (!rec.vendeu) {
      summary = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            c.anterior?.vendeu == true
                ? 'Sem vendas nos últimos 12 meses (vendeu '
                    '${formatCompactBr(c.anterior!.valor)} nos 12 anteriores).'
                : 'Nenhuma venda a órgãos públicos nos últimos 24 meses.',
            style: const TextStyle(fontSize: 13, color: _muted, height: 1.3),
          ),
          if (sicaf != null) ...[const SizedBox(height: 8), sicaf],
        ],
      );
    } else {
      summary = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatCompactBr(rec.valor),
                  key: const ValueKey('compras-total'),
                  style: const TextStyle(
                      fontSize: 22, fontWeight: FontWeight.w800, color: _ink)),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(bottom: 3),
                child: Text('em 12 meses',
                    style: TextStyle(fontSize: 12, color: _muted)),
              ),
              const Spacer(),
              if (variacao != null)
                Pill(
                  '${variacao >= 0 ? '+' : ''}${(variacao * 100).round()}% vs. ano anterior',
                  color: variacao >= 0 ? _good : _bad,
                  icon: variacao >= 0
                      ? CupertinoIcons.arrow_up_right
                      : CupertinoIcons.arrow_down_right,
                ),
            ],
          ),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
                child: Stat('${rec.contratacoes}',
                    rec.contratacoes == 1 ? 'contratação' : 'contratações')),
            Expanded(
                child: Stat(
                    '${rec.orgaos}', rec.orgaos == 1 ? 'órgão' : 'órgãos')),
            Expanded(
                child: Stat('${rec.ufs.length}',
                    rec.ufs.length == 1 ? 'estado' : 'estados')),
          ]),
          if (sicaf != null) ...[const SizedBox(height: 10), sicaf],
        ],
      );
    }

    return DetailCard(
      key: const ValueKey('card-compras'),
      icon: CupertinoIcons.briefcase_fill,
      iconColor: _color,
      title: 'Vendas ao governo',
      stale: result.desatualizado,
      footer: _footer(result, 'licitações da Lei 14.133 publicadas no PNCP'),
      summary: summary,
      details: !rec.vendeu
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (rec.ufs.isNotEmpty)
                  _Kv('Estados atendidos', rec.ufs.join(', ')),
                _Kv('Itens ganhos', '${rec.itens}'),
                if (c.anterior != null)
                  _Kv('12 meses antes',
                      '${formatCompactBr(c.anterior!.valor)} em ${c.anterior!.contratacoes} contratações'),
                if (c.contratacoes.isNotEmpty) ...[
                  const _Heading('Maiores vendas'),
                  ...c.contratacoes.map(_ContratacaoRow.new),
                ],
              ],
            ),
    );
  }
}

class _ContratacaoRow extends StatelessWidget {
  const _ContratacaoRow(this.c);
  final Contratacao c;

  @override
  Widget build(BuildContext context) {
    final local = [c.municipio, c.uf].whereType<String>().join(' - ');
    final meta = [
      c.modalidade,
      if (c.data != null) formatDateBr(c.data!),
      if (c.itens > 1) '${c.itens} itens',
    ].whereType<String>().join(' · ');
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: CupertinoColors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: CupertinoColors.systemGrey5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                    c.orgao == null ? 'Órgão público' : titleCaseBr(c.orgao!),
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: _ink)),
              ),
              const SizedBox(width: 8),
              Text(formatCompactBr(c.valor),
                  style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                      color: ComprasView._color)),
            ],
          ),
          if (local.isNotEmpty)
            Text(local, style: const TextStyle(fontSize: 11, color: _muted)),
          if (c.objeto != null) ...[
            const SizedBox(height: 4),
            Text(c.objeto!,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12, color: _ink, height: 1.3)),
          ],
          const SizedBox(height: 4),
          Row(children: [
            Expanded(
              child: Text(meta,
                  style: const TextStyle(fontSize: 11, color: _muted)),
            ),
            if (c.url != null)
              CupertinoButton(
                padding: EdgeInsets.zero,
                minimumSize: Size.zero,
                onPressed: () => _open(c.url!),
                child:
                    const Text('Ver no PNCP', style: TextStyle(fontSize: 12)),
              ),
          ]),
        ],
      ),
    );
  }
}

// ─── Economia do município ───────────────────────────────────────────

class EconomiaCard extends ConsumerWidget {
  const EconomiaCard(
      {super.key, required this.municipioKey, required this.comexKey});
  final EnrichmentKey municipioKey;
  final EnrichmentKey comexKey;

  static const _color = Color(0xFF0E9AA7);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mun = ref.watch(enrichmentProvider(municipioKey));
    final cx = ref.watch(enrichmentProvider(comexKey));
    if (mun.isLoading && cx.isLoading) {
      return const DetailCard(
        icon: CupertinoIcons.chart_bar_alt_fill,
        iconColor: _color,
        title: 'Economia da cidade',
        summary: Row(children: [
          Expanded(
              child: Text('Consultando…',
                  style: TextStyle(fontSize: 13, color: _muted))),
          CupertinoActivityIndicator(radius: 8),
        ]),
      );
    }
    final m = mun.valueOrNull;
    final c = cx.valueOrNull;
    final mData = m?.hasData == true ? MunicipioData.fromJson(m!.dados!) : null;
    final cData = c?.hasData == true ? ComexData.fromJson(c!.dados!) : null;
    if (mData == null && cData == null) return const SizedBox.shrink();
    return EconomiaView(
      municipio: mData,
      comex: cData,
      stale: (m?.desatualizado ?? false) || (c?.desatualizado ?? false),
    );
  }
}

class EconomiaView extends StatelessWidget {
  const EconomiaView(
      {super.key, this.municipio, this.comex, this.stale = false});
  final MunicipioData? municipio;
  final ComexData? comex;
  final bool stale;

  @override
  Widget build(BuildContext context) {
    final m = municipio;
    final c = comex;
    final cidade = m?.municipio ?? c?.municipio;
    final exp = c?.exportacao;
    final imp = c?.importacao;

    return DetailCard(
      key: const ValueKey('card-economia'),
      icon: CupertinoIcons.chart_bar_alt_fill,
      iconColor: EconomiaCard._color,
      title: cidade == null ? 'Economia da cidade' : 'Economia de $cidade',
      stale: stale,
      footer: 'Dados do município, não da empresa · Fontes: IBGE e Comex '
          'Stat (MDIC). A Receita não publica comércio exterior por empresa.',
      summary: Row(children: [
        if (m?.populacao != null)
          Expanded(child: Stat(_count(m!.populacao!), 'habitantes')),
        if (m?.pibPerCapita != null)
          Expanded(
              child: Stat(formatCompactBr(m!.pibPerCapita!), 'PIB per capita')),
        if (exp != null && exp.totalUsd > 0)
          Expanded(
              child: Stat(formatCompactBr(exp.totalUsd, prefix: 'US\$'),
                  'exportados em ${c!.ano}')),
      ]),
      details: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (m?.pib != null)
            _Kv('PIB (${m!.pibAno})', formatCompactBr(m.pib!)),
          if (m?.populacao != null)
            _Kv('População (${m!.populacaoAno})',
                formatThousandsBr(m.populacao!)),
          if (exp != null && exp.totalUsd > 0) ...[
            _Heading('O que a cidade exporta (${c!.ano})'),
            ...exp.produtos.map((p) => _ShareRow(
                _cap(p.nome.toLowerCase()),
                p.participacao,
                '${(p.participacao * 100).round()}% · ${formatCompactBr(p.usd, prefix: 'US\$')}',
                color: EconomiaCard._color)),
            if (exp.paises.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                    'Destinos: ${exp.paises.map((p) => '${p.nome} ${(p.participacao * 100).round()}%').join(', ')}',
                    style: const TextStyle(fontSize: 12, color: _muted)),
              ),
          ],
          if (imp != null && imp.totalUsd > 0) ...[
            _Heading(
                'O que a cidade importa (${c!.ano}) · ${formatCompactBr(imp.totalUsd, prefix: 'US\$')}'),
            ...imp.produtos.map((p) => _ShareRow(
                _cap(p.nome.toLowerCase()),
                p.participacao,
                '${(p.participacao * 100).round()}% · ${formatCompactBr(p.usd, prefix: 'US\$')}',
                color: CupertinoColors.systemIndigo)),
            if (imp.paises.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                    'Origens: ${imp.paises.map((p) => '${p.nome} ${(p.participacao * 100).round()}%').join(', ')}',
                    style: const TextStyle(fontSize: 12, color: _muted)),
              ),
          ],
        ],
      ),
    );
  }
}
