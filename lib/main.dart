import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
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
      home: const RootPage(),
    );
  }
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _tab = 0;

  final _gemini = GeminiService();

  static const _langs = {
    'Indonesian': 'Indonesian (Bahasa Indonesia)',
    'English': 'English',
    'Korean': 'Korean',
    'Chinese': 'Simplified Chinese',
  };

  // ---------- shared state (survives tab switches) ----------
  List<String> _paths = [];
  String _lang = 'Indonesian';
  int _panelIndex = 0;

  int? _width; // null = original
  bool _jpg = false;
  double _quality = 85;
  int _split = 0; // 0 = no split

  bool _stitching = false;
  List<Uint8List> _parts = [];

  bool _translating = false;
  List<TextItem> _items = [];

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ---------- panels ----------
  Future<void> _addPanels() async {
    final r = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
    );
    final added = r?.files
            .where((f) => f.path != null)
            .map((f) => f.path!)
            .toList() ??
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

  void _clearPanels() {
    setState(() {
      _paths = [];
      _parts = [];
      _panelIndex = 0;
    });
  }

  // ---------- stitch actions ----------
  Future<void> _stitch() async {
    if (_paths.length < 2) {
      _snack('Add at least 2 panels first');
      return;
    }
    setState(() {
      _stitching = true;
      _parts = [];
    });
    try {
      final parts = await ImageService.stitch(
        paths: _paths,
        width: _width ?? 0,
        jpg: _jpg,
        quality: _quality.round(),
        split: _split,
      );
      if (!mounted) return;
      setState(() => _parts = parts);
    } catch (e) {
      _snack('Stitch failed: $e');
    } finally {
      if (mounted) setState(() => _stitching = false);
    }
  }

  Future<void> _saveGallery() async {
    if (_parts.isEmpty) return;
    try {
      if (!await Gal.hasAccess()) {
        final ok = await Gal.requestAccess();
        if (ok != true) {
          _snack('Storage permission denied');
          return;
        }
      }
      final ts = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < _parts.length; i++) {
        await Gal.putImageBytes(
          _parts[i],
          name: 'stitched_$ts-$i.${_jpg ? 'jpg' : 'png'}',
          album: 'ManhwaToolkit',
        );
      }
      _snack('Saved ${_parts.length} image(s) to gallery');
    } catch (e) {
      _snack('Save failed: $e');
    }
  }

  Future<void> _shareParts() async {
    if (_parts.isEmpty) return;
    try {
      final ext = _jpg ? 'jpg' : 'png';
      final files = <XFile>[];
      for (var i = 0; i < _parts.length; i++) {
        final f = await ImageService.saveTemp(
            _parts[i], 'stitched-$i.$ext');
        files.add(XFile(f.path));
      }
      await SharePlus.instance
          .share(ShareParams(files: files, text: 'Stitched strip'));
    } catch (e) {
      _snack('Share failed: $e');
    }
  }

  Future<void> _sharePartsZip() async {
    if (_parts.isEmpty) return;
    try {
      final ext = _jpg ? 'jpg' : 'png';
      final names = [
        for (var i = 0; i < _parts.length; i++) 'stitched-${i + 1}.$ext'
      ];
      final zip = await ImageService.zipBytes(_parts, names);
      final f = await ImageService.saveTemp(
          zip, 'stitched_${DateTime.now().millisecondsSinceEpoch}.zip');
      await SharePlus.instance.share(
        ShareParams(files: [XFile(f.path)], text: 'Stitched strip (zip)'),
      );
    } catch (e) {
      _snack('ZIP failed: $e');
    }
  }

  Future<void> _shareRawZip() async {
    if (_paths.isEmpty) return;
    try {
      final zip = await ImageService.zipFiles(_paths);
      final f = await ImageService.saveTemp(
          zip, 'panels_${DateTime.now().millisecondsSinceEpoch}.zip');
      await SharePlus.instance.share(
        ShareParams(files: [XFile(f.path)], text: 'Raw panels (zip)'),
      );
    } catch (e) {
      _snack('ZIP failed: $e');
    }
  }

  // ---------- translate ----------
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
      _snack('Add a panel first (Stitch tab)');
      return;
    }
    final key = await _gemini.getKey();
    if (!mounted) return;
    if (key == null || key.isEmpty) {
      await _askForKey();
      return;
    }
    final idx = _panelIndex < _paths.length ? _panelIndex : 0;
    setState(() {
      _translating = true;
      _items = [];
    });
    try {
      final bytes = await File(_paths[idx]).readAsBytes();
      final mime = _paths[idx].toLowerCase().endsWith('.png')
          ? 'image/png'
          : 'image/jpeg';
      final items =
          await _gemini.ocrTranslate(bytes, mime: mime, lang: _langs[_lang]!);
      if (!mounted) return;
      setState(() => _items = items);
      if (items.isEmpty) _snack('No text detected in that panel');
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  Future<void> _customWidth() async {
    final c = TextEditingController(text: _width?.toString() ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Custom width (px)'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
              hintText: 'e.g. 900', border: OutlineInputBorder()),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save')),
        ],
      ),
    );
    if (ok != true) return;
    final v = int.tryParse(c.text.trim());
    if (v == null || v < 200 || v > 4000) {
      _snack('Width must be between 200 and 4000 px');
      return;
    }
    setState(() => _width = v);
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    const titles = ['Manhwa Toolkit', 'Stitch', 'Translate'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tab]),
        centerTitle: true,
        actions: _tab == 2
            ? [
                IconButton(icon: const Icon(Icons.key), onPressed: _askForKey)
              ]
            : null,
      ),
      body: IndexedStack(
        index: _tab,
        children: [_buildHome(), _buildStitch(), _buildTranslate()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) => setState(() => _tab = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home),
              label: 'Home'),
          NavigationDestination(
              icon: Icon(Icons.layers_outlined),
              selectedIcon: Icon(Icons.layers),
              label: 'Stitch'),
          NavigationDestination(
              icon: Icon(Icons.translate), label: 'Translate'),
        ],
      ),
    );
  }

  Widget _buildHome() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card('Welcome', [
          const Text(
            'Translate manhwa faster: stitch raw panels into one long strip, '
            'and let AI read + translate any panel (bubbles, narration, SFX).',
          ),
        ]),
        _card('How to use - Stitch', [
          _step('1', 'Open the Stitch tab and tap "Add panels".'),
          _step('2',
              'Long-press and drag to set the order (top of list = top of strip).'),
          _step('3',
              'Choose width, file type (PNG/JPG) and part splitting.'),
          _step('4',
              'Tap Stitch, then Save (gallery), Share, or Share as ZIP.'),
          const SizedBox(height: 8),
          const Text(
            'Tips: JPG is much smaller and faster. For very long strips use '
            'split (e.g. 8000 px) - some gallery apps fail on giant images.',
            style: TextStyle(fontSize: 13),
          ),
        ]),
        _card('How to use - Translate (OCR + TL)', [
          _step('1', 'Add a panel in the Stitch tab first.'),
          _step('2',
              'Open the Translate tab, pick the panel and target language.'),
          _step('3',
              'Tap "Read & translate" - every text piece appears with its translation.'),
          const SizedBox(height: 8),
          const Text(
            'Needs a free Gemini API key (key icon, top right): open '
            'aistudio.google.com, tap "Get API key", create one, paste it in. '
            'The key stays on this device only. Panel images are sent to '
            "Google's API for processing.",
            style: TextStyle(fontSize: 13),
          ),
        ]),
        _card('Coming next', [
          const Text(
            'Phase 2: tap-a-bubble cleaning (white-fill) and typesetting.\n'
            'Phase 3: AI clean & redraw.',
            style: TextStyle(fontSize: 13),
          ),
        ]),
      ],
    );
  }

  Widget _step(String n, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 10,
            child: Text(n, style: const TextStyle(fontSize: 11)),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  Widget _buildStitch() {
    final isCustom = _width != null &&
        _width != 800 &&
        _width != 1000 &&
        _width != 1200;
    return ListView(
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
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                TextButton(onPressed: _clearPanels, child: const Text('Clear all')),
                OutlinedButton.icon(
                  onPressed: _shareRawZip,
                  icon: const Icon(Icons.folder_zip, size: 18),
                  label: const Text('ZIP raws'),
                ),
              ],
            ),
        ]),
        _card('2. Settings', [
          Text('Width', style: Theme.of(context).textTheme.labelLarge),
          Text('Height follows automatically so nothing gets squashed.',
              style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              ChoiceChip(
                label: const Text('Original'),
                selected: _width == null,
                onSelected: (_) => setState(() => _width = null),
              ),
              for (final w in const [800, 1000, 1200])
                ChoiceChip(
                  label: Text('$w'),
                  selected: _width == w,
                  onSelected: (_) => setState(() => _width = w),
                ),
              ActionChip(
                avatar: const Icon(Icons.tune, size: 18),
                label: Text(isCustom ? '$_width px' : 'Custom'),
                onPressed: _customWidth,
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text('File type', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: const Text('PNG'),
                selected: !_jpg,
                onSelected: (_) => setState(() => _jpg = false),
              ),
              ChoiceChip(
                label: const Text('JPG (smaller)'),
                selected: _jpg,
                onSelected: (_) => setState(() => _jpg = true),
              ),
            ],
          ),
          if (_jpg) ...[
            Text('JPG quality: ${_quality.round()}'),
            Slider(
              value: _quality,
              min: 50,
              max: 100,
              divisions: 10,
              label: '${_quality.round()}',
              onChanged: (v) => setState(() => _quality = v),
            ),
          ],
          const SizedBox(height: 8),
          Text('Split long strips', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in const [0, 4000, 8000, 16000])
                ChoiceChip(
                  label: Text(s == 0 ? 'No split' : '$s px'),
                  selected: _split == s,
                  onSelected: (_) => setState(() => _split = s),
                ),
            ],
          ),
        ]),
        _card('3. Stitch', [
          FilledButton.icon(
            onPressed: _stitching ? null : _stitch,
            icon: const Icon(Icons.vertical_align_bottom),
            label: Text(_stitching ? 'Stitching...' : 'Stitch into strip'),
          ),
          if (_stitching)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: LinearProgressIndicator(),
            ),
          if (_parts.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text('${_parts.length} part(s) ready',
                style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SizedBox(
              height: 170,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _parts.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) => SizedBox(
                  width: 120,
                  child: Column(
                    children: [
                      Expanded(
                          child: Image.memory(_parts[i], fit: BoxFit.contain)),
                      const SizedBox(height: 4),
                      Text('Part ${i + 1}',
                          style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: _saveGallery,
                  icon: const Icon(Icons.download),
                  label: const Text('Save'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _shareParts,
                  icon: const Icon(Icons.share),
                  label: const Text('Share'),
                ),
              ),
            ]),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _sharePartsZip,
              icon: const Icon(Icons.folder_zip),
              label: const Text('Share result as ZIP'),
            ),
          ],
        ]),
      ],
    );
  }

  Widget _buildTranslate() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card('1. Target language', [
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
        ]),
        _card('2. Panel', [
          if (_paths.isEmpty)
            const Text('No panels yet - add one in the Stitch tab.')
          else ...[
            if (_paths.length > 1)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: DropdownButton<int>(
                  value: _panelIndex < _paths.length ? _panelIndex : 0,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  items: [
                    for (var i = 0; i < _paths.length; i++)
                      DropdownMenuItem(
                        value: i,
                        child: Text(
                          'Panel ${i + 1}: ${_paths[i].split('/').last}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) => setState(() => _panelIndex = v ?? 0),
                ),
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
          ],
        ]),
        _card('3. Result', [
          if (_items.isEmpty && !_translating)
            const Text('Translations will appear here.',
                style: TextStyle(fontSize: 13)),
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
