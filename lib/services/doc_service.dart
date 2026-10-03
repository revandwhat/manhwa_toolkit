import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class DocService {
  static Future<String> extractText(String path) async {
    final l = path.toLowerCase();
    if (l.endsWith('.txt') || l.endsWith('.md')) {
      try {
        return await File(path).readAsString();
      } catch (_) {
        return latin1.decode(await File(path).readAsBytes());
      }
    }
    if (l.endsWith('.pdf')) {
      final doc = PdfDocument(inputBytes: await File(path).readAsBytes());
      final t = PdfTextExtractor(doc).extractText();
      doc.dispose();
      return t.trim();
    }
    if (l.endsWith('.docx')) {
      final archive = ZipDecoder().decodeBytes(await File(path).readAsBytes());
      for (final f in archive.files) {
        if (f.name == 'word/document.xml') {
          var s = utf8.decode(f.content as List<int>);
          s = s.replaceAll(RegExp(r'</w:p>'), '\n\n');
          s = s.replaceAll(RegExp(r'<w:br\s*/?>'), '\n');
          s = s.replaceAll(RegExp(r'<[^>]+>'), '');
          return _unescape(s).trim();
        }
      }
      throw FormatException('Not a valid .docx');
    }
    if (l.endsWith('.doc')) {
      throw FormatException(
          'Legacy .doc is not supported - re-save as .docx, .pdf or .txt');
    }
    if (l.endsWith('.png') ||
        l.endsWith('.jpg') ||
        l.endsWith('.jpeg') ||
        l.endsWith('.webp')) {
      throw FormatException('That is an image - use the OCR tool to read it');
    }
    throw FormatException('Unsupported type - use .txt, .pdf or .docx');
  }

  static String _unescape(String s) => s
      .replaceAll('&amp;', '&')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAllMapped(
          RegExp(r'&#(\d+);'),
          (m) => String.fromCharCode(int.parse(m.group(1)!)));

  static String _esc(String s) => s
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');

  static Uint8List buildTxt(String text) =>
      Uint8List.fromList(utf8.encode(text));

  /// Minimal valid .docx: one paragraph element per blank-line-separated chunk.
  static Uint8List buildDocx(String text) {
    final paras = text.split(RegExp(r'\n\s*\n'));
    final body = StringBuffer();
    for (final p in paras) {
      final lines = p.split('\n');
      final runs = StringBuffer();
      for (var i = 0; i < lines.length; i++) {
        if (i > 0) runs.write('<w:r><w:br/></w:r>');
        runs.write(
            '<w:r><w:t xml:space="preserve">${_esc(lines[i])}</w:t></w:r>');
      }
      body.write('<w:p>$runs</w:p>');
    }
    const ct =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
        '</Types>';
    const rels =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
        '</Relationships>';
    const drels =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"/>';
    final doc =
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
        '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
        '<w:body>$body<w:sectPr/></w:body></w:document>';
    final a = Archive();
    void add(String name, String s) {
      final b = utf8.encode(s);
      a.addFile(ArchiveFile(name, b.length, b));
    }

    add('[Content_Types].xml', ct);
    add('_rels/.rels', rels);
    add('word/_rels/document.xml.rels', drels);
    add('word/document.xml', doc);
    return Uint8List.fromList(ZipEncoder().encode(a));
  }

  static Future<Uint8List> buildZipBoth(String text, String base) async {
    final t = buildTxt(text);
    final d = buildDocx(text);
    final a = Archive();
    a.addFile(ArchiveFile('$base.txt', t.length, t));
    a.addFile(ArchiveFile('$base.docx', d.length, d));
    return Uint8List.fromList(ZipEncoder().encode(a));
  }
}
