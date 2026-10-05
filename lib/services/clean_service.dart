import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

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

Uint8List _fillBoxes(Map<String, dynamic> a) {
  final rgba = a['rgba'] as Uint8List;
  final w = a['w'] as int;
  final h = a['h'] as int;
  final boxes = (a['boxes'] as List)
      .map((e) => (e as List).cast<int>())
      .toList();

  for (final b in boxes) {
    final x0 = (b[0] - 6).clamp(0, w - 1);
    final y0 = (b[1] - 6).clamp(0, h - 1);
    final x1 = (b[0] + b[2] + 6).clamp(1, w);
    final y1 = (b[1] + b[3] + 6).clamp(1, h);

    const pad = 10;
    var ar = 0, ag = 0, ab = 0, n = 0;
    void sample(int x, int y) {
      if (x < 0 || y < 0 || x >= w || y >= h) return;
      final o = (y * w + x) * 4;
      ar += rgba[o];
      ag += rgba[o + 1];
      ab += rgba[o + 2];
      n++;
    }

    for (var x = x0 - pad; x <= x1 + pad; x += 3) {
      sample(x, y0 - pad);
      sample(x, y1 + pad);
    }
    for (var y = y0 - pad; y <= y1 + pad; y += 3) {
      sample(x0 - pad, y);
      sample(x1 + pad, y);
    }
    if (n == 0) continue;
    final r = ar ~/ n, g = ag ~/ n, bl = ab ~/ n;

    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final o = (y * w + x) * 4;
        rgba[o] = r;
        rgba[o + 1] = g;
        rgba[o + 2] = bl;
        rgba[o + 3] = 255;
      }
    }
  }
  return rgba;
}

class CleanService {
  static Future<List<int>> dims(Uint8List bytes) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final d = [frame.image.width, frame.image.height];
    frame.image.dispose();
    return d;
  }

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
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
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

  /// OFFLINE auto-clean: on-device OCR finds text boxes, fills each with
  /// the color sampled just outside it. Free, no key, no internet.
  static Future<Uint8List> autoCleanOffline(String path, Uint8List bytes) async {
    final input = InputImage.fromFilePath(path);
    final boxes = <List<int>>[];
    for (final script in [
      TextRecognitionScript.latin,
      TextRecognitionScript.korean,
    ]) {
      final rec = TextRecognizer(script: script);
      try {
        final r = await rec.processImage(input);
        for (final b in r.blocks) {
          for (final l in b.lines) {
            final bb = l.boundingBox;
            if (bb.width < 3 || bb.height < 3) continue;
            boxes.add([
              bb.left.round(),
              bb.top.round(),
              bb.width.round(),
              bb.height.round()
            ]);
          }
        }
      } catch (_) {
        // that script's model not ready - skip it
      } finally {
        rec.close();
      }
    }
    if (boxes.isEmpty) {
      throw Exception('Offline OCR found no text (or its model is still '
          'downloading - try again once, online)');
    }

    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final w = img.width, h = img.height;
    final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
    final rgba = data!.buffer.asUint8List();
    img.dispose();

    final filled = await compute(
        _fillBoxes, {'rgba': rgba, 'w': w, 'h': h, 'boxes': boxes});

    final buf = await ui.ImmutableBuffer.fromUint8List(filled);
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

  /// AI auto-clean: whole panel to Gemini's image model, text-free back.
  static const _imgModel = 'gemini-3.8-flash-image';

  static Future<Uint8List> aiClean(Uint8List bytes,
      {required String mime}) async {
    final key =
        (await SharedPreferences.getInstance()).getString('gemini_key');
    if (key == null || key.isEmpty) throw Exception('NO_KEY');

    final res = await http
        .post(
          Uri.parse(
              'https://generativelanguage.googleapis.com/v1beta/models/$_imgModel:generateContent?key=$key'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'contents': [
              {
                'parts': [
                  {
                    'text': 'Remove ALL text from this comic panel: speech '
                        'bubbles, narration boxes, sound effects, watermarks. '
                        'Reconstruct the art and bubble interiors cleanly. '
                        'Output only the edited image.'
                  },
                  {
                    'inline_data': {
                      'mime_type': mime,
                      'data': base64Encode(bytes)
                    }
                  },
                ]
              }
            ],
            'generationConfig': {'responseModalities': ['IMAGE']},
          }),
        )
        .timeout(const Duration(seconds: 180));

    if (res.statusCode != 200) {
      throw Exception('AI clean ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final cands = data['candidates'] as List?;
    if (cands == null || cands.isEmpty) {
      throw Exception('AI clean: empty response');
    }
    final parts = cands[0]['content']['parts'] as List;
    for (final p in parts) {
      final m = p as Map<String, dynamic>;
      final inline =
          (m['inlineData'] ?? m['inline_data']) as Map<String, dynamic>?;
      if (inline != null && inline['data'] != null) {
        return base64Decode(inline['data'] as String);
      }
    }
    throw Exception(
        'AI clean returned no image: ${res.body.substring(0, res.body.length.clamp(0, 300))}');
  }
}
