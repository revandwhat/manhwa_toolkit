import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

import 'services/doc_service.dart';
import 'services/gemini_service.dart';
import 'services/image_service.dart';
import 'services/translate_service.dart';

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
  final _svc = TranslateService();

  static const _langCodes = {
    'Indonesian': 'id',
    'English': 'en',
    'Korean': 'ko',
    'Chinese': 'zh-CN',
  };
  static const _langNames = {
    'Indonesian': 'Indonesian (Bahasa Indonesia)',
    'English': 'English',
    'Korean': 'Korean',
    'Chinese': 'Simplified Chinese',
  };

  // ---------- storage helpers ----------
  static Future<Directory> _importsDir() async {
    final docs = await getApplicationDocumentsDirectory();
    final d = Directory('${docs.path}/imports');
    await d.create(recursive: true);
    return d;
  }

  Future<String> _importCopy(String src) async {
    try {
      final dir = await _importsDir();
      final name =
          '${DateTime.now().microsecondsSinceEpoch}_${src.split('/').last}';
      final out = File('${dir.path}/$name');
      await File(src).copy(out.path);
      return out.path;
    } catch (_) {
      return src;
    }
  }

  Future<bool> _ensureStorage() async {
    if (await Permission.manageExternalStorage.isGranted) return true;
    if (await Permission.storage.request().isGranted) return true;
    final s = await Permission.manageExternalStorage.request();
    if (s.isGranted) return true;
    _snack('Allow "All files access" (one time), then try again');
    return false;
  }

  Future<String> _unique(String path, {bool isDir = false}) async {
    final dot = path.lastIndexOf('.');
    final hasExt = !isDir && dot > path.lastIndexOf('/');
    final stem = hasExt ? path.substring(0, dot) : path;
    final ext = hasExt ? path.substring(dot) : '';
    var cand = path;
    var i = 1;
    while (isDir ? await Directory(cand).exists() : await File(cand).exists()) {
      i++;
      cand = '$stem-$i$ext';
    }
    return cand;
  }

  String _sanitize(String raw) {
    final s = raw.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return s.isEmpty ? 'output' : s;
  }

  // ---------- shared ----------
  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
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
                'Optional: only needed for the Gemini engine and the OCR tool. '
                'Free at aistudio.google.com -> "Get API key". '
                'The key stays on this device only.',
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

  // ---------- Stitch state ----------
  List<String> _stitchPaths = [];
  bool _jpg = false;
  double _quality = 85;
  int _split = 0;
  String _exportMode = 'picture'; // picture | zip | folder
  final _nameCtrl = TextEditingController(text: 'stitched');
  bool _stitching = false;
  List<Uint8List> _parts = [];
  String? _savedWhere;

  Future<void> _addStitchPanels() async {
    final r = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.image,
    );
    final added =
        r?.files.where((f) => f.path != null).map((f) => f.path!).toList() ??
            const [];
    if (added.isEmpty) return;
    final imported = <String>[];
    for (final p in added) {
      imported.add(await _importCopy(p));
    }
    setState(() => _stitchPaths.addAll(imported));
  }

  void _reorder(int oldI, int newI) {
    setState(() {
      final p = _stitchPaths.removeAt(oldI);
      _stitchPaths.insert(newI, p);
    });
  }

  Future<void> _stitch() async {
    if (_stitchPaths.length < 2) {
      _snack('Add at least 2 panels first');
      return;
    }
    if (!await _ensureStorage()) return;
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Pick where to save the result',
    );
    if (dir == null) return;
    final base = _sanitize(_nameCtrl.text);
    setState(() {
      _stitching = true;
      _parts = [];
      _savedWhere = null;
    });
    try {
      final parts = await ImageService.stitch(
        paths: _stitchPaths,
        jpg: _jpg,
        quality: _quality.round(),
        split: _split,
      );
      final ext = _jpg ? 'jpg' : 'png';
      if (_exportMode == 'zip') {
        final names = [
          for (var i = 0; i < parts.length; i++) '$base-${i + 1}.$ext'
        ];
        final zip = await ImageService.zipBytes(parts, names);
        final out = await _unique('$dir/$base.zip');
        await File(out).writeAsBytes(zip);
      } else if (_exportMode == 'folder') {
        final out = await _unique('$dir/$base', isDir: true);
        await Directory(out).create(recursive: true);
        for (var i = 0; i < parts.length; i++) {
          await File('$out/$base-${i + 1}.$ext').writeAsBytes(parts[i]);
        }
      } else {
        for (var i = 0; i < parts.length; i++) {
          final out = await _unique('$dir/$base-$i.$ext');
          await File(out).writeAsBytes(parts[i]);
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

  // ---------- Translate-file state ----------
  String? _docPath;
  bool _useGemini = false;
  String _lang = 'Indonesian';
  String _outFormat = 'docx'; // txt | docx | zip
  bool _translating = false;
  String _prog = '';
  String? _tlSavedWhere;

  Future<void> _pickDoc() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = r?.files.single.path;
    if (path == null) return;
    setState(() {
      _docPath = path;
      _tlSavedWhere = null;
    });
  }

  Future<void> _translateSave() async {
    if (_docPath == null) {
      _snack('Choose a file first');
      return;
    }
    if (!await _ensureStorage()) return;
    final dir = await FilePicker.platform.getDirectoryPath(
      dialogTitle: 'Pick where to save the translation',
    );
    if (dir == null) return;
    setState(() {
      _translating = true;
      _prog = '';
      _tlSavedWhere = null;
    });
    try {
      final text = await DocService.extractText(_docPath!);
      final out = await _svc.translateAll(
        text,
        langCode: _langCodes[_lang]!,
        langName: _langNames[_lang]!,
        useGemini: _useGemini,
        onProgress: (d, t) {
          if (mounted) setState(() => _prog = 'Part $d of $t');
        },
      );
      final srcName = _docPath!.split('/').last;
      final dot = srcName.lastIndexOf('.');
      final stem = dot > 0 ? srcName.substring(0, dot) : srcName;
      final base = '${_sanitize(stem)}-${_langCodes[_lang]}';
      String saved;
      if (_outFormat == 'zip') {
        final zip = await DocService.buildZipBoth(out, base);
        final p = await _unique('$dir/$base.zip');
        await File(p).writeAsBytes(zip);
        saved = p;
      } else if (_outFormat == 'docx') {
        final p = await _unique('$dir/$base.docx');
        await File(p).writeAsBytes(DocService.buildDocx(out));
        saved = p;
      } else {
        final p = await _unique('$dir/$base.txt');
        await File(p).writeAsBytes(DocService.buildTxt(out));
        saved = p;
      }
      if (!mounted) return;
      setState(() => _tlSavedWhere = saved);
      _snack('Done - $saved');
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', '').replaceFirst('FormatException: ', ''));
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  // ---------- OCR state ----------
  String? _ocrPath;
  bool _autoOcr = true;
  bool _ocrBusy = false;
  String _ocrText = '';

  Future<void> _pickOcrImage() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = r?.files.single.path;
    if (path == null) return;
    final imported = await _importCopy(path);
    setState(() {
      _ocrPath = imported;
      _ocrText = '';
    });
    if (_autoOcr) await _runOcr();
  }

  Future<void> _runOcr() async {
    if (_ocrPath == null) {
      _snack('Choose an image first');
      return;
    }
    setState(() => _ocrBusy = true);
    try {
      final bytes = await File(_ocrPath!).readAsBytes();
      final mime =
          _ocrPath!.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
      final text = await _gemini.extractText(bytes, mime: mime);
      if (!mounted) return;
      setState(() => _ocrText = text);
      if (text.isEmpty) _snack('No text detected');
    } catch (e) {
      final m = e.toString().replaceFirst('Exception: ', '');
      _snack(m == 'NO_KEY' ? 'Add a Gemini key (key icon, top right)' : m);
    } finally {
      if (mounted) setState(() => _ocrBusy = false);
    }
  }

  // ---------- UI ----------
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
            'Pick a tool in the Tools tab. Every tool has its own input and '
            'saves its result straight to a folder you choose.',
          ),
        ]),
        _card('Tool: Stitch', [
          _step('1', 'Add panels, drag to order (top = top of strip).'),
          _step('2',
              'Panels keep their original pixels - no resizing, ever.'),
          _step('3', 'Set file name, type (PNG/JPG), splitting, export format.'),
          _step('4', 'Tap Stitch & save -> pick folder -> done.'),
        ]),
        _card('Tool: Translate file', [
          _step('1', 'Pick a .txt, .md, .pdf or .docx file.'),
          _step('2', 'Engine: Free (no key needed) or Gemini (better quality).'),
          _step('3', 'Pick language and output format: TXT, DOCX or ZIP.'),
          _step('4',
              'Translate & save -> pick folder. Paragraphs and titles keep '
              'their positions; the translation is written to the file, not '
              'shown on screen.'),
        ]),
        _card('Tool: OCR - image text', [
          _step('1', 'Pick an image (manhwa panel, page...).'),
          _step('2',
              'Auto-extract toggle: ON = reads text immediately after picking. '
              'OFF = you press "Extract text" yourself.'),
          _step('3', 'All found text is listed and copyable. Needs a Gemini key.'),
        ]),
        _card('Coming next', [
          const Text(
            'Clean (manual white-fill + AI option), Typeset (draggable text '
            'layers), raw downloader, mini game.',
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
                    value: 'Translate file',
                    child: Text('Translate file - txt/pdf/docx -> file')),
                DropdownMenuItem(
                    value: 'OCR',
                    child: Text('OCR - read all text in an image')),
              ],
              onChanged: (v) => setState(() => _tool = v ?? 'Stitch'),
            ),
          ),
        ]),
        if (_tool == 'Stitch') ..._stitchCards(),
        if (_tool == 'Translate file') ..._tlCards(),
        if (_tool == 'OCR') ..._ocrCards(),
      ],
    );
  }

  // ---------- Stitch UI ----------

  List<Widget> _stitchCards() {
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
        const Text(
          'Original pixels only: output width = widest panel, no resizing.',
          style: TextStyle(fontSize: 12),
        ),
      ]),
      _card('2. Settings', [
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'File name',
            hintText: 'stitched',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
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
          'Pick the destination folder right after tapping - files are '
          'written there automatically.',
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
            SelectableText('Saved to: $_savedWhere',
                style: Theme.of(context).textTheme.bodySmall),
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

  // ---------- Translate-file UI ----------

  List<Widget> _tlCards() {
    return [
      _card('1. File', [
        Row(children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: _pickDoc,
              icon: const Icon(Icons.description),
              label: const Text('Choose file'),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        const Text('Supported: .txt  .md  .pdf  .docx',
            style: TextStyle(fontSize: 12)),
        if (_docPath != null) ...[
          const SizedBox(height: 8),
          Text(_docPath!.split('/').last,
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ]),
      _card('2. Engine & language', [
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: const Text('Free (no key)'),
              selected: !_useGemini,
              onSelected: (_) => setState(() => _useGemini = false),
            ),
            ChoiceChip(
              label: const Text('Gemini (key)'),
              selected: _useGemini,
              onSelected: (_) => setState(() => _useGemini = true),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _langCodes.keys
              .map((k) => ChoiceChip(
                    label: Text(k),
                    selected: _lang == k,
                    onSelected: (_) => setState(() => _lang = k),
                  ))
              .toList(),
        ),
      ]),
      _card('3. Output format', [
        Wrap(
          spacing: 8,
          children: [
            for (final f in const [
              ('txt', 'TXT'),
              ('docx', 'DOCX (Word)'),
              ('zip', 'ZIP (txt+docx)'),
            ])
              ChoiceChip(
                label: Text(f.$2),
                selected: _outFormat == f.$1,
                onSelected: (_) => setState(() => _outFormat = f.$1),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Paragraph structure is preserved - titles and order stay in place. '
          'The translation goes straight into the output file.',
          style: TextStyle(fontSize: 13),
        ),
      ]),
      _card('4. Translate & save', [
        FilledButton.icon(
          onPressed: _translating ? null : _translateSave,
          icon: const Icon(Icons.translate),
          label:
              Text(_translating ? 'Translating...' : 'Translate & save'),
        ),
        if (_translating) ...[
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
          if (_prog.isNotEmpty) Text(_prog),
        ],
        if (_tlSavedWhere != null && !_translating) ...[
          const SizedBox(height: 12),
          SelectableText('Saved to: $_tlSavedWhere',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ]),
    ];
  }

  // ---------- OCR UI ----------

  List<Widget> _ocrCards() {
    return [
      _card('1. Image', [
        Row(children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: _ocrBusy ? null : _pickOcrImage,
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('Choose image'),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Auto-extract after picking'),
          subtitle: const Text('OFF = press "Extract text" yourself'),
          value: _autoOcr,
          onChanged: (v) => setState(() => _autoOcr = v),
        ),
        if (_ocrPath != null)
          Text(_ocrPath!.split('/').last,
              maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
      _card('2. Extract', [
        FilledButton.icon(
          onPressed: _ocrBusy ? null : _runOcr,
          icon: const Icon(Icons.document_scanner),
          label: Text(_ocrBusy ? 'Reading...' : 'Extract text'),
        ),
        if (_ocrBusy)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        const SizedBox(height: 8),
        const Text('Needs a Gemini API key (key icon, top right).',
            style: TextStyle(fontSize: 12)),
      ]),
      _card('3. Text found', [
        if (_ocrText.isEmpty && !_ocrBusy)
          const Text('Extracted text will appear here.',
              style: TextStyle(fontSize: 13)),
        if (_ocrText.isNotEmpty) ...[
          SelectableText(_ocrText),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: _ocrText));
              _snack('Copied');
            },
            icon: const Icon(Icons.copy),
            label: const Text('Copy all'),
          ),
        ],
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
            'Coming soon. Tell me which game you want and it lands in this tab.',
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
