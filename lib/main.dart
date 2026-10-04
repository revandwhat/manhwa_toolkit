import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'login_page.dart';

import 'services/clean_service.dart';
import 'services/doc_service.dart';
import 'services/gemini_service.dart';
import 'services/image_service.dart';
import 'services/translate_service.dart';
import 'services/typeset_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabaseFromPrefs();
  runApp(const ManhwaApp());
}

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

  // ---------- shared helpers ----------
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
                'Optional: needed for the Gemini engine, OCR and Typeset. '
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

  Future<String?> _pickDestFolder(String title) async {
    if (!await _ensureStorage()) return null;
    return FilePicker.platform.getDirectoryPath(dialogTitle: title);
  }

  // ---------- Stitch state ----------
  List<String> _stitchPaths = [];
  bool _jpg = false;
  double _quality = 85;
  int _split = 0;
  String _exportMode = 'picture';
  final _nameCtrl = TextEditingController(text: '[Stitched] File');
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
    final dir = await _pickDestFolder('Pick where to save the result');
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
  String _engine = 'free'; // free | gemini | offline
  String _fromLang = 'English';
  String _lang = 'Indonesian';
  String _outFormat = 'docx';
  bool _translating = false;
  String _prog = '';
  String? _tlSavedWhere;

  Future<void> _pickDoc() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any);
    final path = r?.files.single.path;
    if (path == null) return;
    final imported = await _importCopy(path);
    setState(() {
      _docPath = imported;
      _tlSavedWhere = null;
    });
  }

  Future<void> _translateSave() async {
    if (_docPath == null) {
      _snack('Choose a file first');
      return;
    }
    final dir = await _pickDestFolder('Pick where to save the translation');
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
        engine: _engine,
        langCode: _langCodes[_lang]!,
        langName: _langNames[_lang]!,
        fromCode: _langCodes[_fromLang],
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
      _snack('Done');
    } catch (e) {
      _snack(e
          .toString()
          .replaceFirst('Exception: ', '')
          .replaceFirst('FormatException: ', ''));
    } finally {
      if (mounted) setState(() => _translating = false);
    }
  }

  // ---------- OCR state ----------
  String? _ocrPath;
  bool _autoOcr = true;
  bool _ocrBusy = false;
  String _ocrText = '';

  static bool _isImage(String p) {
    final l = p.toLowerCase();
    return l.endsWith('.png') ||
        l.endsWith('.jpg') ||
        l.endsWith('.jpeg') ||
        l.endsWith('.webp');
  }

  Future<void> _pickOcrImage() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = r?.files.single.path;
    if (path == null) return;
    if (!_isImage(path)) {
      _snack('That is not an image. For .txt/.pdf/.docx use Translate file.');
      return;
    }
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

  // ---------- Clean (CL) state ----------
  Uint8List? _clOriginal;
  Uint8List? _clBytes;
  List<int> _clDims = [0, 0];
  final List<Uint8List> _clUndo = [];
  double _clTol = 55;
  final _clNameCtrl = TextEditingController(text: '[Cleaned] File');
  bool _clBusy = false;
  String? _clSavedWhere;

  Future<void> _pickCleanImage() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = r?.files.single.path;
    if (path == null) return;
    if (!_isImage(path)) {
      _snack('That is not an image.');
      return;
    }
    final imported = await _importCopy(path);
    try {
      final bytes = await File(imported).readAsBytes();
      final dims = await CleanService.dims(bytes);
      if (!mounted) return;
      setState(() {
        _clOriginal = bytes;
        _clBytes = bytes;
        _clDims = dims;
        _clUndo.clear();
        _clSavedWhere = null;
      });
    } catch (_) {
      _snack('Could not read that image');
    }
  }

  Future<void> _onCleanTap(TapUpDetails d, double dispW, double dispH) async {
    if (_clBytes == null || _clBusy || _clDims[0] == 0) return;
    final px =
        (d.localPosition.dx / dispW * _clDims[0]).round().clamp(0, _clDims[0] - 1);
    final py =
        (d.localPosition.dy / dispH * _clDims[1]).round().clamp(0, _clDims[1] - 1);
    setState(() => _clBusy = true);
    try {
      final out = await CleanService.clean(_clBytes!,
          x: px, y: py, tolerance: _clTol.round());
      if (!mounted) return;
      setState(() {
        _clUndo.add(_clBytes!);
        if (_clUndo.length > 5) _clUndo.removeAt(0);
        _clBytes = out;
      });
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _clBusy = false);
    }
  }

  Future<void> _saveClean() async {
    if (_clBytes == null) return;
    final dir = await _pickDestFolder('Pick where to save the cleaned image');
    if (dir == null) return;
    final base = _sanitize(_clNameCtrl.text);
    final out = await _unique('$dir/$base.png');
    try {
      await File(out).writeAsBytes(_clBytes!);
      if (!mounted) return;
      setState(() => _clSavedWhere = out);
      _snack('Done');
    } catch (e) {
      _snack('Save failed: $e');
    }
  }

  // ---------- Typeset (TS) state ----------
  String? _tsPath;
  Uint8List? _tsBytes;
  List<int> _tsDims = [0, 0];
  List<BoxItem> _tsItems = [];
  String _tsLang = 'Indonesian';
  bool _tsBusy = false;
  final _tsNameCtrl = TextEditingController(text: '[Typeset] File');
  String? _tsSavedWhere;

  Future<void> _pickTsImage() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = r?.files.single.path;
    if (path == null) return;
    if (!_isImage(path)) {
      _snack('That is not an image.');
      return;
    }
    final imported = await _importCopy(path);
    try {
      final bytes = await File(imported).readAsBytes();
      final dims = await CleanService.dims(bytes);
      if (!mounted) return;
      setState(() {
        _tsPath = imported;
        _tsBytes = bytes;
        _tsDims = dims;
        _tsItems = [];
        _tsSavedWhere = null;
      });
    } catch (_) {
      _snack('Could not read that image');
    }
  }

  Future<void> _tsRead() async {
    if (_tsBytes == null) {
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
      _tsBusy = true;
      _tsItems = [];
    });
    try {
      final mime = _tsPath!.toLowerCase().endsWith('.png')
          ? 'image/png'
          : 'image/jpeg';
      final items = await _gemini.readPanel(
        _tsBytes!,
        mime: mime,
        lang: _langNames[_tsLang]!,
      );
      if (!mounted) return;
      setState(() => _tsItems = items);
      _snack(items.isEmpty
          ? 'No text detected'
          : '${items.length} box(es) - drag to adjust, tap to edit');
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _tsBusy = false);
    }
  }

  void _tsAddBox() {
    if (_tsBytes == null) {
      _snack('Choose an image first');
      return;
    }
    setState(() => _tsItems.add(BoxItem(translated: 'text')));
  }

  Future<void> _editTsItem(int i) async {
    final it = _tsItems[i];
    final c = TextEditingController(text: it.translated);
    double size = it.size;
    final res = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit text'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: c, maxLines: 4, autofocus: true),
            const SizedBox(height: 8),
            StatefulBuilder(
              builder: (ctx, setD) => Slider(
                value: size,
                min: 0.15,
                max: 0.9,
                divisions: 15,
                label: 'font size',
                onChanged: (v) => setD(() => size = v),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'del'),
            child:
                const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 'ok'),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (res == 'del') {
      setState(() => _tsItems.removeAt(i));
    } else if (res == 'ok') {
      setState(() {
        it.translated = c.text.trim();
        it.size = size;
      });
    }
  }

  Future<void> _tsExport() async {
    if (_tsBytes == null || _tsItems.isEmpty) {
      _snack('Nothing to export yet');
      return;
    }
    final dir = await _pickDestFolder('Pick where to save the typeset image');
    if (dir == null) return;
    final base = _sanitize(_tsNameCtrl.text);
    setState(() => _tsBusy = true);
    try {
      final png = await TypesetService.render(_tsBytes!, _tsItems);
      final out = await _unique('$dir/$base.png');
      await File(out).writeAsBytes(png);
      if (!mounted) return;
      setState(() => _tsSavedWhere = out);
      _snack('Done');
    } catch (e) {
      _snack('Export failed: $e');
    } finally {
      if (mounted) setState(() => _tsBusy = false);
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
                IconButton(
                    icon: const Icon(Icons.key), onPressed: _askForKey)
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
            'Five tools in the Tools tab. Every tool has its own input and '
            'saves results straight to a folder you choose.',
          ),
        ]),
        _card('Stitch', [
          _step('1', 'Add panels, drag to order (top = top of strip).'),
          _step('2',
              'Original pixels kept - no resizing. Set file name, PNG/JPG, splitting, format.'),
          _step('3', 'Stitch & save -> pick folder -> done.'),
        ]),
        _card('Translate file', [
          _step('1', 'Pick .txt / .md / .pdf / .docx.'),
          _step('2', 'Engine: Free (no key) or Gemini.'),
          _step('3',
              'Translate & save -> folder. Structure preserved; output is TXT / DOCX / ZIP.'),
        ]),
        _card('OCR - image text', [
          _step('1', 'Pick an image. Auto-extract toggle or manual button.'),
          _step('2', 'All text listed and copyable. Needs a Gemini key.'),
        ]),
        _card('Clean (CL)', [
          _step('1', 'Pick a panel, set tolerance.'),
          _step('2',
              'Tap inside a bubble - the text is wiped to the bubble color. Tap again for more bubbles.'),
          _step('3', 'Undo / Reset if a tap goes wrong, then Save.'),
        ]),
        _card('Typeset (TS)', [
          _step('1', 'Pick a panel -> "Read & translate" (AI, needs key).'),
          _step('2',
              'White text boxes appear on the panel: drag to move, tap to edit text/size, add boxes manually.'),
          _step('3', 'Export -> finished PNG with boxes baked in.'),
        ]),
        _card('Coming next', [
          const Text(
            'AI clean & redraw (needs an image-generation API), raw '
            'downloader, mini game.',
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
                DropdownMenuItem(
                    value: 'Clean',
                    child: Text('Clean (CL) - tap bubbles to erase text')),
                DropdownMenuItem(
                    value: 'Typeset',
                    child: Text('Typeset (TS) - place translated text')),
              ],
              onChanged: (v) => setState(() => _tool = v ?? 'Stitch'),
            ),
          ),
        ]),
        if (_tool == 'Stitch') ..._stitchCards(),
        if (_tool == 'Translate file') ..._tlCards(),
        if (_tool == 'OCR') ..._ocrCards(),
        if (_tool == 'Clean') ..._clCards(),
        if (_tool == 'Typeset') ..._tsCards(),
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
        const Text('Original pixels only: output width = widest panel.',
            style: TextStyle(fontSize: 12)),
      ]),
      _card('2. Settings', [
        TextField(
          controller: _nameCtrl,
          decoration: const InputDecoration(
            labelText: 'File name',
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
            for (final e in const {
              'picture': 'Picture(s)',
              'zip': 'ZIP',
              'folder': 'Folder',
            }.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: _exportMode == e.key,
                onSelected: (_) => setState(() => _exportMode = e.key),
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
              selected: _engine == 'free',
              onSelected: (_) => setState(() => _engine = 'free'),
            ),
            ChoiceChip(
              label: const Text('Gemini (key)'),
              selected: _engine == 'gemini',
              onSelected: (_) => setState(() => _engine = 'gemini'),
            ),
            ChoiceChip(
              label: const Text('Offline (ML Kit)'),
              selected: _engine == 'offline',
              onSelected: (_) => setState(() => _engine = 'offline'),
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
        if (_engine == 'offline') ...[
          const SizedBox(height: 8),
          const Text('Translate FROM (offline cannot auto-detect):',
              style: TextStyle(fontSize: 12)),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _langCodes.keys
                .map((k) => ChoiceChip(
                      label: Text(k),
                      selected: _fromLang == k,
                      onSelected: (_) => setState(() => _fromLang = k),
                    ))
                .toList(),
          ),
          const Text(
            'Offline = free + no internet after first model download. '
            'Styles (barbarian etc.) need Gemini.',
            style: TextStyle(fontSize: 12),
          ),
        ],
        const SizedBox(height: 8),
        const Text('Gemini busy (503)? Switch engine.',
            style: TextStyle(fontSize: 12)),
      ]),
      _card('3. Output format', [
        Wrap(
          spacing: 8,
          children: [
            for (final e in const {
              'txt': 'TXT',
              'docx': 'DOCX (Word)',
              'zip': 'ZIP (txt+docx)',
            }.entries)
              ChoiceChip(
                label: Text(e.value),
                selected: _outFormat == e.key,
                onSelected: (_) => setState(() => _outFormat = e.key),
              ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Paragraph structure is preserved - titles and order stay in '
          'place. The translation goes straight into the output file.',
          style: TextStyle(fontSize: 13),
        ),
      ]),
      _card('4. Translate & save', [
        FilledButton.icon(
          onPressed: _translating ? null : _translateSave,
          icon: const Icon(Icons.translate),
          label: Text(_translating ? 'Translating...' : 'Translate & save'),
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

  // ---------- Clean UI ----------

  List<Widget> _clCards() {
    return [
      _card('1. Image', [
        Row(children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: _clBusy ? null : _pickCleanImage,
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('Choose image'),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        const Text(
          'Best on single panels with uniform bubbles (white/solid color). '
          'Tap INSIDE a bubble to erase its text.',
          style: TextStyle(fontSize: 13),
        ),
      ]),
      _card('2. Tolerance', [
        Text('Fill tolerance: ${_clTol.round()}'),
        Slider(
          value: _clTol,
          min: 20,
          max: 100,
          divisions: 16,
          label: '${_clTol.round()}',
          onChanged: (v) => setState(() => _clTol = v),
        ),
        const Text(
          'Higher = grabs more shades (bigger fill). Lower = stricter.',
          style: TextStyle(fontSize: 12),
        ),
      ]),
      _card('3. Tap bubbles to erase', [
        if (_clBytes == null)
          const Text('Pick an image first.',
              style: TextStyle(fontSize: 13))
        else
          LayoutBuilder(builder: (ctx, cons) {
            final W = cons.maxWidth;
            final H =
                _clDims[1] == 0 ? 200.0 : W * _clDims[1] / _clDims[0];
            return GestureDetector(
              onTapUp: (d) => _onCleanTap(d, W, H),
              child: SizedBox(
                width: W,
                height: H,
                child: Stack(children: [
                  Image.memory(_clBytes!, fit: BoxFit.fill),
                  if (_clBusy)
                    const Positioned.fill(
                      child: Center(child: CircularProgressIndicator()),
                    ),
                ]),
              ),
            );
          }),
        if (_clSavedWhere != null) ...[
          const SizedBox(height: 8),
          SelectableText('Saved to: $_clSavedWhere',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ]),
      _card('4. Fix & save', [
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: (_clUndo.isEmpty || _clBusy)
                  ? null
                  : () => setState(() {
                        _clBytes = _clUndo.removeLast();
                      }),
              icon: const Icon(Icons.undo),
              label: const Text('Undo'),
            ),
            OutlinedButton.icon(
              onPressed: (_clOriginal == null || _clBusy)
                  ? null
                  : () => setState(() {
                        _clBytes = _clOriginal;
                        _clUndo.clear();
                      }),
              icon: const Icon(Icons.restart_alt),
              label: const Text('Reset'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _clNameCtrl,
          decoration: const InputDecoration(
            labelText: 'File name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: (_clBytes == null || _clBusy) ? null : _saveClean,
          icon: const Icon(Icons.save_alt),
          label: const Text('Save cleaned PNG'),
        ),
      ]),
    ];
  }

  // ---------- Typeset UI ----------

  List<Widget> _tsCards() {
    return [
      _card('1. Image', [
        Row(children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: _tsBusy ? null : _pickTsImage,
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('Choose image'),
            ),
          ),
        ]),
      ]),
      _card('2. Read & translate (AI)', [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _langCodes.keys
              .map((k) => ChoiceChip(
                    label: Text(k),
                    selected: _tsLang == k,
                    onSelected: (_) => setState(() => _tsLang = k),
                  ))
              .toList(),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _tsBusy ? null : _tsRead,
          icon: const Icon(Icons.auto_fix_high),
          label: Text(_tsBusy ? 'Reading panel...' : 'Read & translate'),
        ),
        if (_tsBusy)
          const Padding(
            padding: EdgeInsets.only(top: 12),
            child: LinearProgressIndicator(),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: _tsBusy ? null : _tsAddBox,
          icon: const Icon(Icons.add),
          label: const Text('Add empty box (for missed text)'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Boxes are AI-placed and approximate: drag to move, tap to edit '
          'text/size (or delete).',
          style: TextStyle(fontSize: 12),
        ),
      ]),
      _card('3. Preview & edit', [
        if (_tsBytes == null)
          const Text('Pick an image first.', style: TextStyle(fontSize: 13))
        else
          LayoutBuilder(builder: (ctx, cons) {
            final W = cons.maxWidth;
            final H =
                _tsDims[1] == 0 ? 240.0 : W * _tsDims[1] / _tsDims[0];
            return SizedBox(
              width: W,
              height: H,
              child: Stack(children: [
                Positioned.fill(
                  child: Image.memory(_tsBytes!, fit: BoxFit.fill),
                ),
                for (var i = 0; i < _tsItems.length; i++) _tsBox(i, W, H),
              ]),
            );
          }),
        if (_tsSavedWhere != null) ...[
          const SizedBox(height: 8),
          SelectableText('Saved to: $_tsSavedWhere',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ]),
      _card('4. Export', [
        TextField(
          controller: _tsNameCtrl,
          decoration: const InputDecoration(
            labelText: 'File name',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _tsBusy ? null : _tsExport,
          icon: const Icon(Icons.save_alt),
          label: const Text('Export PNG (pick folder)'),
        ),
      ]),
    ];
  }

  Widget _tsBox(int i, double W, double H) {
    final it = _tsItems[i];
    return Positioned(
      left: (it.x * W).clamp(0.0, W).toDouble(),
      top: (it.y * H).clamp(0.0, H).toDouble(),
      width: (it.w * W).clamp(20.0, W).toDouble(),
      height: (it.h * H).clamp(14.0, H).toDouble(),
      child: GestureDetector(
        onTap: () => _editTsItem(i),
        onPanUpdate: (d) {
          setState(() {
            it.x = (it.x + d.delta.dx / W).clamp(0.0, 1.0).toDouble();
            it.y = (it.y + d.delta.dy / H).clamp(0.0, 1.0).toDouble();
          });
        },
        child: Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.black26),
          ),
          child: Center(
            child: Text(
              it.translated,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.black,
                fontSize:
                    (it.size * it.h * H).clamp(6.0, 200.0).toDouble(),
                height: 1.1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ---------- Game placeholder ----------

  Widget _buildGame() => const GameGate();

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
