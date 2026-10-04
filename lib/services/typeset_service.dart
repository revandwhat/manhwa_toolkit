import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// One text layer on the panel. x/y/w/h are fractions of the image (0..1).
class BoxItem {
  BoxItem({
    required this.translated,
    this.x = 0.3,
    this.y = 0.3,
    this.w = 0.4,
    this.h = 0.12,
    this.size = 0.4,
  });

  String translated;
  double x, y, w, h;
  double size; // font size as a fraction of box height
}

class TypesetService {
  /// Bakes the boxes into a finished PNG at native resolution.
  static Future<Uint8List> render(
      Uint8List imageBytes, List<BoxItem> items) async {
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;

    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    canvas.drawImage(img, ui.Offset.zero, ui.Paint());

    for (final it in items) {
      final rect = ui.Rect.fromLTWH(
        it.x * img.width,
        it.y * img.height,
        it.w * img.width,
        it.h * img.height,
      );
      canvas.drawRRect(
        ui.RRect.fromRectAndRadius(
            rect.inflate(2), const ui.Radius.circular(6)),
        ui.Paint()..color = Colors.white,
      );
      final fs =
          (rect.height * it.size).clamp(6.0, 300.0).toDouble();
      final tp = TextPainter(
        text: TextSpan(
          text: it.translated,
          style: TextStyle(
              color: Colors.black, fontSize: fs, height: 1.15),
        ),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: (rect.width - 8).clamp(10.0, 10000.0));
      tp.paint(
        canvas,
        ui.Offset(
          rect.left + 4,
          rect.top + (rect.height - tp.height) / 2,
        ),
      );
    }

    final pic = rec.endRecording();
    final out = await pic.toImage(img.width, img.height);
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return data!.buffer.asUint8List();
  }
}
