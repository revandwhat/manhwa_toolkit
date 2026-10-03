import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

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
  int _tab = 0; // 0 home, 1 tools, 2 game
  String _tool = 'Stitch';

  final _gemini = GeminiService();

  static const _langs = {
    'Indonesian': 'Indonesian (Bahasa Indonesia)',
    'English': 'English',
    'Korean': 'Korean',
    'Chinese': 'Simplified Chinese',
  };

  // ---------- Stitch tool state ----------
  List<String> _stitchPaths = [];
  int? _width; // null = original
  bool _jpg = false;
  double _quality = 85;
  int _split = 0;
  String _exportMode = 'picture'; // picture | zip | folder
  bool _stitching = false;
  List<Uint8List> _parts = [];
  String? _savedWhere;

  // ---------- OCR+TL tool state ----------
  String? _tlPath;
  String _lang = 'Indonesian';
  bool _translating = false;
  List<TextItem> _items = [];

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  // ================= Stitch =================

  Future<void> _addStitchPanels() async {
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
    setState(() => _stitchPaths.addAll(added));
  }

  void _reorder(int oldI, int newI) {
    setState(() {
      final p = _stitchPaths.removeAt(oldI);
      _stitchPaths.insert(newI, p);
    });
  }

  /// One flow: pick destination -> stitch -> files land there automatically.
  Future<void> _stitch() async {
    if (_stitchPaths.length < 2) {
      _snack('Add at least 2 panels first');
      return;
    }
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Pick where to save the result',
    );
    if (dir == null) return;
    setState(() {
      _stitching = true;
      _parts = [];
      _savedWhere = null;
    });
    try {
      final parts = await ImageService.stitch(
        paths: _stitchPaths,
        width: _width ?? 0,
        jpg: _jpg,
        quality: _quality.round(),
        split: _split,
      );

      final ext = _jpg ? 'jpg' : 'png';
      final ts = DateTime.now().millisecondsSinceEpoch;
      if (_exportMode == 'zip') {
        final names = [
          for (var i = 0; i < parts.length; i++) 'stitched-$ts-${i + 1}.$ext'
        ];
        final zip = await ImageService.zipBytes(parts, names);
        await File('$dir/stitched_$ts.zip').writeAsBytes(zip);
      } else if (_exportMode == 'folder') {
        final sub = Directory('$dir/stitched_$ts');
        await sub.create(recursive: true);
        for (var i = 0; i < parts.length; i++) {
          await File('${sub.path}/part-${i + 1}.$ext').writeAsBytes(parts[i]);
        }
      } else {
        for (var i = 0; i < parts.length; i++) {
          await File('$dir/stitched-$ts-${i + 1}.$ext')
              .writeAsBytes(parts[i]);
        }
      }

      if (!mounted) return;
      setState(() {
        _parts = parts;
        _savedWhere = dir;
      });
      _snack('Done - saved to $dir');
    } catch (e) {
      _snack('Failed: $e');
    } finally {
      if (mounted) setState(() => _stitching = false);
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

  // ================= OCR + TL =================

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

  Future<void> _pickTlImage() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = r?.files.single.path;
    if (path == null) return;
    setState(() {
      _tlPath = path;
      _items = [];
    });
  }

  Future<void> _ocrTl() async {
    if (_tlPath == null) {
      _snack('Choose an image first');
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
      final bytes = await File(_tlPath!).readAsBytes();
      final mime =
          _tlPath!.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
      final items =
          await _gemini.ocrTranslate(bytes, mime: mime, lang: _langs[_lang]!);
      if (!mounted) return;
      setState(() => _items = items);
      if (items.isEmpty) _snack('No text detected in that image');
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  // ================= UI =================

  @override
  Widget build(BuildContext context) {
    const titles = ['Manhwa Toolkit', 'Tools', 'Mini Game'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tab]),
        centerTitle: true,
        actions: _tab == 1
            ? [
                IconButton(icon: const Icon(Icons.key), onPressed: _askForKey)
              ]
            : null,
      ),
      body: IndexedStack(
        index: _tab,
        children: [_buildHome(), _buildTools(), _buildGame()],
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
              icon: Icon(Icons.build_outlined),
              selectedIcon: Icon(Icons.build),
              label: 'Tools'),
          NavigationDestination(
              icon: Icon(Icons.sports_esports_outlined),
              selectedIcon: Icon(Icons.sports_esports),
              label: 'Game'),
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
            'Your manhwa translation workbench. Open the Tools tab and pick '
            'a tool from the dropdown - every tool has its own file input.',
          ),
        ]),
        _card('Tool: Stitch', [
          _step('1', 'Tools tab -> dropdown -> Stitch -> "Add panels".'),
          _step('2',
              'Long-press and drag to order (top of list = top of strip).'),
          _step('3',
              'Set width, file type, splitting, and the export format (Picture / ZIP / Folder).'),
          _step('4',
              'Tap "Stitch & save" - pick the destination folder when asked, '
              'and the result lands there automatically. Nothing else to press.'),
        ]),
        _card('Tool: OCR + Translate', [
          _step('1', 'Tools tab -> dropdown -> OCR + TL -> "Choose image".'),
          _step('2', 'Pick the target language.'),
          _step('3',
              '"Read & translate" returns every text piece: bubbles, narration, SFX.'),
          const SizedBox(height: 8),
          const Text(
            'Needs a free Gemini API key (key icon, top right): '
            'aistudio.google.com -> "Get API key". The key stays on this '
            "device only. Chosen images are sent to Google's API.",
            style: TextStyle(fontSize: 13),
          ),
        ]),
        _card('Coming next', [
          const Text(
            'Clean (manual white-fill + AI option), Typeset (draggable text '
            'layers), raw downloader, and a mini game. Each gets its own '
            'slot in the Tools dropdown.',
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

  Widget _buildTools() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card('Pick a tool', [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(8),
            ),
            child: DropdownButton<String>(
              value: _tool,
              isExpanded: true,
              underline: const SizedBox.shrink(),
              items: const [
                DropdownMenuItem(
                    value: 'Stitch',
                    child: Text('Stitch - combine panels into a strip')),
                DropdownMenuItem(
                    value: 'OCR + TL',
                    child: Text('OCR + Translate - read a panel')),
              ],
              onChanged: (v) => setState(() => _tool = v ?? 'Stitch'),
            ),
          ),
        ]),
        if (_tool == 'Stitch') ..._stitchCards() else ..._tlCards(),
      ],
    );
  }

  // ---------- Stitch tool ----------

  List<Widget> _stitchCards() {
    final isCustom = _width != null &&
        _width != 800 &&
        _width != 1000 &&
        _width != 1200;
    return [
      _card('1. Panels', [
        Row(children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: _addStitchPanels,
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('Add panels'),
            ),
          ),
          if (_stitchPaths.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text('${_stitchPaths.length}'),
          ],
        ]),
        const SizedBox(height: 8),
        if (_stitchPaths.isNotEmpty)
          ReorderableListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _stitchPaths.length,
            onReorderItem: _reorder,
            itemBuilder: (ctx, i) => ListTile(
              key: ValueKey(_stitchPaths[i]),
              dense: true,
              leading: const Icon(Icons.drag_indicator),
              title: Text(
                _stitchPaths[i].split('/').last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        if (_stitchPaths.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: () => setState(() {
                _stitchPaths = [];
                _parts = [];
                _savedWhere = null;
              }),
              child: const Text('Clear all'),
            ),
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
        Text('Split long strips',
            style: Theme.of(context).textTheme.labelLarge),
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
        const SizedBox(height: 16),
        Text('Export format', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final m in const [
              ('picture', 'Picture(s)'),
              ('zip', 'ZIP'),
              ('folder', 'Folder'),
            ])
              ChoiceChip(
                label: Text(m.$2),
                selected: _exportMode == m.$1,
                onSelected: (_) => setState(() => _exportMode = m.$1),
              ),
          ],
        ),
      ]),
      _card('3. Stitch & save', [
        FilledButton.icon(
          onPressed: _stitching ? null : _stitch,
          icon: const Icon(Icons.save_alt),
          label: Text(_stitching ? 'Stitching & saving...' : 'Stitch & save'),
        ),
        const SizedBox(height: 8),
        const Text(
          'You will pick the destination folder right after tapping - '
          'the result is written there automatically.',
          style: TextStyle(fontSize: 13),
        ),
        if (_stitching)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        if (_parts.isNotEmpty && !_stitching) ...[
          const SizedBox(height: 12),
          Text('${_parts.length} part(s) saved',
              style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 4),
          if (_savedWhere != null)
            SelectableText(
              'Saved to: $_savedWhere',
              style: Theme.of(context).textTheme.bodySmall,
            ),
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
        ],
      ]),
    ];
  }

  // ---------- OCR + TL tool ----------

  List<Widget> _tlCards() {
    return [
      _card('1. Image', [
        Row(children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: _pickTlImage,
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('Choose image'),
            ),
          ),
        ]),
        if (_tlPath != null) ...[
          const SizedBox(height: 8),
          Text(_tlPath!.split('/').last,
              maxLines: 1, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          SizedBox(
            height: 180,
            child: InteractiveViewer(
              maxScale: 5,
              child: Center(child: Image.file(File(_tlPath!))),
            ),
          ),
        ],
      ]),
      _card('2. Target language', [
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
      _card('3. Read & translate', [
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
      ]),
      _card('4. Result', [
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
    ];
  }

  // ---------- Game placeholder ----------

  Widget _buildGame() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _card('Mini game - under construction', [
          const Text(
            'Coming soon. Idea: a word game powered by your own KBBI '
            'dictionary - guess, streak, beat your high score.\n\n'
            'Tell me which game you want and it lands in this tab.',
            style: TextStyle(fontSize: 13),
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
