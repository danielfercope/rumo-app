import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';

import '../models/lead_tier.dart';

/// Visual do pino de lead por faixa: quanto mais prioritário, maior e mais
/// quente a cor.
extension LeadTierStyle on LeadTier {
  Color get color => switch (this) {
        LeadTier.hot => const Color(0xFFF2542D),
        LeadTier.warm => const Color(0xFFF5A524),
        LeadTier.cold => const Color(0xFF8E9AAF),
      };

  /// Largura do pino (px lógicos).
  double get pinWidth => switch (this) {
        LeadTier.hot => 38,
        LeadTier.warm => 30,
        LeadTier.cold => 22,
      };

  double get pinHeight => pinWidth * 1.3;

  String get label => switch (this) {
        LeadTier.hot => 'Lead quente',
        LeadTier.warm => 'Lead morno',
        LeadTier.cold => 'Lead frio',
      };
}

const double _stroke = 2;

/// Desenha o pino (gota com contorno branco e miolo branco) na caixa
/// [pinWidth]×[pinHeight], com [_stroke] de folga em volta.
class LeadPinPainter extends CustomPainter {
  const LeadPinPainter(this.tier);

  final LeadTier tier;

  @override
  void paint(Canvas canvas, Size size) {
    final w = tier.pinWidth;
    final h = tier.pinHeight;
    final r = w / 2;
    canvas.translate(_stroke, _stroke);

    // Gota = círculo + triângulo até a ponta, tangente ao círculo.
    final center = Offset(r, r);
    final d = h - r; // centro → ponta
    final alpha = math.acos(r / d);
    final left = center + Offset(-r * math.sin(alpha), r * math.cos(alpha));
    final right = center + Offset(r * math.sin(alpha), r * math.cos(alpha));
    final drop = Path.combine(
      PathOperation.union,
      Path()..addOval(Rect.fromCircle(center: center, radius: r)),
      Path()
        ..moveTo(w / 2, h)
        ..lineTo(left.dx, left.dy)
        ..lineTo(center.dx, center.dy)
        ..lineTo(right.dx, right.dy)
        ..close(),
    );

    canvas.drawShadow(drop, const Color(0xFF000000), 2, true);
    canvas.drawPath(
      drop,
      Paint()
        ..color = const Color(0xFFFFFFFF)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _stroke * 2
        ..strokeJoin = StrokeJoin.round,
    );
    canvas.drawPath(drop, Paint()..color = tier.color);
    canvas.drawCircle(
        center, r * 0.38, Paint()..color = const Color(0xFFFFFFFF));
  }

  @override
  bool shouldRepaint(LeadPinPainter old) => old.tier != tier;
}

/// Tamanho lógico da imagem do pino (inclui a folga do contorno).
Size leadPinSize(LeadTier tier) =>
    Size(tier.pinWidth + _stroke * 2, tier.pinHeight + _stroke * 2);

/// Pino de lead como widget (mapa OpenStreetMap). A ponta fica no centro da
/// base do widget.
class LeadPin extends StatelessWidget {
  const LeadPin(this.tier, {super.key});

  final LeadTier tier;

  @override
  Widget build(BuildContext context) {
    final size = leadPinSize(tier);
    return Align(
      alignment: Alignment.bottomCenter,
      child: CustomPaint(size: size, painter: LeadPinPainter(tier)),
    );
  }
}

/// PNG do pino (Google Maps), em [pixelRatio]x; passe o [leadPinSize] como
/// largura/altura do `BitmapDescriptor.bytes`.
Future<Uint8List> renderLeadPinPng(LeadTier tier,
    {double pixelRatio = 3}) async {
  final size = leadPinSize(tier);
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..scale(pixelRatio);
  LeadPinPainter(tier).paint(canvas, size);
  final image = await recorder.endRecording().toImage(
        (size.width * pixelRatio).ceil(),
        (size.height * pixelRatio).ceil(),
      );
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

/// Legenda compacta dos pinos do mapa.
class MapLegend extends StatelessWidget {
  const MapLegend({super.key});

  @override
  Widget build(BuildContext context) {
    Widget row(Widget icon, String text) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(width: 20, child: Center(child: icon)),
            const SizedBox(width: 6),
            Text(text,
                style: const TextStyle(
                    fontSize: 11, color: CupertinoColors.label)),
          ]),
        );
    Widget dot(LeadTier t, double size) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(color: t.color, shape: BoxShape.circle),
        );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: CupertinoColors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: CupertinoColors.black.withValues(alpha: 0.15),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          row(Image.asset('assets/icon_save.webp', width: 16), 'Cliente'),
          row(dot(LeadTier.hot, 14), 'Lead quente'),
          row(dot(LeadTier.warm, 11), 'Lead morno'),
          row(dot(LeadTier.cold, 8), 'Lead frio'),
        ],
      ),
    );
  }
}
