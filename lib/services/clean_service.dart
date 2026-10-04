import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;

// Flood-fill + dilate + fill, on raw RGBA bytes. Runs in an isolate.
Uint8List _clean(Map<String, dynamic> a) {
  final rgba = (a['rgba'] as Uint8List);
  final w = a['w'] as int;
  final h = a['h'] as int;
  final sx = a['x'] as int;
  final sy = a['y'] as int;
  final tol = a['tol'] as int;

  final n = w * h;
  final i0 = (sy * w + sx) * 4;
  final sr = rgba[i0], sg = rgba[i0 + 1], sb = rgba[i0 + 2];

  bool match(int p) {
    final o = p * 4;
    final dr = rgba[o] - sr, dg = rgba[o + 1] - sg, db = rgba[o + 2] - sb;
    return dr * dr + dg * dg + db * db <= tol * tol;
  }

  final mask = Uint8List(n);
  final stack = <int>[sy * w + sx];
  mask[sy * w + sx] = 1;
  var count = 0;
  final maxFill = (n * 0.7).toInt();
  var ar = 0, ag = 0, ab = 0, cnt = 0;

  while (stack.isNotEmpty) {
    final p = stack.removeLast();
    count++;
    if (count > maxFill) {
      throw Exception('Region too large - tap inside a bubble, not the background');
    }
    final o = p * 4;
    ar += rgba[o];
    ag += rgba[o + 1];
    ab += rgba[o + 2];
    cnt++;
    final x = p % w, y = p ~/ w;
    if (x > 0 && mask[p - 1] == 0 && match(p - 1)) {
      mask[p - 1] = 1;
      stack.add(p - 1);
    }
    if (x < w - 1 && mask[p + 1] == 0 && match(p + 1)) {
      mask[p + 1] = 1;
      stack.add(p + 1);
    }
    if (y > 0 && mask[p - w] == 0 && match(p - w)) {
      mask[p - w] = 1;
      stack.add(p - w);
    }
    if (y < h - 1 && mask[p + w] == 0 && match(p + w)) {
      mask[p + w] = 1;
      stack.add(p + w);
    }
  }

  // Dilate the mask so text strokes touching the background get covered too.
  const r = 2;
  final dil = Uint8List.fromList(mask);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = y * w + x;
      if (mask[p] == 1) continue;
      var hit = false;
      for (var dy = -r; dy <= r && !hit; dy++) {
        final yy = y + dy;
        if (yy < 0 || yy >= h) continue;
        for (var dx = -r; dx <= r; dx++) {
          final xx = x + dx;
          if (xx < 0 || xx >= w) continue;
          if (mask[yy * w + xx] == 1) {
            hit = true;
            break;
          }
        }
      }
      if (hit) dil[p] = 1;
    }
  }

  // Fill with the average color of the bubble interior (white-ish).
  final fr = cnt > 0 ? ar ~/ cnt : 255;
  final fg = cnt > 0 ? ag ~/ cnt : 255;
  final fb = cnt > 0 ? ab ~/ cnt : 255;
  for (var p = 0; p < n; p++) {
    if (dil[p] == 1) {
      final o = p * 4;
      rgba[o] = fr;
      rgba[o + 1] = fg;
      rgba[o + 2] = fb;
      rgba[o + 3] = 255;
    }
  }
  return rgba;
}

class CleanService {
  /// [width, height] of an encoded image (png/jpg/webp).
  static Future<List<int>> dims(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final d = [frame.image.width, frame.image.height];
    frame.image.dispose();
    return d;
  }

  /// Returns a new PNG with the tapped region wiped to its background color.
  static Future<Uint8List> clean(
    Uint8List bytes, {
    required int x,
    required int y,
    required int tolerance,
  }) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final w = img.width, h = img.height;
    final data =
        await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    final rgba = data!.buffer.asUint8List();
    img.dispose();

    final cleaned = await compute(_clean, {
      'rgba': rgba,
      'w': w,
      'h': h,
      'x': x.clamp(0, w - 1),
      'y': y.clamp(0, h - 1),
      'tol': tolerance,
    });

    final buf = await ui.ImmutableBuffer.fromUint8List(cleaned);
    final desc = ui.ImageDescriptor.raw(
      buf,
      width: w,
      height: h,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec2 = await desc.instantiateCodec();
    final f2 = await codec2.getNextFrame();
    final out = await f2.image.toByteData(format: ui.ImageByteFormat.png);
    f2.image.dispose();
    return out!.buffer.asUint8List();
  }
}
