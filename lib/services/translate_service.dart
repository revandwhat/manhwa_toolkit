import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TranslateService {
  static const _model = 'gemini-3.8-flash';
  static const _geminiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  Future<String?> getKey() async =>
      (await SharedPreferences.getInstance()).getString('gemini_key');

  Future<void> setKey(String k) async => (await SharedPreferences.getInstance())
      .setString('gemini_key', k.trim());

  /// Splits on blank lines so paragraphs (and titles) keep their positions.
  List<String> chunk(String text, [int max = 3000]) {
    if (text.length <= max) return [text];
    final paras = text.split(RegExp(r'\n\s*\n'));
    final chunks = <String>[];
    var buf = '';
    for (final p in paras) {
      if (p.length > max) {
        if (buf.isNotEmpty) {
          chunks.add(buf.trim());
          buf = '';
        }
        for (var i = 0; i < p.length; i += max) {
          final end = (i + max < p.length) ? i + max : p.length;
          chunks.add(p.substring(i, end));
        }
        continue;
      }
      if (('$buf\n\n$p').length > max) {
        chunks.add(buf.trim());
        buf = p;
      } else {
        buf = buf.isEmpty ? p : '$buf\n\n$p';
      }
    }
    if (buf.trim().isNotEmpty) chunks.add(buf.trim());
    return chunks;
  }

  /// No-key engine: Google's public translate endpoint (unofficial).
  Future<String> _freeOnce(String text, String code) async {
    for (var a = 1; a <= 3; a++) {
      try {
        final res = await http
            .post(
              Uri.parse(
                  'https://translate.googleapis.com/translate_a/single?client=gtx&sl=auto&tl=$code&dt=t'),
              headers: {
                'Content-Type':
                    'application/x-www-form-urlencoded;charset=UTF-8'
              },
              body: 'q=${Uri.encodeQueryComponent(text)}',
            )
            .timeout(const Duration(seconds: 30));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as List;
          final segs = data[0] as List?;
          if (segs == null) throw Exception('Free engine: empty response');
          return segs.map((s) => ((s as List)[0] ?? '').toString()).join();
        }
        if (res.statusCode == 429 || res.statusCode >= 500) {
          await Future.delayed(Duration(seconds: 2 * a));
          continue;
        }
        throw Exception('Free engine HTTP ${res.statusCode}');
      } on TimeoutException {
        if (a == 3) rethrow;
      }
    }
    throw Exception('Free engine unavailable (rate-limited?)');
  }

  /// Gemini with retries - rides out 503 "high demand" spikes.
  Future<http.Response> _post(String prompt, String key) async {
    var last = '';
    for (var a = 1; a <= 3; a++) {
      try {
        final res = await http
            .post(
              Uri.parse('$_geminiUrl?key=$key'),
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode({
                'contents': [
                  {
                    'parts': [
                      {'text': prompt}
                    ]
                  }
                ],
                'generationConfig': {'temperature': 0.2},
              }),
            )
            .timeout(const Duration(seconds: 90));
        if (res.statusCode == 200) return res;
        last = 'Gemini ${res.statusCode}: ${res.body}';
        if (res.statusCode == 429 || res.statusCode >= 500) {
          await Future.delayed(Duration(seconds: 4 * a));
          continue;
        }
        break;
      } on TimeoutException {
        last = 'Gemini timed out';
      }
    }
    throw Exception('$last\n(Model busy - retry soon, or use the Free engine)');
  }

  Future<String> _geminiOnce(String text, String name, String key) async {
    final prompt = 'Translate the text inside <text> tags into $name.\n'
        'Rules:\n'
        '- Output ONLY the translation, no notes, no markdown.\n'
        '- Preserve the paragraph structure exactly: same number of '
        'paragraphs, same order (titles stay titles).\n\n'
        '<text>\n$text\n</text>';
    final res = await _post(prompt, key);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final cands = data['candidates'] as List?;
    if (cands == null || cands.isEmpty) throw Exception('Gemini: empty reply');
    final parts = cands[0]['content']['parts'] as List;
    return ((parts[0] as Map)['text'] ?? '').toString().trim();
  }

  Future<String> translateAll(
    String text, {
    required String langCode,
    required String langName,
    required bool useGemini,
    void Function(int done, int total)? onProgress,
  }) async {
    if (text.trim().isEmpty) throw Exception('No text found in that file');
    String? key;
    if (useGemini) {
      key = await getKey();
      if (key == null || key.isEmpty) {
        throw Exception('Gemini needs a key - or switch to the Free engine');
      }
    }
    final chunks = chunk(text, useGemini ? 3500 : 1800);
    final out = <String>[];
    for (var i = 0; i < chunks.length; i++) {
      out.add(useGemini
          ? await _geminiOnce(chunks[i], langName, key!)
          : await _freeOnce(chunks[i], langCode));
      onProgress?.call(i + 1, chunks.length);
      if (i < chunks.length - 1) {
        await Future.delayed(Duration(milliseconds: useGemini ? 1500 : 400));
      }
    }
    return out.join('\n\n');
  }
}
