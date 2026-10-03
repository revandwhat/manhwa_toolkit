import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';

/// Runs inside a background isolate (via compute) so the UI never freezes.
List<Uint8List> _stitchIsolate(Map<String, dynamic> args) {
  final paths = (args['paths'] as List).cast<String>();
  final targetW = args['width'] as int; // 0 = auto (widest panel)
  final jpg = args['jpg'] as bool;
  final quality = args['quality'] as int;
  final splitH = args['split'] as int; // 0 = no split

  Uint8List encode(img.Image im) =>
      jpg ? img.encodeJpg(im, quality: quality) : img.encodePng(im);

  var w = targetW;
  if (w <= 0) {
    for (final p in paths) {
      final im = img.decodeImage(File(p).readAsBytesSync());
      if (im == null) continue;
      if (im.width > w) w = im.width;
    }
  }
  if (w <= 0) throw Exception('No readable images');

  final pieces = <img.Image>[];
  for (final p in paths) {
    final im = img.decodeImage(File(p).readAsBytesSync());
    if (im == null) continue;
    pieces.add(im.width == w ? im : img.copyResize(im, width: w));
  }
  if (pieces.isEmpty) throw Exception('No readable images');

  // No split: one tall canvas
  if (splitH <= 0) {
    var total = 0;
    for (final p in pieces) {
      total += p.height;
    }
    final canvas = img.Image(width: w, height: total);
    var y = 0;
    for (final p in pieces) {
      img.compositeImage(canvas, p, dstX: 0, dstY: y);
      y += p.height;
    }
    return [encode(canvas)];
  }

  // Split mode: fixed-height parts, pieces that span two parts get cut
  final parts = <Uint8List>[];
  var cur = img.Image(width: w, height: splitH);
  var y = 0;
  for (final p in pieces) {
    img.Image? piece = p;
    while (piece != null) {
      final remaining = splitH - y;
      if (piece.height <= remaining) {
        img.compositeImage(cur, piece, dstX: 0, dstY: y);
        y += piece.height;
        piece = null;
      } else {
        if (remaining > 0) {
          final top =
              img.copyCrop(piece, x: 0, y: 0, width: w, height: remaining);
          img.compositeImage(cur, top, dstX: 0, dstY: y);
        }
        parts.add(encode(cur));
        cur = img.Image(width: w, height: splitH);
        y = 0;
        final left = piece.height - remaining;
        piece = left > 0
            ? img.copyCrop(piece, x: 0, y: remaining, width: w, height: left)
            : null;
      }
    }
  }
  if (y > 0) {
    parts.add(encode(
        y == splitH ? cur : img.copyCrop(cur, x: 0, y: 0, width: w, height: y)));
  }
  return parts;
}

class ImageService {
  static Future<List<Uint8List>> stitch({
    required List<String> paths,
    required int width,
    required bool jpg,
    required int quality,
    required int split,
  }) {
    return compute(_stitchIsolate, {
      'paths': paths,
      'width': width,
      'jpg': jpg,
      'quality': quality,
      'split': split,
    });
  }

  static Future<Uint8List> zipFiles(List<String> paths) async {
    final a = Archive();
    for (final p in paths) {
      final b = await File(p).readAsBytes();
      a.addFile(ArchiveFile(p.split('/').last, b.length, b));
    }
    final out = ZipEncoder().encode(a);
    return Uint8List.fromList(out);
  }

  static Future<Uint8List> zipBytes(
      List<Uint8List> datas, List<String> names) async {
    final a = Archive();
    for (var i = 0; i < datas.length; i++) {
      a.addFile(ArchiveFile(names[i], datas[i].length, datas[i]));
    }
    final out = ZipEncoder().encode(a);
    return Uint8List.fromList(out);
  }

  static Future<File> saveTemp(Uint8List bytes, String name) async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$name').writeAsBytes(bytes);
  }
}

