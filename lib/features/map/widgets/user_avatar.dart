import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';

/// "Daniel Pereira" -> "DP"; um nome só -> "D"; vazio -> "?".
String userInitials(String name) {
  final parts = name.trim().split(RegExp(r'\s+'))
    ..removeWhere((p) => p.isEmpty);
  if (parts.isEmpty) return '?';
  final first = parts.first[0];
  final last = parts.length > 1 ? parts.last[0] : '';
  return (first + last).toUpperCase();
}

/// Avatar redondo com borda branca: a foto, ou as iniciais sobre fundo azul.
class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.initials,
    this.photo,
    this.size = 40,
    this.borderWidth = 3,
  });

  final String initials;

  /// Bytes da foto (ver `userPhotoProvider`); sem eles, as iniciais.
  final Uint8List? photo;
  final double size;
  final double borderWidth;

  @override
  Widget build(BuildContext context) {
    final fallback = Center(
      child: Text(
        initials,
        style: TextStyle(
          color: CupertinoColors.white,
          fontSize: size * 0.4,
          fontWeight: FontWeight.w600,
          decoration: TextDecoration.none,
        ),
      ),
    );
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: CupertinoColors.activeBlue,
        shape: BoxShape.circle,
        border: Border.all(color: CupertinoColors.white, width: borderWidth),
      ),
      // Recorte próprio: o do Container seguiria o círculo externo e deixaria
      // os cantos da imagem aparecendo por cima da borda.
      child: ClipOval(
        child: SizedBox.expand(
          child: photo == null || photo!.isEmpty
              ? fallback
              : Image.memory(
                  photo!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => fallback,
                ),
        ),
      ),
    );
  }
}

/// Desenha o mesmo avatar como PNG, pro marcador do Google Maps (que só
/// aceita bitmap). Sem [photo] (ou se ela não decodificar), usa as iniciais.
Future<Uint8List> renderUserAvatarPng({
  required String initials,
  Uint8List? photo,
  int size = 120,
}) async {
  final s = size.toDouble();
  final center = Offset(s / 2, s / 2);
  final border = s * 0.07;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);

  canvas.drawCircle(center, s / 2, Paint()..color = const Color(0xFFFFFFFF));
  final inner = Rect.fromCircle(center: center, radius: s / 2 - border);

  ui.Image? image;
  if (photo != null) {
    try {
      final codec = await ui.instantiateImageCodec(photo,
          targetWidth: inner.width.round(), targetHeight: inner.height.round());
      image = (await codec.getNextFrame()).image;
    } catch (_) {
      image = null;
    }
  }

  canvas.save();
  canvas.clipPath(Path()..addOval(inner));
  if (image != null) {
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      inner,
      Paint()..filterQuality = FilterQuality.high,
    );
  } else {
    canvas.drawRect(inner, Paint()..color = CupertinoColors.activeBlue);
    final text = TextPainter(
      text: TextSpan(
        text: initials,
        style: TextStyle(
          color: const Color(0xFFFFFFFF),
          fontSize: s * 0.4,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, center - Offset(text.width / 2, text.height / 2));
  }
  canvas.restore();

  final picture = recorder.endRecording();
  final img = await picture.toImage(size, size);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!
      .buffer
      .asUint8List();
}
