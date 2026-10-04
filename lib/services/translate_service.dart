import 'dart:async';
import 'dart:convert';

import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TranslateService {
  static const _model = 'gemini-3.8-flash';
  static const _geminiUrl =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  static const _ml = {
    'id': TranslateLanguage.indonesian,
    'en': TranslateLanguage.english,
    'ko': TranslateLanguage.korean,
    'zh-CN': TranslateLanguage.chinese,
  };

  Future<String?> getKey() async =>
      (await SharedPreferences.getInstance()).getString('gemini_key');

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

  // ---- Free engine (online, no key, unofficial endpoint) ----
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

  // ---- Offline engine (ML Kit on-device) ----
  Future<String> _offlineChunk(String text, String fromCode, String toCode) async {
    final src = _ml[fromCode];
    final tgt = _ml[toCode];
    if (src == null || tgt == null) {
      throw Exception('Language not supported offline');
    }
    try {
      final mgr = OnDeviceTranslatorModelManager();
      if (!await mgr.isModelDownloaded(fromCode)) {
        await mgr.downloadModel(fromCode, isWifiRequired: false);
      }
      if (!await mgr.isModelDownloaded(toCode)) {
        await mgr.downloadModel(toCode, isWifiRequired: false);
      }
      final t = OnDeviceTranslator(sourceLanguage: src, targetLanguage: tgt);
      try {
        return await t.translateText(text);
      } finally {
        await t.close();
      }
    } catch (e) {
      throw Exception(
          'Offline engine failed (first use downloads ~30MB per language, '
          'and Google Play Services must be installed): $e');
    }
  }

  // ---- Gemini (online, key, retries through 503s) ----
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
    throw Exception('$last\n(Model busy - retry soon, or switch engine)');
  }

  Future<String> _geminiOnce(String text, String name, String key) async {
    final prompt = 'Translate the text inside <text> tags into $name.\n'
        'Rules:\n'
        '- Output ONLY the translation, no notes, no markdown.\n'
        '- Preserve the paragraph structure exactly.\n\n'
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
    required String engine, // 'free' | 'gemini' | 'offline'
    required String langCode,
    required String langName,
    String? fromCode,
    void Function(int done, int total)? onProgress,
  }) async {
    if (text.trim().isEmpty) throw Exception('No text found in that file');
    String? key;
    if (engine == 'gemini') {
      key = await getKey();
      if (key == null || key.isEmpty) {
        throw Exception('Gemini needs a key - or switch engine');
      }
    }
    if (engine == 'offline' && fromCode == langCode) {
      throw Exception('Source and target language are the same');
    }
    final maxLen =
        engine == 'gemini' ? 3500 : (engine == 'free' ? 1800 : 2500);
    final chunks = chunk(text, maxLen);
    final out = <String>[];
    for (var i = 0; i < chunks.length; i++) {
      switch (engine) {
        case 'gemini':
          out.add(await _geminiOnce(chunks[i], langName, key!));
        case 'offline':
          out.add(await _offlineChunk(chunks[i], fromCode ?? 'en', langCode));
        default:
          out.add(await _freeOnce(chunks[i], langCode));
      }
      onProgress?.call(i + 1, chunks.length);
      if (i < chunks.length - 1) {
        await Future.delayed(
            Duration(milliseconds: engine == 'free' ? 400 : 200));
      }
    }
    return out.join('\n\n');
  }
}
