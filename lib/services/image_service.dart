import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

class ImageService {
  /// Stitches images vertically into one long manhwa strip.
  /// Two passes (measure, then blit) to keep memory low on phones.
  static Future<Uint8List> stitch(List<String> paths) async {
    var targetW = 0;
    final sizes = <List<int>>[];
    for (final p in paths) {
      try {
        final im = img.decodeImage(await File(p).readAsBytes());
        if (im == null) continue;
        sizes.add([im.width, im.height]);
        if (im.width > targetW) targetW = im.width;
      } catch (_) {}
    }
    if (targetW == 0) throw Exception('No readable images');

    var totalH = 0;
    for (final s in sizes) {
      totalH += (s[1] * targetW / s[0]).round();
    }

    final canvas = img.Image(width: targetW, height: totalH);
    var y = 0;
    for (final p in paths) {
      final im = img.decodeImage(await File(p).readAsBytes());
      if (im == null) continue;
      final part = im.width == targetW ? im : img.copyResize(im, width: targetW);
      img.compositeImage(canvas, part, dstX: 0, dstY: y);
      y += part.height;
    }
    return img.encodePng(canvas);
  }

  static Future<File> savePng(Uint8List bytes) async {
    final dir = await getApplicationDocumentsDirectory();
    final f = File(
        '${dir.path}/stitched_${DateTime.now().millisecondsSinceEpoch}.png');
    return f.writeAsBytes(bytes);
  }
}
