import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

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
  String font; // preset name or Custom_<name>
  double x, y, w, h;
  double fs; // fraction of image height
  Color color;
  bool bold, italic;
  bool outline;
  Color outlineColor;
  double outlineW;
  bool glow;
  Color glowColor;
  double glowR;
  double blur;
  double rot; // degrees
  bool gradient;
  Color color2;
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

  /// Registers font bytes under family `Custom_<name>` and saves for next launches.
  static Future<String> registerFontData(Uint8List bytes, String rawName) async {
    final name = _cleanName(rawName);
    final family = 'Custom_$name';
    final loader = FontLoader(family);
    loader.addFont(Future.value(ByteData.view(bytes.buffer)));
    await loader.load();
    await File('${(await fontDir()).path}/$name.ttf').writeAsBytes(bytes);
    return family;
  }

  /// Re-registers fonts saved by previous sessions (call when tool opens).
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
    final seg = url.split('/').last;
    return registerFontData(res.bodyBytes, seg);
  }

  static Future<String> fontFromFile(String path) async {
    final bytes = await File(path).readAsBytes();
    final seg = path.split('/').last;
    return registerFontData(bytes, seg);
  }

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
      _paintBox(canvas, it, rect, img.height.toDouble());
    }

    final pic = rec.endRecording();
    final out = await pic.toImage(img.width, img.height);
    final data = await out.toByteData(format: ui.ImageByteFormat.png);
    img.dispose();
    return data!.buffer.asUint8List();
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
