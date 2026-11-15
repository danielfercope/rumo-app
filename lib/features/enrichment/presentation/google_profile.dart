import 'package:flutter/cupertino.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/format/br_format.dart';
import '../models/enrichment_models.dart';

// Peças do Google no topo dos detalhes, no estilo de um perfil: foto de capa,
// nota e situação. O Google é consultado quando os detalhes abrem (cada
// abertura é uma consulta cobrada; pelos termos, o conteúdo não fica guardado).

const _muted = CupertinoColors.systemGrey;

/// Capa dos detalhes: a foto do Google, ou um fundo neutro enquanto carrega ou
/// quando não há foto. A alça da folha fica por cima.
class GoogleCover extends StatelessWidget {
  const GoogleCover({super.key, this.place, this.loading = false});

  final GooglePlaceData? place;
  final bool loading;

  static const photoHeight = 190.0;
  static const emptyHeight = 96.0;

  @override
  Widget build(BuildContext context) {
    final url = place?.fotoUrl;
    final hasPhoto = url != null;
    return SizedBox(
      height: hasPhoto || loading ? photoHeight : emptyHeight,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasPhoto)
            Hero(
              tag: _heroTag(url),
              child: Image.network(
                url,
                key: const ValueKey('google-foto'),
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : const _Placeholder(loading: true),
                errorBuilder: (_, __, ___) => const _Placeholder(),
              ),
            )
          else
            _Placeholder(loading: loading),
          if (hasPhoto)
            // escurece o topo (alça) e a base (crédito) pra ficarem legíveis
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x55000000),
                    Color(0x00000000),
                    Color(0x00000000),
                    Color(0x66000000),
                  ],
                  stops: [0, 0.25, 0.7, 1],
                ),
              ),
            ),
          if (hasPhoto)
            // tocar na capa abre a foto em tela cheia
            GestureDetector(
              key: const ValueKey('google-foto-abrir'),
              behavior: HitTestBehavior.opaque,
              onTap: () => openGooglePhoto(context, place!),
            ),
          Align(
            alignment: Alignment.topCenter,
            child: Container(
              margin: const EdgeInsets.only(top: 8),
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: hasPhoto
                    ? CupertinoColors.white.withValues(alpha: 0.85)
                    : CupertinoColors.systemGrey3,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          if (hasPhoto && place!.fotoAutor != null)
            Positioned(
              left: 12,
              right: 12,
              bottom: 8,
              child: GestureDetector(
                onTap: place!.fotoAutorUrl == null
                    ? null
                    : () => launchUrl(Uri.parse(place!.fotoAutorUrl!),
                        mode: LaunchMode.externalApplication),
                child: Text(
                  'Foto: ${place!.fotoAutor} · Google',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 10, color: CupertinoColors.white),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

String _heroTag(String url) => 'google-foto:$url';

/// Abre a foto da capa em tela cheia (zoom com pinça ou toque duplo).
Future<void> openGooglePhoto(BuildContext context, GooglePlaceData place) {
  return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder(
    opaque: false,
    barrierColor: CupertinoColors.black,
    transitionDuration: const Duration(milliseconds: 250),
    reverseTransitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (_, __, ___) => _PhotoViewer(place: place),
    transitionsBuilder: (_, animation, __, child) =>
        FadeTransition(opacity: animation, child: child),
  ));
}

class _PhotoViewer extends StatefulWidget {
  const _PhotoViewer({required this.place});
  final GooglePlaceData place;

  @override
  State<_PhotoViewer> createState() => _PhotoViewerState();
}

class _PhotoViewerState extends State<_PhotoViewer> {
  final _zoom = TransformationController();
  double _drag = 0;
  TapDownDetails? _lastTap;

  @override
  void dispose() {
    _zoom.dispose();
    super.dispose();
  }

  bool get _zoomed => _zoom.value.getMaxScaleOnAxis() > 1.01;

  void _toggleZoom(TapDownDetails d) {
    if (_zoomed) {
      _zoom.value = Matrix4.identity();
    } else {
      // amplia mantendo o ponto tocado no lugar
      const s = 2.5;
      final p = d.localPosition;
      _zoom.value = Matrix4.identity()
        ..translateByDouble(-p.dx * (s - 1), -p.dy * (s - 1), 0, 1)
        ..scaleByDouble(s, s, 1, 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    final g = widget.place;
    return CupertinoPageScaffold(
      key: const ValueKey('google-foto-ampliada'),
      backgroundColor: CupertinoColors.black
          .withValues(alpha: (1 - _drag.abs() / 400).clamp(0.3, 1.0)),
      child: Stack(
        children: [
          // arrastar pra baixo/cima (sem zoom) fecha
          GestureDetector(
            onVerticalDragUpdate:
                _zoomed ? null : (d) => setState(() => _drag += d.delta.dy),
            onVerticalDragEnd: _zoomed
                ? null
                : (_) {
                    if (_drag.abs() > 120) {
                      Navigator.of(context).pop();
                    } else {
                      setState(() => _drag = 0);
                    }
                  },
            onDoubleTapDown: (d) => _lastTap = d,
            onDoubleTap: () {
              if (_lastTap != null) setState(() => _toggleZoom(_lastTap!));
            },
            child: Transform.translate(
              offset: Offset(0, _drag),
              child: InteractiveViewer(
                transformationController: _zoom,
                minScale: 1,
                maxScale: 5,
                onInteractionEnd: (_) => setState(() {}),
                child: SizedBox.expand(
                  child: Hero(
                    tag: _heroTag(g.fotoUrl!),
                    child: Image.network(
                      g.fotoUrl!,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) =>
                          progress == null
                              ? child
                              : const Center(
                                  child: CupertinoActivityIndicator(
                                      color: CupertinoColors.white)),
                      errorBuilder: (_, __, ___) => const Center(
                        child: Icon(CupertinoIcons.photo,
                            size: 40, color: CupertinoColors.systemGrey),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: CupertinoButton(
                  key: const ValueKey('google-foto-fechar'),
                  padding: const EdgeInsets.all(8),
                  minimumSize: Size.zero,
                  color: CupertinoColors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(20),
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Icon(CupertinoIcons.xmark,
                      size: 18, color: CupertinoColors.white),
                ),
              ),
            ),
          ),
          if (g.fotoAutor != null)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: GestureDetector(
                    onTap: g.fotoAutorUrl == null
                        ? null
                        : () => launchUrl(Uri.parse(g.fotoAutorUrl!),
                            mode: LaunchMode.externalApplication),
                    child: Text('Foto: ${g.fotoAutor} · Google',
                        style: const TextStyle(
                            fontSize: 12, color: CupertinoColors.white)),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({this.loading = false});
  final bool loading;

  @override
  Widget build(BuildContext context) => ColoredBox(
        color: CupertinoColors.systemGrey6,
        child: Center(
          child: loading
              ? const CupertinoActivityIndicator()
              : const Icon(CupertinoIcons.building_2_fill,
                  size: 34, color: CupertinoColors.systemGrey3),
        ),
      );
}

/// "★ 4,7 (405) · Aberto agora · Fabricante" logo abaixo do nome.
class GoogleRatingLine extends StatelessWidget {
  const GoogleRatingLine(this.place, {super.key});
  final GooglePlaceData place;

  @override
  Widget build(BuildContext context) {
    final g = place;
    final closedForGood = g.situacao != null && g.situacao != 'Em funcionamento';
    final status = closedForGood
        ? (g.situacao!, CupertinoColors.systemRed)
        : g.abertoAgora == true
            ? ('Aberto agora', const Color(0xFF1E9E54))
            : g.abertoAgora == false
                ? ('Fechado agora', CupertinoColors.systemRed)
                : null;
    final parts = <InlineSpan>[
      if (g.nota != null) ...[
        const WidgetSpan(
          alignment: PlaceholderAlignment.middle,
          child: Icon(CupertinoIcons.star_fill,
              size: 13, color: CupertinoColors.systemYellow),
        ),
        TextSpan(
          text: ' ${g.nota!.toStringAsFixed(1).replaceAll('.', ',')}',
          style: const TextStyle(
              fontWeight: FontWeight.w700, color: CupertinoColors.black),
        ),
        if (g.avaliacoes != null)
          TextSpan(text: ' (${formatThousandsBr(g.avaliacoes!)})'),
      ],
      if (status != null) ...[
        if (g.nota != null) const TextSpan(text: '  ·  '),
        TextSpan(
          text: status.$1,
          style: TextStyle(fontWeight: FontWeight.w600, color: status.$2),
        ),
      ],
      if (g.tipo != null) ...[
        if (g.nota != null || status != null) const TextSpan(text: '  ·  '),
        TextSpan(text: g.tipo),
      ],
    ];
    if (parts.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text.rich(
        TextSpan(
            children: parts,
            style: const TextStyle(fontSize: 13, color: _muted)),
        key: const ValueKey('google-nota'),
      ),
    );
  }
}

/// Endereço do site sem protocolo e sem barra final, pra caber numa linha.
String displaySite(String url) => url
    .replaceFirst(RegExp(r'^https?://', caseSensitive: false), '')
    .replaceFirst(RegExp(r'^www\.', caseSensitive: false), '')
    .replaceFirst(RegExp(r'/$'), '');

/// Horário de hoje (o Google lista de segunda a domingo).
String? todayHours(List<String> horarios, [DateTime? now]) {
  if (horarios.length != 7) return null;
  final day = (now ?? DateTime.now()).weekday; // 1 = segunda
  final line = horarios[day - 1];
  final i = line.indexOf(':');
  return i < 0 ? line : 'Hoje: ${line.substring(i + 1).trim()}';
}
