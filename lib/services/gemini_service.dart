import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'typeset_service.dart' show BoxItem;

class GeminiService {
  static const _model = 'gemini-3.8-flash';
  static const _url =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  Future<String?> getKey() async =>
      (await SharedPreferences.getInstance()).getString('gemini_key');

  Future<void> setKey(String key) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('gemini_key', key.trim());
  }

  /// POST with retries on 429/5xx ("high demand" 503 included).
  Future<http.Response> _post(String body, String key) async {
    var last = '';
    for (var a = 1; a <= 3; a++) {
      try {
        final res = await http
            .post(
              Uri.parse('$_url?key=$key'),
              headers: {'Content-Type': 'application/json'},
              body: body,
            )
            .timeout(const Duration(seconds: 90));
        if (res.statusCode == 200) return res;
        last = 'API ${res.statusCode}: ${res.body}';
        if (res.statusCode == 429 || res.statusCode >= 500) {
          await Future.delayed(Duration(seconds: 5 * a));
          continue;
        }
        break; // 4xx = real problem (bad key, bad request) - no retry
      } on Exception catch (e) {
        last = e.toString();
      }
    }
    throw Exception('$last\n(Model busy or unreachable - '
        'retry in a minute, or use the Free engine)');
  }

  Future<String> _vision(
    Uint8List imageBytes, {
    required String mime,
    required String prompt,
  }) async {
    final key = await getKey();
    if (key == null || key.isEmpty) throw Exception('NO_KEY');
    final body = jsonEncode({
      'contents': [
        {
          'parts': [
            {'text': prompt},
            {
              'inline_data': {
                'mime_type': mime,
                'data': base64Encode(imageBytes)
              }
            },
          ]
        }
      ],
      'generationConfig': {
        'temperature': 0.2,
        'responseMimeType': 'application/json',
      },
    });
    final res = await _post(body, key);
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final cands = data['candidates'] as List?;
    if (cands == null || cands.isEmpty) return '';
    final parts = cands[0]['content']['parts'] as List;
    return ((parts[0] as Map)['text'] ?? '').toString();
  }

  /// OCR tool: ALL text in the image, original language, order kept.
  Future<String> extractText(Uint8List imageBytes,
      {required String mime}) async {
    final raw = await _vision(imageBytes,
        mime: mime,
        prompt: 'Extract ALL text visible in this comic image: speech '
            'bubbles, narration boxes, sound effects, signs, screens. Keep '
            'the reading order and line breaks. Do not translate. Return '
            'ONLY JSON: {"text":"..."} with \\n for line breaks.');
    final cleaned =
        raw.replaceAll('```json', '').replaceAll('```', '').trim();
    if (cleaned.isEmpty) return '';
    try {
      final d = jsonDecode(cleaned) as Map<String, dynamic>;
      return (d['text'] ?? '').toString();
    } catch (_) {
      return cleaned;
    }
  }

  /// TS tool: translate every text piece WITH its position.
  Future<List<BoxItem>> readPanel(
    Uint8List imageBytes, {
    required String mime,
    required String lang,
  }) async {
    final raw = await _vision(imageBytes,
        mime: mime,
        prompt: 'You are a professional manhwa/manga translator.\n'
            'Find every piece of text in this comic panel and translate '
            'into $lang.\n'
            'For each piece give its text area as fractions of the image '
            'size: x,y = top-left corner, w,h = width and height, all '
            'between 0 and 1.\n'
            'Return ONLY a JSON array, no markdown fences:\n'
            '[{"translated":"...","kind":"bubble",'
            '"x":0.1,"y":0.2,"w":0.3,"h":0.08}]\n'
            'If there is no text at all, return [].');
    final cleaned =
        raw.replaceAll('```json', '').replaceAll('```', '').trim();
    if (cleaned.isEmpty) return [];
    try {
      final list = jsonDecode(cleaned) as List;
      return list.map((e) {
        final j = e as Map<String, dynamic>;
        return BoxItem(
          text: (j['translated'] ?? '').toString(),
          x: _d(j['x'], 0.3),
          y: _d(j['y'], 0.3),
          w: _d(j['w'], 0.4).clamp(0.04, 1.0).toDouble(),
          h: _d(j['h'], 0.12).clamp(0.03, 1.0).toDouble(),
        );
      }).toList();
    } catch (_) {
      throw Exception('AI returned an unreadable layout - try again');
    }
  }

  static double _d(dynamic v, double def) {
    final d = double.tryParse('$v');
    return (d == null || d.isNegative || d > 1) ? def : d;
  }
}
