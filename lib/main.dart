import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import 'services/gemini_service.dart';
import 'services/image_service.dart';

void main() => runApp(const ManhwaApp());

class ManhwaApp extends StatelessWidget {
  const ManhwaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Manhwa Toolkit',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.deepPurple, useMaterial3: true),
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _gemini = GeminiService();

  static const _langs = {
    'Indonesian': 'Indonesian (Bahasa Indonesia)',
    'English': 'English',
    'Korean': 'Korean',
    'Chinese': 'Simplified Chinese',
  };

  List<String> _paths = [];
  String _lang = 'Indonesian';

  bool _stitching = false;
  Uint8List? _stitched;

  bool _translating = false;
  List<TextItem> _items = [];

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _addPanels() async {
    final r = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
    );
    final added =
        r?.files.where((f) => f.path != null).map((f) => f.path!).toList() ??
            const [];
    if (added.isEmpty) return;
    setState(() => _paths.addAll(added));
  }

  void _reorder(int oldI, int newI) {
    setState(() {
      final p = _paths.removeAt(oldI);
      _paths.insert(newI, p);
    });
  }

  Future<void> _stitch() async {
    if (_paths.length < 2) {
      _snack('Add at least 2 panels first');
      return;
    }
    setState(() => _stitching = true);
    try {
      final out = await ImageService.stitch(_paths);
      if (!mounted) return;
      setState(() => _stitched = out);
    } catch (e) {
      _snack('Stitch failed: $e');
    } finally {
      if (mounted) setState(() => _stitching = false);
    }
  }

  Future<void> _shareStitched() async {
    if (_stitched == null) return;
    final f = await ImageService.savePng(_stitched!);
    await SharePlus.instance.share(
      ShareParams(files: [XFile(f.path)], text: 'Stitched strip'),
    );
  }

  Future<void> _askForKey() async {
    final c = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Gemini API key'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Free: open aistudio.google.com, tap "Get API key", create one, '
                'paste it here. It stays on this device only.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: c,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'AIza...',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok == true && c.text.trim().isNotEmpty) {
      await _gemini.setKey(c.text);
      if (mounted) _snack('API key saved');
    }
  }

  Future<void> _ocrTl() async {
    if (_paths.isEmpty) {
      _snack('Add a panel first');
      return;
    }
    final key = await _gemini.getKey();
    if (!mounted) return;
    if (key == null || key.isEmpty) {
      await _askForKey();
      return;
    }
    setState(() {
      _translating = true;
      _items = [];
    });
    try {
      final bytes = await File(_paths.first).readAsBytes();
      final mime = _paths.first.toLowerCase().endsWith('.png')
          ? 'image/png'
          : 'image/jpeg';
      final items =
          await _gemini.ocrTranslate(bytes, mime: mime, lang: _langs[_lang]!);
      if (!mounted) return;
      setState(() => _items = items);
      if (items.isEmpty) _snack('No text detected in the first panel');
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Manhwa Toolkit'),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.key), onPressed: _askForKey),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _card('1. Panels', [
            Row(children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: _addPanels,
                  icon: const Icon(Icons.add_photo_alternate),
                  label: const Text('Add panels'),
                ),
              ),
              if (_paths.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text('${_paths.length}'),
              ],
            ]),
            const SizedBox(height: 8),
            if (_paths.isNotEmpty)
              ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _paths.length,
                onReorderItem: _reorder,
                itemBuilder: (ctx, i) => ListTile(
                  key: ValueKey(_paths[i]),
                  dense: true,
                  leading: const Icon(Icons.drag_indicator),
                  title: Text(
                    _paths[i].split('/').last,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            if (_paths.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() {
                    _paths = [];
                    _stitched = null;
                  }),
                  child: const Text('Clear all'),
                ),
              ),
            const Text(
              'List order = stitch order. Long-press and drag to reorder.',
              style: TextStyle(fontSize: 12),
            ),
          ]),
          _card('2. Stitch', [
            FilledButton.icon(
              onPressed: _stitching ? null : _stitch,
              icon: const Icon(Icons.vertical_align_bottom),
              label: Text(_stitching ? 'Stitching...' : 'Stitch into one strip'),
            ),
            if (_stitched != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                height: 340,
                child: InteractiveViewer(
                  maxScale: 5,
                  child: Center(child: Image.memory(_stitched!)),
                ),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _shareStitched,
                icon: const Icon(Icons.save),
                label: const Text('Save & share PNG'),
              ),
            ],
          ]),
          _card('3. OCR + TL (first panel)', [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _langs.entries
                  .map((e) => ChoiceChip(
                        label: Text(e.key),
                        selected: _lang == e.key,
                        onSelected: (_) => setState(() => _lang = e.key),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _translating ? null : _ocrTl,
              icon: const Icon(Icons.translate),
              label: Text(_translating ? 'Reading panel...' : 'Read & translate'),
            ),
            if (_translating)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(),
              ),
            for (final it in _items)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      it.original,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      it.translated,
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w600),
                    ),
                    Text(it.kind, style: const TextStyle(fontSize: 11)),
                  ],
                ),
              ),
          ]),
        ],
      ),
    );
  }

  Widget _card(String title, List<Widget> children) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      ),
    );
  }
}
