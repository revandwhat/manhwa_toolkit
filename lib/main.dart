import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'login_page.dart';

import 'services/clean_service.dart';
import 'services/doc_service.dart';
import 'services/gemini_service.dart';
import 'services/image_service.dart';
import 'services/translate_service.dart';
import 'services/typeset_service.dart';

final themeModeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initSupabaseFromPrefs();
  try {
    final p = await SharedPreferences.getInstance();
    themeModeNotifier.value =
        (p.getString('theme_mode') ?? 'light') == 'dark'
            ? ThemeMode.dark
            : ThemeMode.light;
  } catch (_) {}
  runApp(const ManhwaApp());
}

class ManhwaApp extends StatelessWidget {
  const ManhwaApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) => MaterialApp(
        title: 'RunaTL',
        debugShowCheckedModeBanner: false,
        themeMode: mode,
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1E3A8A),
            surface: Colors.white,
          ),
          scaffoldBackgroundColor: Colors.white,
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF1E3A8A),
            foregroundColor: Colors.white,
            centerTitle: true,
          ),
          cardTheme: const CardThemeData(
            color: Colors.white,
            surfaceTintColor: Colors.white,
          ),
        ),
        darkTheme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1E3A8A),
            brightness: Brightness.dark,
            surface: const Color(0xFF12244A),
          ),
          scaffoldBackgroundColor: const Color(0xFF0B1B3A),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFF0F1E3C),
            foregroundColor: Colors.white,
            centerTitle: true,
          ),
          cardTheme: const CardThemeData(
            color: Color(0xFF12244A),
            surfaceTintColor: Colors.transparent,
          ),
        ),
        home: const RootPage(),
      ),
    );
  }
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});

  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  bool _permAsked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_permAsked) return;
      _permAsked = true;
      try {
        if (!await Permission.manageExternalStorage.isGranted) {
          await Permission.manageExternalStorage.request();
        }
      } catch (_) {}
    });
  }
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
  String? _clPath;
  List<int> _clDims = [0, 0];
  final List<Uint8List> _clUndo = [];
  double _clTol = 55;
  final _clNameCtrl = TextEditingController(text: '[Cleaned] File');
  bool _clBusy = false;
  String? _clSavedWhere;
  bool _clAutofill = true;
  String _clMime = 'image/jpeg';
  List<Stroke> _clStrokes = [];
  bool _clBrush = false;
  Color _clBrushColor = Colors.white;
  double _clBrushSize = 0.02;
  Stroke? _clCurrent;

  Future<void> _pickCleanImage() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = r?.files.single.path;
    if (path == null) return;
    if (!_isImage(path)) {
      _snack('That is not an image.');
      return;
    }
    final imported = await _importCopy(path);
    _clMime = imported.toLowerCase().endsWith('.png') ? 'image/png' : 'image/jpeg';
    try {
      final bytes = await File(imported).readAsBytes();
      final dims = await CleanService.dims(bytes);
      if (!mounted) return;
      setState(() {
        _clOriginal = bytes;
        _clBytes = bytes;
        _clPath = imported;
        _clDims = dims;
        _clUndo.clear();
        _clStrokes = [];
        _clSavedWhere = null;
      });
    } catch (_) {
      _snack('Could not read that image');
    }
  }

  List<double> _clFrac(Offset o, double W, double H) => [
        (o.dx / W).clamp(0.0, 1.0).toDouble(),
        (o.dy / H).clamp(0.0, 1.0).toDouble(),
      ];

  Future<void> _onCleanTap(TapUpDetails d, double dispW, double dispH) async {
    if (_clBrush || !_clAutofill || _clBytes == null || _clBusy || _clDims[0] == 0) return;
    final px = (d.localPosition.dx / dispW * _clDims[0]).round().clamp(0, _clDims[0] - 1);
    final py = (d.localPosition.dy / dispH * _clDims[1]).round().clamp(0, _clDims[1] - 1);
    setState(() => _clBusy = true);
    try {
      final out = await CleanService.clean(_clBytes!, x: px, y: py, tolerance: _clTol.round());
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

  void _clPushUndo() {
    if (_clBytes != null) {
      _clUndo.add(_clBytes!);
      if (_clUndo.length > 5) _clUndo.removeAt(0);
    }
  }

  Future<void> _clAutoOffline() async {
    if (_clPath == null || _clOriginal == null) {
      _snack('Choose an image first');
      return;
    }
    setState(() => _clBusy = true);
    try {
      final out = await CleanService.autoCleanOffline(_clPath!, _clOriginal!);
      if (!mounted) return;
      setState(() {
        _clPushUndo();
        _clBytes = out;
        _clStrokes = [];
      });
      _snack('Offline auto-clean done - brush the leftovers');
    } catch (e) {
      _snack(e.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _clBusy = false);
    }
  }

  Future<void> _runAiClean() async {
    if (_clOriginal == null) {
      _snack('Choose an image first');
      return;
    }
    setState(() => _clBusy = true);
    try {
      final out = await CleanService.aiClean(_clOriginal!, mime: _clMime);
      if (!mounted) return;
      setState(() {
        _clPushUndo();
        _clBytes = out;
        _clStrokes = [];
      });
      _snack('AI clean done');
    } catch (e) {
      final msg = e.toString().replaceFirst('Exception: ', '');
      _snack(msg == 'NO_KEY' ? 'Add a Gemini key (key icon, top right)' : msg);
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
    setState(() => _clBusy = true);
    try {
      Uint8List toSave = _clBytes!;
      if (_clStrokes.isNotEmpty) {
        toSave = await TypesetService.bakeStrokes(_clBytes!, _clStrokes);
      }
      await File(out).writeAsBytes(toSave);
      if (!mounted) return;
      setState(() => _clSavedWhere = out);
      _snack('Done');
    } catch (e) {
      _snack('Save failed: $e');
    } finally {
      if (mounted) setState(() => _clBusy = false);
    }
  }

  // ---------- Typeset (TS) state ----------
  Uint8List? _tsBytes;
  List<int> _tsDims = [0, 0];
  List<BoxItem> _tsItems = [];
  List<Stroke> _tsStrokes = [];
  bool _tsBrush = false;
  Color _tsBrushColor = Colors.white;
  double _tsBrushSize = 0.02;
  Stroke? _tsCurrent;
  bool _tsCrop = false;
  double _cropL = 0, _cropT = 0, _cropR = 0, _cropB = 0;
  bool _tsBusy = false;
  final _tsNameCtrl = TextEditingController(text: '[Typeset] File');
  String? _tsSavedWhere;
  bool _tsTapAdd = true;

  Future<void> _pickTsImage() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = r?.files.single.path;
    if (path == null) return;
    if (!_isImage(path)) {
      _snack('That is not an image.');
      return;
    }
    final imported = await _importCopy(path);
    TypesetService.registerSavedFonts();
    try {
      final bytes = await File(imported).readAsBytes();
      final dims = await CleanService.dims(bytes);
      if (!mounted) return;
      setState(() {
        _tsBytes = bytes;
        _tsDims = dims;
        _tsItems = [];
        _tsStrokes = [];
        _tsSavedWhere = null;
      });
    } catch (_) {
      _snack('Could not read that image');
    }
  }

  List<double> _tsFrac(Offset o, double W, double H) => [
        (o.dx / W).clamp(0.0, 1.0).toDouble(),
        (o.dy / H).clamp(0.0, 1.0).toDouble(),
      ];

  void _tsAddAt(double fx, double fy) {
    if (_tsBytes == null) {
      _snack('Choose an image first');
      return;
    }
    final it = BoxItem(
      text: 'New text',
      x: (fx - 0.2).clamp(0.0, 0.9).toDouble(),
      y: (fy - 0.06).clamp(0.0, 0.9).toDouble(),
    );
    setState(() => _tsItems.add(it));
    _tsEdit(_tsItems.indexOf(it));
  }

  void _tsAddBox() {
    if (_tsBytes == null) {
      _snack('Choose an image first');
      return;
    }
    setState(() => _tsItems.add(BoxItem(text: 'New text')));
  }

  Future<void> _tsApplyCrop() async {
    if (_tsBytes == null) return;
    if (_cropL + _cropR >= 0.98 || _cropT + _cropB >= 0.98) {
      _snack('Crop region too small');
      return;
    }
    setState(() => _tsBusy = true);
    try {
      final out = await TypesetService.cropImage(
          _tsBytes!, Rect.fromLTRB(_cropL, _cropT, 1 - _cropR, 1 - _cropB));
      if (!mounted) return;
      final dims = await CleanService.dims(out);
      setState(() {
        _tsBytes = out;
        _tsDims = dims;
        _tsItems = [];
        _tsStrokes = [];
        _tsCrop = false;
        _cropL = _cropT = _cropR = _cropB = 0;
        _tsSavedWhere = null;
      });
      _snack('Cropped (text boxes reset - add them on the cropped image)');
    } catch (e) {
      _snack('Crop failed: $e');
    } finally {
      if (mounted) setState(() => _tsBusy = false);
    }
  }

  Future<String?> _loadFontDialog() async {
    final c = TextEditingController();
    final pick = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Load custom font'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: c,
              decoration: const InputDecoration(
                hintText: 'https://.../myfont.ttf',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final r = await FilePicker.platform.pickFiles(
                  type: FileType.custom,
                  allowedExtensions: ['ttf', 'otf'],
                );
                final p = r?.files.single.path;
                if (p != null && ctx.mounted) Navigator.pop(ctx, 'file:$p');
              },
              icon: const Icon(Icons.folder_open),
              label: const Text('Pick .ttf / .otf file'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, 'url:${c.text.trim()}'),
              child: const Text('Load URL')),
        ],
      ),
    );
    if (pick == null || pick.isEmpty) return null;
    try {
      if (pick.startsWith('url:')) {
        return await TypesetService.fontFromUrl(pick.substring(4));
      }
      return await TypesetService.fontFromFile(pick.substring(5));
    } catch (e) {
      _snack('Font load failed: $e');
      return null;
    }
  }

  Future<void> _tsEdit(int i) async {
    final it = _tsItems[i];
    final text = TextEditingController(text: it.text);
    var font = it.font;
    var fs = it.fs;
    var color = it.color;
    var bold = it.bold;
    var italic = it.italic;
    var outline = it.outline;
    var outlineColor = it.outlineColor;
    var outlineW = it.outlineW;
    var glow = it.glow;
    var glowColor = it.glowColor;
    var glowR = it.glowR;
    var blur = it.blur;
    var rot = it.rot;
    var gradient = it.gradient;
    var color2 = it.color2;
    var bw = it.w;
    var bh = it.h;

    const palette = [
      Colors.white, Colors.black, Colors.red, Colors.orange,
      Colors.yellow, Colors.green, Colors.cyan, Colors.blue,
      Colors.purple, Colors.pink,
    ];

    late void Function(void Function()) setD;

    Widget swatches(List<Color> cs, Color cur, void Function(Color) on) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final c in cs)
            GestureDetector(
              onTap: () {
                on(c);
                setD(() {});
              },
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: c,
                  shape: BoxShape.circle,
                  border: Border.all(
                      width: cur == c ? 3 : 1,
                      color: cur == c ? Colors.teal : Colors.white24),
                ),
              ),
            ),
        ],
      );
    }

    Widget sl(String label, double v, double min, double max, int div,
        void Function(double) on, {String? extra}) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(extra == null ? label : '$label: $extra',
              style: const TextStyle(fontSize: 12)),
          Slider(
            value: v.clamp(min, max).toDouble(),
            min: min,
            max: max,
            divisions: div,
            label: extra,
            onChanged: (x) {
              on(x);
              setD(() {});
            },
          ),
        ],
      );
    }

    final fams = <String>{
      ...TypesetService.fonts.keys,
      for (final b in _tsItems)
        if (b.font.startsWith('Custom_')) b.font,
      if (font.startsWith('Custom_')) font,
    };

    final ok = await showDialog<Object?>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, sb) {
          setD = sb;
          return AlertDialog(
            title: const Text('Style text'),
            content: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(controller: text, maxLines: 3, autofocus: true),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: fams.contains(font) ? font : 'Default',
                    decoration: const InputDecoration(
                        labelText: 'Font', border: OutlineInputBorder()),
                    items: [
                      for (final f in fams)
                        DropdownMenuItem(
                            value: f,
                            child: Text(f,
                                style: TextStyle(
                                    fontFamily: f.startsWith('Custom_')
                                        ? f
                                        : null,
                                    fontSize: 15))),
                    ],
                    onChanged: (v) {
                      font = v ?? 'Default';
                      setD(() {});
                    },
                  ),
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          final fam = await _loadFontDialog();
                          if (fam != null) {
                            font = fam;
                            setD(() {});
                          }
                        },
                        icon: const Icon(Icons.font_download, size: 18),
                        label: const Text('Custom font',
                            overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ]),
                  sl('Font size', fs, 0.008, 0.12, 40, (v) => fs = v,
                      extra: '${(fs * _tsDims[1]).round()} px'),
                  sl('Box width', bw, 0.05, 1.0, 19, (v) => bw = v),
                  sl('Box height', bh, 0.03, 0.6, 19, (v) => bh = v),
                  const Text('Text color'),
                  swatches(palette, color, (c) => color = c),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Gradient (vertical, color to color 2)'),
                    value: gradient,
                    onChanged: (v) {
                      gradient = v;
                      setD(() {});
                    },
                  ),
                  if (gradient) ...[
                    const Text('Gradient color 2'),
                    swatches(palette, color2, (c) => color2 = c),
                  ],
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Bold'),
                    value: bold,
                    onChanged: (v) {
                      bold = v ?? false;
                      setD(() {});
                    },
                  ),
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Italic'),
                    value: italic,
                    onChanged: (v) {
                      italic = v ?? false;
                      setD(() {});
                    },
                  ),
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Outline'),
                    value: outline,
                    onChanged: (v) {
                      outline = v;
                      setD(() {});
                    },
                  ),
                  if (outline) ...[
                    const Text('Outline color'),
                    swatches(palette, outlineColor, (c) => outlineColor = c),
                    sl('Outline width', outlineW, 1, 8, 7, (v) => outlineW = v),
                  ],
                  SwitchListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Glow'),
                    value: glow,
                    onChanged: (v) {
                      glow = v;
                      setD(() {});
                    },
                  ),
                  if (glow) ...[
                    const Text('Glow color'),
                    swatches(palette, glowColor, (c) => glowColor = c),
                    sl('Glow strength', glowR, 2, 24, 11, (v) => glowR = v),
                  ],
                  sl('Blur', blur, 0, 12, 12, (v) => blur = v),
                  sl('Rotation', rot, -30, 30, 60, (v) => rot = v,
                      extra: '${rot.round()} deg'),
                ],
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              TextButton(
                  onPressed: () => Navigator.pop(ctx, 'del'),
                  child: const Text('Delete',
                      style: TextStyle(color: Colors.red))),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save')),
            ],
          );
        },
      ),
    );
    if (!mounted) return;
    if (ok == 'del') {
      setState(() => _tsItems.removeAt(i));
    } else if (ok == true) {
      setState(() {
        it.text = text.text.trim().isEmpty ? it.text : text.text;
        it.font = font;
        it.fs = fs;
        it.color = color;
        it.bold = bold;
        it.italic = italic;
        it.outline = outline;
        it.outlineColor = outlineColor;
        it.outlineW = outlineW;
        it.glow = glow;
        it.glowColor = glowColor;
        it.glowR = glowR;
        it.blur = blur;
        it.rot = rot;
        it.gradient = gradient;
        it.color2 = color2;
        it.w = bw;
        it.h = bh;
      });
    }
  }

  Future<void> _tsExport() async {
    if (_tsBytes == null) {
      _snack('Choose an image first');
      return;
    }
    if (_tsItems.isEmpty && _tsStrokes.isEmpty) {
      _snack('Nothing to export yet');
      return;
    }
    final dir = await _pickDestFolder('Pick where to save the typeset image');
    if (dir == null) return;
    final base = _sanitize(_tsNameCtrl.text);
    setState(() => _tsBusy = true);
    try {
      final png = await TypesetService.render(_tsBytes!, _tsItems, _tsStrokes);
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

  // ---------- Photo Editor state ----------
  String? _editPath;
  final _editNameCtrl = TextEditingController(text: '[Edited] File');
  bool _editBusy = false;
  String? _editSavedWhere;

  Future<void> _pickEditImage() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.image);
    final path = r?.files.single.path;
    if (path == null) return;
    if (!_isImage(path)) {
      _snack('That is not an image.');
      return;
    }
    final imported = await _importCopy(path);
    setState(() {
      _editPath = imported;
      _editSavedWhere = null;
    });
  }

  Future<void> _openEditor() async {
    if (_editPath == null) {
      _snack('Choose an image first');
      return;
    }
    final bytes = await File(_editPath!).readAsBytes();
    if (!mounted) return;
    Uint8List? result;
    try {
      result = await Navigator.push<Uint8List>(
        context,
        MaterialPageRoute(
          builder: (_) => ProImageEditor.memory(
            bytes,
            callbacks: ProImageEditorCallbacks(
              onImageEditingComplete: (Uint8List out) async =>
                  Navigator.pop(context, out),
            ),
          ),
        ),
      );
    } catch (e) {
      _snack('Editor failed to open: $e');
      return;
    }
    if (result == null) return;
    final dir = await _pickDestFolder('Pick where to save the edited image');
    if (dir == null) return;
    final base = _sanitize(_editNameCtrl.text);
    setState(() => _editBusy = true);
    try {
      final out = await _unique('$dir/$base.png');
      await File(out).writeAsBytes(result);
      if (!mounted) return;
      setState(() => _editSavedWhere = out);
      _snack('Done');
    } catch (e) {
      _snack('Save failed: $e');
    } finally {
      if (mounted) setState(() => _editBusy = false);
    }
  }

  List<Widget> _editorCards() {
    return [
      _card('1. Image', [
        Row(children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: _pickEditImage,
              icon: const Icon(Icons.add_photo_alternate),
              label: const Text('Choose image'),
            ),
          ),
        ]),
        if (_editPath != null) ...[
          const SizedBox(height: 8),
          Text(_editPath!.split('/').last,
              maxLines: 1, overflow: TextOverflow.ellipsis),
        ],
      ]),
      _card('2. Open the full editor', [
        TextField(
          controller: _editNameCtrl,
          decoration: const InputDecoration(
              labelText: 'File name', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _editBusy ? null : _openEditor,
          icon: const Icon(Icons.edit),
          label: const Text('Open editor'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Inside: brush painting (paint bubbles white = cleaning), text '
          'tool with fonts and colors, tune sliders (brightness, contrast, '
          'saturation...), filter presets, crop & rotate, blur, stickers. '
          'Tap Done -> pick a folder -> saved as PNG.',
          style: TextStyle(fontSize: 13),
        ),
      ]),
      if (_editSavedWhere != null)
        _card('Result', [
          SelectableText('Saved to: $_editSavedWhere',
              style: Theme.of(context).textTheme.bodySmall),
        ]),
    ];
  }

  // ---------- UI ----------
  @override
  Widget build(BuildContext context) {
    const titles = ['RunaTL', 'Tools', 'Mini Game'];
    return Scaffold(
      appBar: AppBar(
        title: Text(titles[_tab]),
        centerTitle: true,
        actions: _tab == 1
            ? [
                IconButton(
                    icon: const Icon(Icons.key), onPressed: _askForKey)
              ]
            : (_tab == 2
                ? [
                    IconButton(
                      icon: const Icon(Icons.logout),
                      onPressed: () async {
                        final ok = await showDialog<bool>(
                          context: context,
                          builder: (ctx) => AlertDialog(
                            title: const Text('Log out?'),
                            content: const Text(
                                'Your heroes, coins and progress stay safe on the server.'),
                            actions: [
                              TextButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx, false),
                                  child: const Text('Cancel')),
                              FilledButton(
                                  onPressed: () =>
                                      Navigator.pop(ctx, true),
                                  child: const Text('Log out')),
                            ],
                          ),
                        );
                        if (ok == true) {
                          try {
                            await Supabase
                                .instance.client.auth.signOut();
                          } catch (_) {}
                        }
                      },
                    )
                  ]
                : null),
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

  Future<void> _toggleTheme() async {
    final next = themeModeNotifier.value == ThemeMode.dark
        ? ThemeMode.light
        : ThemeMode.dark;
    themeModeNotifier.value = next;
    final p = await SharedPreferences.getInstance();
    await p.setString('theme_mode', next == ThemeMode.dark ? 'dark' : 'light');
  }

  Widget _runaHelpBanner() {
    final dark = themeModeNotifier.value == ThemeMode.dark;
    return GestureDetector(
      onTap: _toggleTheme,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: dark ? const Color(0xFF12244A) : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFF60A5FA), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF60A5FA).withValues(alpha: 0.5),
              blurRadius: 16,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          children: [
            const Text(
              'RunaHelp',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Color(0xFF60A5FA),
                shadows: [
                  Shadow(color: Color(0xFF60A5FA), blurRadius: 16),
                  Shadow(color: Color(0xFF60A5FA), blurRadius: 30),
                ],
              ),
            ),
            const SizedBox(height: 2),
            Text(
              'tap to switch to ${dark ? 'light' : 'dark'} mode',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHome() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _runaHelpBanner(),
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
        _card('Online game', [
          const Text(
            'Gacha, dungeon, and sharing cards with other players - all '
            'saved online. Create an account or log in.'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => setState(() => _tab = 2),
            icon: const Icon(Icons.sports_esports),
            label: const Text('Log in / Sign up & play'),
          ),
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
                DropdownMenuItem(
                    value: 'Editor',
                    child: Text('Photo Editor - brush, text, filters, crop')),
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
        if (_tool == 'Editor') ..._editorCards(),
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
          'Auto-clean first (offline or AI), then brush the hard leftovers: '
          'transparent bubbles and SFX outside bubbles.',
          style: TextStyle(fontSize: 13),
        ),
      ]),
      _card('2. Auto clean', [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _clBusy ? null : _clAutoOffline,
              icon: const Icon(Icons.offline_bolt),
              label: const Text('Offline (no key)'),
            ),
            OutlinedButton.icon(
              onPressed: _clBusy ? null : _runAiClean,
              icon: const Icon(Icons.auto_fix_high),
              label: const Text('AI (Gemini)'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Offline: on-device OCR finds text and fills it with the '
          'surrounding color (first run downloads OCR models, online once). '
          'AI: whole-panel reconstruction, needs a key.',
          style: TextStyle(fontSize: 12),
        ),
      ]),
      _card('3. Redraw brush (for hard bubbles)', [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Brush mode'),
          subtitle: const Text(
              'Paint over text manually. While ON: pinch-zoom is paused and '
              'tap-autofill is off.'),
          value: _clBrush,
          onChanged: (v) => setState(() => _clBrush = v),
        ),
        const Text('Brush color'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in const [
              Colors.white, Colors.black, Colors.grey, Colors.blueGrey,
            ])
              GestureDetector(
                onTap: () => setState(() => _clBrushColor = c),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                        width: _clBrushColor == c ? 3 : 1,
                        color: _clBrushColor == c
                            ? Colors.teal
                            : Colors.white24),
                  ),
                ),
              ),
          ],
        ),
        Text('Brush size: ${(_clBrushSize * 100).toStringAsFixed(1)}%'),
        Slider(
          value: _clBrushSize,
          min: 0.005,
          max: 0.08,
          divisions: 15,
          label: (_clBrushSize * 100).toStringAsFixed(1),
          onChanged: (v) => setState(() => _clBrushSize = v),
        ),
        Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _clStrokes.isEmpty
                  ? null
                  : () => setState(() {
                        _clStrokes.removeLast();
                      }),
              icon: const Icon(Icons.undo),
              label: const Text('Undo stroke'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _clStrokes.isEmpty
                  ? null
                  : () => setState(() => _clStrokes = []),
              icon: const Icon(Icons.layers_clear),
              label: const Text('Clear strokes'),
            ),
          ),
        ]),
      ]),
      _card('4. Tap-autofill (normal bubbles)', [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Tap to erase (flood fill)'),
          value: _clAutofill,
          onChanged: (v) => setState(() => _clAutofill = v),
        ),
        Text('Fill tolerance: ${_clTol.round()}'),
        Slider(
          value: _clTol,
          min: 20,
          max: 100,
          divisions: 16,
          label: '${_clTol.round()}',
          onChanged: (v) => setState(() => _clTol = v),
        ),
      ]),
      _card('5. Canvas', [
        if (_clBytes == null)
          const Text('Pick an image first.', style: TextStyle(fontSize: 13))
        else
          Stack(children: [
            LayoutBuilder(builder: (ctx, cons) {
              final W = cons.maxWidth;
              final H = _clDims[1] == 0 ? 200.0 : W * _clDims[1] / _clDims[0];
              return InteractiveViewer(
                panEnabled: !_clBrush,
                scaleEnabled: !_clBrush,
                maxScale: 8,
                child: SizedBox(
                  width: W,
                  height: H,
                  child: GestureDetector(
                    onTapUp: (d) => _onCleanTap(d, W, H),
                    onPanStart: _clBrush
                        ? (d) {
                            final f = _clFrac(d.localPosition, W, H);
                            setState(() {
                              _clCurrent = Stroke(
                                  pts: [f],
                                  color: _clBrushColor,
                                  widthFrac: _clBrushSize);
                              _clStrokes.add(_clCurrent!);
                            });
                          }
                        : null,
                    onPanUpdate: _clBrush
                        ? (d) {
                            setState(() {
                              _clCurrent?.pts
                                  .add(_clFrac(d.localPosition, W, H));
                            });
                          }
                        : null,
                    child: Stack(children: [
                      Positioned.fill(
                          child: Image.memory(_clBytes!, fit: BoxFit.fill)),
                      Positioned.fill(
                        child: CustomPaint(
                          painter: StrokesPainter(_clStrokes),
                          size: Size(W, H),
                        ),
                      ),
                    ]),
                  ),
                ),
              );
            }),
            if (_clBusy)
              const Positioned.fill(
                child: Center(child: CircularProgressIndicator()),
              ),
          ]),
        if (_clSavedWhere != null) ...[
          const SizedBox(height: 8),
          SelectableText('Saved to: $_clSavedWhere',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ]),
      _card('6. Save', [
        TextField(
          controller: _clNameCtrl,
          decoration: const InputDecoration(
              labelText: 'File name', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: (_clBytes == null || _clBusy) ? null : _saveClean,
          icon: const Icon(Icons.save_alt),
          label: const Text('Save cleaned PNG'),
        ),
        const SizedBox(height: 8),
        const Text('Brush strokes are baked into the saved PNG.',
            style: TextStyle(fontSize: 12)),
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
      _card('2. Brush (cover original text)', [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Brush mode'),
          subtitle: const Text('Paint over the text you want to replace.'),
          value: _tsBrush,
          onChanged: (v) => setState(() => _tsBrush = v),
        ),
        const Text('Brush color'),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in const [
              Colors.white, Colors.black, Colors.grey, Colors.blueGrey,
            ])
              GestureDetector(
                onTap: () => setState(() => _tsBrushColor = c),
                child: Container(
                  width: 26,
                  height: 26,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                        width: _tsBrushColor == c ? 3 : 1,
                        color: _tsBrushColor == c
                            ? Colors.teal
                            : Colors.white24),
                  ),
                ),
              ),
          ],
        ),
        Text('Brush size: ${(_tsBrushSize * 100).toStringAsFixed(1)}%'),
        Slider(
          value: _tsBrushSize,
          min: 0.005,
          max: 0.08,
          divisions: 15,
          label: (_tsBrushSize * 100).toStringAsFixed(1),
          onChanged: (v) => setState(() => _tsBrushSize = v),
        ),
      ]),
      _card('3. Crop', [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Crop mode'),
          subtitle: const Text('Trim the image edges. Resets boxes/strokes '
              'when applied.'),
          value: _tsCrop,
          onChanged: (v) => setState(() => _tsCrop = v),
        ),
        if (_tsCrop) ...[
          _cropSlider('Left', _cropL, (v) => _cropL = v),
          _cropSlider('Top', _cropT, (v) => _cropT = v),
          _cropSlider('Right', _cropR, (v) => _cropR = v),
          _cropSlider('Bottom', _cropB, (v) => _cropB = v),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _tsBusy ? null : _tsApplyCrop,
            icon: const Icon(Icons.crop),
            label: const Text('Apply crop'),
          ),
        ],
      ]),
      _card('4. Add & style text', [
        Row(children: [
          Expanded(
            child: FilledButton.tonalIcon(
              onPressed: _tsBusy ? null : _tsAddBox,
              icon: const Icon(Icons.text_fields),
              label: const Text('Add text box'),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Tap image to place text'),
          subtitle: const Text('A box appears where you tap and the style '
              'editor opens'),
          value: _tsTapAdd,
          onChanged: (v) => setState(() => _tsTapAdd = v),
        ),
        const Text(
          'Tap a box to edit: text, custom font (URL or .ttf), size, color, '
          'gradient, bold/italic, outline, glow, blur, rotation.',
          style: TextStyle(fontSize: 12),
        ),
      ]),
      _card('5. Preview', [
        if (_tsBytes == null)
          const Text('Pick an image first.', style: TextStyle(fontSize: 13))
        else
          LayoutBuilder(builder: (ctx, cons) {
            final W = cons.maxWidth;
            final H = _tsDims[1] == 0 ? 240.0 : W * _tsDims[1] / _tsDims[0];
            return SizedBox(
              width: W,
              height: H,
              child: GestureDetector(
                onTapUp: (!_tsBrush && _tsTapAdd && !_tsCrop)
                    ? (d) => _tsAddAt(d.localPosition.dx / W,
                        d.localPosition.dy / H)
                    : null,
                onPanStart: _tsBrush
                    ? (d) {
                        final f = _tsFrac(d.localPosition, W, H);
                        setState(() {
                          _tsCurrent = Stroke(
                              pts: [f],
                              color: _tsBrushColor,
                              widthFrac: _tsBrushSize);
                          _tsStrokes.add(_tsCurrent!);
                        });
                      }
                    : null,
                onPanUpdate: _tsBrush
                    ? (d) {
                        setState(() {
                          _tsCurrent?.pts.add(_tsFrac(d.localPosition, W, H));
                        });
                      }
                    : null,
                child: Stack(children: [
                  Positioned.fill(
                      child: Image.memory(_tsBytes!, fit: BoxFit.fill)),
                  Positioned.fill(
                    child: CustomPaint(
                      painter: StrokesPainter(_tsStrokes),
                      size: Size(W, H),
                    ),
                  ),
                  IgnorePointer(
                    ignoring: _tsBrush || _tsCrop,
                    child: Stack(children: [
                      for (var i = 0; i < _tsItems.length; i++)
                        _tsBox(i, W, H),
                    ]),
                  ),
                  if (_tsCrop) ..._cropOverlay(W, H),
                ]),
              ),
            );
          }),
        if (_tsSavedWhere != null) ...[
          const SizedBox(height: 8),
          SelectableText('Saved to: $_tsSavedWhere',
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ]),
      _card('6. Export', [
        TextField(
          controller: _tsNameCtrl,
          decoration: const InputDecoration(
              labelText: 'File name', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _tsBusy ? null : _tsExport,
          icon: const Icon(Icons.save_alt),
          label: const Text('Export PNG (pick folder)'),
        ),
        const SizedBox(height: 8),
        const Text(
          'Brush strokes and styled text are baked in exactly. Custom fonts '
          'persist and work offline; Google Fonts need internet once.',
          style: TextStyle(fontSize: 12),
        ),
      ]),
    ];
  }

  Widget _cropSlider(String label, double v, void Function(double) on) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label inset: ${(v * 100).round()}%'),
        Slider(
          value: v,
          min: 0,
          max: 0.45,
          divisions: 45,
          label: '${(v * 100).round()}%',
          onChanged: (x) => setState(() => on(x)),
        ),
      ],
    );
  }

  List<Widget> _cropOverlay(double W, double H) {
    return [
      Positioned(
        left: 0, top: 0,
        width: W * _cropL, height: H,
        child: Container(color: Colors.black45),
      ),
      Positioned(
        left: W * (1 - _cropR), top: 0,
        width: W * _cropR, height: H,
        child: Container(color: Colors.black45),
      ),
      Positioned(
        left: W * _cropL, top: 0,
        width: W * (1 - _cropL - _cropR), height: H * _cropT,
        child: Container(color: Colors.black45),
      ),
      Positioned(
        left: W * _cropL, top: H * (1 - _cropB),
        width: W * (1 - _cropL - _cropR), height: H * _cropB,
        child: Container(color: Colors.black45),
      ),
    ];
  }

  Widget _tsBox(int i, double W, double H) {
    final it = _tsItems[i];
    final fontPx = (it.fs * H).clamp(6.0, 300.0).toDouble();
    final base = (TypesetService.fonts[it.font] ??
            TypesetService.fonts['Default']!)()
        .copyWith(
      color: it.color,
      fontSize: fontPx,
      fontWeight: it.bold ? FontWeight.bold : FontWeight.normal,
      fontStyle: it.italic ? FontStyle.italic : FontStyle.normal,
      height: 1.1,
    );
    final shadows = <Shadow>[
      if (it.glow)
        Shadow(
            color: it.glowColor,
            blurRadius: it.glowR * (_tsDims[0] > 0 ? W / _tsDims[0] : 1)),
      if (it.outline)
        for (final o in const [
          Offset(1, 0), Offset(-1, 0), Offset(0, 1), Offset(0, -1),
          Offset(1, 1), Offset(-1, -1), Offset(1, -1), Offset(-1, 1),
        ])
          Shadow(color: it.outlineColor, offset: o * (it.outlineW / 2)),
    ];
    Widget txt = Text(
      it.text,
      textAlign: TextAlign.center,
      style: base.copyWith(shadows: shadows),
    );
    if (it.gradient) {
      txt = ShaderMask(
        shaderCallback: (b) => LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [it.color, it.color2],
        ).createShader(b),
        blendMode: BlendMode.srcIn,
        child: txt,
      );
    }
    if (it.rot != 0) {
      txt = Transform.rotate(
          angle: it.rot * 3.141592653589793 / 180,
          alignment: Alignment.center,
          child: txt);
    }
    return Positioned(
      left: (it.x * W).clamp(0.0, W).toDouble(),
      top: (it.y * H).clamp(0.0, H).toDouble(),
      width: (it.w * W).clamp(20.0, W).toDouble(),
      height: (it.h * H).clamp(14.0, H).toDouble(),
      child: GestureDetector(
        onTap: () => _tsEdit(i),
        onPanUpdate: (d) {
          setState(() {
            it.x = (it.x + d.delta.dx / W).clamp(0.0, 1.0).toDouble();
            it.y = (it.y + d.delta.dy / H).clamp(0.0, 1.0).toDouble();
          });
        },
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            border: Border.all(
                color: Colors.cyan.withValues(alpha: 0.6), width: 1),
          ),
          child: txt,
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
