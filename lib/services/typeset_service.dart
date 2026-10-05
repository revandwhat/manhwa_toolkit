import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class Stroke {
  Stroke({required this.pts, this.color = Colors.white, this.widthFrac = 0.02});

  final List<List<double>> pts; // [x, y] as fractions of the image
  Color color;
  double widthFrac;
}

class BoxItem {
  BoxItem({
    required this.text,
    this.x = 0.3,
    this.y = 0.3,
    this.w = 0.4,
    this.h = 0.12,
    this.font = 'Default',
    this.fs = 0.05,
    this.color = Colors.white,
    this.bold = false,
    this.italic = false,
    this.outline = true,
    this.outlineColor = Colors.black,
    this.outlineW = 2,
    this.glow = false,
    this.glowColor = Colors.cyan,
    this.glowR = 8,
    this.blur = 0,
    this.rot = 0,
    this.gradient = false,
    this.color2 = Colors.purple,
  });

  String text;
  String font;
  double x, y, w, h;
  double fs;
  Color color;
  bool bold, italic;
  bool outline;
  Color outlineColor;
  double outlineW;
  bool glow;
  Color glowColor;
  double glowR;
  double blur;
  double rot;
  bool gradient;
  Color color2;
}

class StrokesPainter extends CustomPainter {
  StrokesPainter(this.strokes);
  final List<Stroke> strokes;

  @override
  void paint(ui.Canvas canvas, Size size) =>
      TypesetService.paintStrokes(canvas, strokes, size.width, size.height);

  @override
  bool shouldRepaint(covariant StrokesPainter old) => old.strokes != strokes;
}

class TypesetService {
  static final Map<String, TextStyle Function()> fonts = {
    'Default': () => const TextStyle(),
    'Poppins': () => GoogleFonts.poppins(),
    'Montserrat': () => GoogleFonts.montserrat(),
    'Oswald': () => GoogleFonts.oswald(),
    'Bebas Neue': () => GoogleFonts.bebasNeue(),
    'Raleway': () => GoogleFonts.raleway(),
    'Merriweather': () => GoogleFonts.merriweather(),
    'Playfair Display': () => GoogleFonts.playfairDisplay(),
    'Lobster': () => GoogleFonts.lobster(),
    'Caveat': () => GoogleFonts.caveat(),
    'Indie Flower': () => GoogleFonts.indieFlower(),
    'Patrick Hand': () => GoogleFonts.patrickHand(),
    'Bangers': () => GoogleFonts.bangers(),
    'Comic Neue': () => GoogleFonts.comicNeue(),
  };

  static Future<Directory> fontDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}/fonts');
    await d.create(recursive: true);
    return d;
  }

  static String _cleanName(String raw) {
    var s = raw.replaceAll(RegExp(r'[^A-Za-z0-9_]'), '');
    if (s.isEmpty) s = 'Font';
    return s.length > 24 ? s.substring(0, 24) : s;
  }

  static Future<String> registerFontData(Uint8List bytes, String rawName) async {
    final name = _cleanName(rawName);
    final family = 'Custom_$name';
    final loader = FontLoader(family);
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
    await File('${(await fontDir()).path}/$name.ttf').writeAsBytes(bytes);
    return family;
  }

  static Future<void> registerSavedFonts() async {
    try {
      final d = await fontDir();
      for (final f in d.listSync()) {
        if (f is File && f.path.toLowerCase().endsWith('.ttf')) {
          final base = f.uri.pathSegments.last.replaceAll('.ttf', '');
          try {
            final loader = FontLoader('Custom_$base');
            final b = await f.readAsBytes();
            loader.addFont(Future.value(ByteData.view(b.buffer)));
            await loader.load();
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  static Future<String> fontFromUrl(String url) async {
    final res =
        await http.get(Uri.parse(url)).timeout(const Duration(seconds: 30));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) {
      throw Exception('Font download failed (HTTP ${res.statusCode})');
    }
    return registerFontData(res.bodyBytes, url.split('/').last);
  }

  static Future<String> fontFromFile(String path) async {
    final bytes = await File(path).readAsBytes();
    return registerFontData(bytes, path.split('/').last);
  }

  static void paintStrokes(
      ui.Canvas canvas, List<Stroke> strokes, double w, double h) {
    for (final s in strokes) {
      if (s.pts.isEmpty) continue;
      final paint = ui.Paint()
        ..color = s.color
        ..strokeWidth = (s.widthFrac * h).clamp(1.0, 500.0)
        ..strokeCap = ui.StrokeCap.round
        ..strokeJoin = ui.StrokeJoin.round
        ..style = ui.PaintingStyle.stroke;
      final path = ui.Path();
      final p0 = s.pts[0];
      path.moveTo(p0[0] * w, p0[1] * h);
      if (s.pts.length == 1) {
        path.lineTo(p0[0] * w + 0.5, p0[1] * h + 0.5);
      }
      for (var i = 1; i < s.pts.length; i++) {
        path.lineTo(s.pts[i][0] * w, s.pts[i][1] * h);
      }
      canvas.drawPath(path, paint);
    }
  }

  static Future<Uint8List> render(Uint8List imageBytes,
      List<BoxItem> items, List<Stroke> strokes) async {
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;

    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    canvas.drawImage(img, ui.Offset.zero, ui.Paint());
    paintStrokes(canvas, strokes, img.width.toDouble(), img.height.toDouble());
    for (final it in items) {
      final rect = ui.Rect.fromLTWH(it.x * img.width, it.y * img.height,
          it.w * img.width, it.h * img.height);
      _paintBox(canvas, it, rect, img.height.toDouble());
    }

    final pic = rec.endRecording();
    final out = await pic.toImage(img.width, img.height);
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return data!.buffer.asUint8List();
  }

  /// Bakes only brush strokes over the image (Clean tool's save step).
  static Future<Uint8List> bakeStrokes(
      Uint8List imageBytes, List<Stroke> strokes) async {
    final codec = await ui.instantiateImageCodec(imageBytes);
    final frame = await codec.getNextFrame();
    final img = frame.image;
    final rec = ui.PictureRecorder();
    final canvas = ui.Canvas(rec);
    canvas.drawImage(img, ui.Offset.zero, ui.Paint());
    paintStrokes(canvas, strokes, img.width.toDouble(), img.height.toDouble());
    final pic = rec.endRecording();
    final out = await pic.toImage(img.width, img.height);
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return data!.buffer.asUint8List();
  }

  static Uint8List _cropIsolate(Map<String, dynamic> a) {
    final im = img.decodeImage(a['bytes'] as Uint8List);
    if (im == null) throw Exception('Bad image');
    final r = (a['rect'] as List).cast<double>();
    final x = (im.width * r[0]).round();
    final y = (im.height * r[1]).round();
    final w = ((im.width * r[2]).round() - x).clamp(1, im.width);
    final h = ((im.height * r[3]).round() - y).clamp(1, im.height);
    final out = img.copyCrop(im, x: x, y: y, width: w, height: h);
    return Uint8List.fromList(img.encodePng(out));
  }

  static Future<Uint8List> cropImage(Uint8List bytes, Rect frac) {
    return compute(_cropIsolate, {
      'bytes': bytes,
      'rect': [frac.left, frac.top, frac.right, frac.bottom],
    });
  }

  static void _paintBox(
      ui.Canvas canvas, BoxItem it, ui.Rect rect, double imgH) {
    final fontPx = (it.fs * imgH).clamp(6.0, 400.0).toDouble();
    final base = (fonts[it.font] ?? fonts['Default']!)().copyWith(
      color: it.color,
      fontSize: fontPx,
      fontWeight: it.bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: it.italic ? FontStyle.italic : FontStyle.normal,
      height: 1.1,
    );

    canvas.save();
    canvas.translate(rect.center.dx, rect.center.dy);
    canvas.rotate(it.rot * 3.141592653589793 / 180);

    void pass(TextStyle style) {
      final tp = TextPainter(
        text: TextSpan(text: it.text, style: style),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: (rect.width * 2).clamp(20.0, 20000.0));
      tp.paint(canvas, ui.Offset(-tp.width / 2, -tp.height / 2));
    }

    if (it.glow) {
      pass(base.copyWith(
        foreground: ui.Paint()
          ..color = it.glowColor
          ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, it.glowR),
      ));
    }
    if (it.outline) {
      pass(base.copyWith(
        foreground: ui.Paint()
          ..color = it.outlineColor
          ..style = ui.PaintingStyle.stroke
          ..strokeWidth = it.outlineW,
      ));
    }
    if (it.gradient) {
      pass(base.copyWith(
        foreground: ui.Paint()
          ..shader = ui.Gradient.linear(
            ui.Offset(rect.left, rect.top),
            ui.Offset(rect.left, rect.bottom),
            [it.color, it.color2],
          ),
      ));
    } else if (it.blur > 0) {
      pass(base.copyWith(
        foreground: ui.Paint()
          ..color = it.color
          ..maskFilter = ui.MaskFilter.blur(ui.BlurStyle.normal, it.blur),
      ));
    } else {
      pass(base);
    }
    canvas.restore();
  }
}
