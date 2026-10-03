import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TextItem {
  TextItem({required this.original, required this.translated, required this.kind});

  final String original;
  final String translated;
  final String kind;

  factory TextItem.fromJson(Map<String, dynamic> j) => TextItem(
        original: (j['original'] ?? '').toString(),
        translated: (j['translated'] ?? '').toString(),
        kind: (j['kind'] ?? 'bubble').toString(),
      );
}

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

  Future<String> _vision(
    Uint8List imageBytes, {
    required String mime,
    required String prompt,
  }) async {
    final key = await getKey();
    if (key == null || key.isEmpty) throw Exception('NO_KEY');
    final res = await http.post(
      Uri.parse('$_url?key=$key'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'contents': [
          {
            'parts': [
              {'text': prompt},
              {
                'inline_data': {'mime_type': mime, 'data': base64Encode(imageBytes)}
              },
            ]
          }
        ],
        'generationConfig': {
          'temperature': 0.2,
          'responseMimeType': 'application/json',
        },
      }),
    );
    if (res.statusCode != 200) {
      throw Exception('API ${res.statusCode}: ${res.body}');
    }
    final data = jsonDecode(res.body) as Map<String, dynamic>;
    final cands = data['candidates'] as List?;
    if (cands == null || cands.isEmpty) return '';
    final parts = cands[0]['content']['parts'] as List;
    return ((parts[0] as Map)['text'] ?? '').toString();
  }

  /// OCR tool: ALL text found in the image, original language, order kept.
  Future<String> extractText(Uint8List imageBytes, {required String mime}) async {
    final raw = await _vision(imageBytes, mime: mime,
        prompt: 'Extract ALL text visible in this comic image: speech bubbles, '
            'narration boxes, sound effects, signs, screens. Keep the reading '
            'order and line breaks. Do not translate. Return ONLY JSON: '
            '{"text":"..."} with \\n for line breaks.');
    final cleaned = raw.replaceAll('```json', '').replaceAll('```', '').trim();
    if (cleaned.isEmpty) return '';
    try {
      final d = jsonDecode(cleaned) as Map<String, dynamic>;
      return (d['text'] ?? '').toString();
    } catch (_) {
      return cleaned;
    }
  }

  /// Kept for the future clean/typeset phases.
  Future<List<TextItem>> ocrTranslate(
    Uint8List imageBytes, {
    required String mime,
    required String lang,
  }) async {
    final raw = await _vision(imageBytes, mime: mime,
        prompt: 'You are a professional manhwa/manga translator.\n'
            'Find every piece of text in this comic panel and translate into $lang.\n'
            'Return ONLY a JSON array, no markdown fences:\n'
            '[{"original":"...","translated":"...","kind":"bubble|narration|sfx"}]\n'
            'If there is no text at all, return [].');
    final cleaned = raw.replaceAll('```json', '').replaceAll('```', '').trim();
    if (cleaned.isEmpty) return [];
    final list = jsonDecode(cleaned) as List;
    return list
        .map((e) => TextItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
