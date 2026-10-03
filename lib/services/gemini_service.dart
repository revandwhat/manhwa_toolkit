import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class TextItem {
  TextItem({required this.original, required this.translated, required this.kind});

  final String original;
  final String translated;
  final String kind; // bubble | narration | sfx

  factory TextItem.fromJson(Map<String, dynamic> j) => TextItem(
        original: (j['original'] ?? '').toString(),
        translated: (j['translated'] ?? '').toString(),
        kind: (j['kind'] ?? 'bubble').toString(),
      );
}

class GeminiService {
  // If the API ever returns 404 for the model, use the new model name
  // printed inside the error message.
  static const _model = 'gemini-3.8-flash';
  static const _url =
      'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent';

  Future<String?> getKey() async =>
      (await SharedPreferences.getInstance()).getString('gemini_key');

  Future<void> setKey(String key) async {
    final p = await SharedPreferences.getInstance();
    await p.setString('gemini_key', key.trim());
  }

  /// One vision call: finds every text in the panel AND translates it.
  Future<List<TextItem>> ocrTranslate(
    Uint8List imageBytes, {
    required String mime,
    required String lang,
  }) async {
    final key = await getKey();
    if (key == null || key.isEmpty) throw Exception('NO_KEY');

    final prompt = 'You are a professional manhwa/manga translator.\n'
        'Find every piece of text in this comic panel: speech bubbles, '
        'narration boxes, sound effects, text on signs or screens.\n'
        'For each piece give the original text and its translation into $lang.\n'
        'Return ONLY a JSON array, no markdown fences:\n'
        '[{"original":"...","translated":"...","kind":"bubble|narration|sfx"}]\n'
        'If there is no text at all, return [].';

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
    if (cands == null || cands.isEmpty) return [];
    final parts = cands[0]['content']['parts'] as List;
    final text = ((parts[0] as Map)['text'] ?? '') as String;
    final cleaned = text.replaceAll('```json', '').replaceAll('```', '').trim();
    final list = jsonDecode(cleaned) as List;
    return list
        .map((e) => TextItem.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
