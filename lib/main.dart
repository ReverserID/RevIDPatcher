import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core/axml.dart';
import 'core/patcher.dart';
import 'core/template.dart';

const kPage = Color(0xFF0E1016);
const kInk = Color(0xFF12141C);
const kCard = Color(0xFF191D29);
const kCard2 = Color(0xFF232838);
const kOnCard = Color(0xFFF2F3F8);
const kOnCardMute = Color(0xFF8A8D9E);
const kLine = Color(0xFF282C3A);
const kBrandRed = Color(0xFFED2E26);
const kGood = Color(0xFF4FD6A6);

const _phases = ['Decoding', 'Patching', 'Building', 'Signing'];

void main() => runApp(const ReverserApp());

class ReverserApp extends StatelessWidget {
  const ReverserApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RevID Patcher',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: kPage,
        colorScheme: const ColorScheme.dark(surface: kPage, primary: kOnCard),
        fontFamily: 'Roboto',
      ),
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
  List<PatchTemplate> _templates = [];
  bool _loading = true;
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    Patcher.loadTemplates().then((t) {
      if (mounted) {
        setState(() {
          _templates = t;
          _loading = false;
        });
      }
      _sync();
    });
  }

  Future<void> _sync() async {
    if (_syncing) return;
    setState(() => _syncing = true);
    try {
      final t = await Patcher.syncTemplates();
      if (mounted) setState(() => _templates = t);
    } catch (_) {

    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: kPage,
      ),
      child: Scaffold(
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: _sync,
            color: kOnCard,
            backgroundColor: kCard,
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(child: topBar()),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 20),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      _hero(),
                      const SizedBox(height: 14),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 2, 4, 10),
                        child: Row(
                          children: [
                            cardLabel('AVAILABLE PATCHES'),
                            const Spacer(),
                            if (_syncing)
                              const SizedBox(
                                width: 13,
                                height: 13,
                                child: CircularProgressIndicator(
                                    strokeWidth: 1.6, color: kOnCardMute),
                              ),
                          ],
                        ),
                      ),
                    if (_loading)
                      const Padding(
                        padding: EdgeInsets.only(top: 40),
                        child: Center(
                          child: SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: kOnCardMute),
                          ),
                        ),
                      )
                    else if (_templates.isEmpty)
                      darkCard(child: mutedOnCard('No patches in the repo yet.'))
                    else
                      ...List.generate(_templates.length, (i) {
                        return Padding(
                          padding: EdgeInsets.only(
                              bottom: i == _templates.length - 1 ? 0 : 12),
                          child: _catalogCard(_templates[i]),
                        );
                      }),
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _hero() => Container(
        height: 118,
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: kLine),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Positioned.fill(child: CustomPaint(painter: _FrondPainter())),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('R E V E R S E R . I D',
                      style: TextStyle(
                          color: kOnCard,
                          fontSize: 13,
                          letterSpacing: 4,
                          fontWeight: FontWeight.w300)),
                  const SizedBox(height: 7),
                  Text('Patch any APK on-device — no PC, no root.',
                      style: TextStyle(
                          color: kOnCard.withValues(alpha: 0.55),
                          fontSize: 12,
                          fontWeight: FontWeight.w300)),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _catalogCard(PatchTemplate t) {
    final maxRules = t.variants.isEmpty
        ? 0
        : t.variants.map((v) => v.patches.length).reduce(math.max);
    return Material(
      color: kCard,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => PatchDetailPage(template: t)),
        ),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: kLine),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.info.name,
                        style: const TextStyle(
                            color: kOnCard,
                            fontSize: 17,
                            fontWeight: FontWeight.w400)),
                    const SizedBox(height: 3),
                    Text(t.targetPackage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: kOnCardMute,
                            fontSize: 12,
                            fontWeight: FontWeight.w300)),
                    if (t.info.description.isNotEmpty) ...[
                      const SizedBox(height: 9),
                      Text(t.info.description,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              color: kOnCardMute,
                              fontSize: 12.5,
                              height: 1.5,
                              fontWeight: FontWeight.w300)),
                    ],
                    const SizedBox(height: 11),
                    Row(
                      children: [
                        if (t.info.versions != null) ...[
                          _chip('v ${t.info.versions}'),
                          const SizedBox(width: 8),
                        ],
                        _chip('$maxRules rules'),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              const Padding(
                padding: EdgeInsets.only(top: 2),
                child: Icon(Icons.chevron_right, color: kOnCardMute, size: 22),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: kCard2,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(t,
            style: const TextStyle(
                color: kOnCardMute,
                fontSize: 11,
                letterSpacing: 0.3,
                fontWeight: FontWeight.w400)),
      );
}

class PatchDetailPage extends StatefulWidget {
  final PatchTemplate template;
  const PatchDetailPage({super.key, required this.template});
  @override
  State<PatchDetailPage> createState() => _PatchDetailPageState();
}

class _PatchDetailPageState extends State<PatchDetailPage> {
  String? _apkPath;
  ApkMeta? _meta;
  bool _busy = false;
  int _phase = 0;
  String? _output;
  String? _error;
  int _applied = 0, _skipped = 0;
  final _scroll = ScrollController();
  final List<String> _log = [];
  Stopwatch? _sw;

  PatchTemplate get t => widget.template;
  bool get _compatible =>
      _meta != null && t.compatible(_meta!.package, _meta!.versionName);

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 450), curve: Curves.easeOut);
      }
    });
  }

  void _onLog(String l) {
    const marks = {
      'decoding': 0,
      'applying': 1,
      'rebuilding': 2,
      'signing': 3,
      'done': 4,
    };
    if (!mounted) return;
    final el = _sw == null ? '' : '[+${(_sw!.elapsedMilliseconds / 1000).toStringAsFixed(1)}s] ';
    setState(() {
      _log.add('$el$l');
      if (_log.length > 300) _log.removeRange(0, _log.length - 300);
      final s = l.toLowerCase();
      for (final e in marks.entries) {
        if (s.startsWith(e.key)) {
          _phase = e.value;
          break;
        }
      }
    });
    _scrollToEnd();
  }

  Future<void> _loadApk(String path) async {
    setState(() {
      _apkPath = path;
      _meta = null;
      _output = null;
      _error = null;
    });
    final meta = await Patcher.readMeta(path);
    if (!mounted) return;
    setState(() => _meta = meta);
  }

  Future<void> _pickApk() async {
    final res = await FilePicker.platform.pickFiles(
        type: FileType.custom, allowedExtensions: ['apk']);
    final path = res?.files.single.path;
    if (path != null) _loadApk(path);
  }

  Future<void> _scanDownload() async {
    if (Platform.isAndroid) await Permission.manageExternalStorage.request();
    final dirs = ['/sdcard/Download', '/sdcard/Download/ReverserID'];
    final found = <String>[];
    for (final d in dirs) {
      final dir = Directory(d);
      if (await dir.exists()) {
        await for (final e in dir.list()) {
          if (e is File && e.path.toLowerCase().endsWith('.apk')) {
            found.add(e.path);
          }
        }
      }
    }
    found.sort();
    if (!mounted) return;
    if (found.isEmpty) {
      setState(() => _error = 'No APKs found in Download.');
      return;
    }
    showModalBottomSheet(
      context: context,
      backgroundColor: kCard,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(24, 4, 24, 12),
              child: Text('SELECT APK',
                  style: TextStyle(
                      color: kOnCardMute,
                      fontSize: 12,
                      letterSpacing: 3,
                      fontWeight: FontWeight.w500)),
            ),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                padding: const EdgeInsets.only(bottom: 8),
                itemCount: found.length,
                separatorBuilder: (_, i) => const Divider(
                    height: 1, color: kLine, indent: 24, endIndent: 24),
                itemBuilder: (_, i) => ListTile(
                  title: Text(p.basename(found[i]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: kOnCard, fontWeight: FontWeight.w400)),
                  trailing: const Icon(Icons.arrow_forward,
                      size: 18, color: kOnCardMute),
                  onTap: () {
                    Navigator.pop(ctx);
                    _loadApk(found[i]);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _getOriginal() async {
    final src = t.info.source;
    if (src == null) return;
    final uri = Uri.tryParse(src);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _useInstalled() async {
    try {
      final path = await Patcher.installedApk(t.targetPackage);
      await _loadApk(path);
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            '${t.targetPackage} is not installed, or its APK can\'t be read.');
      }
    }
  }

  Future<void> _startPatch() async {
    if (_busy || _apkPath == null || !_compatible) return;
    setState(() {
      _busy = true;
      _phase = 0;
      _output = null;
      _error = null;
      _log.clear();
      _sw = Stopwatch()..start();
    });
    _onLog('reverser.id patcher · engine v1');
    _onLog('patch: ${t.id}');
    _scrollToEnd();
    try {
      final docs = await getApplicationSupportDirectory();
      final outDir = Platform.isAndroid
          ? Directory('/sdcard/Download/ReverserID')
          : Directory(docs.path);
      await outDir.create(recursive: true);
      final stem = p.basenameWithoutExtension(_apkPath!);
      final out = p.join(outDir.path, '$stem-${t.id}.apk');
      final res = await Patcher.patch(
        apkPath: _apkPath!,
        template: t,
        outPath: out,
        log: _onLog,
      );
      if (!mounted) return;
      setState(() {
        _output = res.outPath;
        _applied = res.applied;
        _skipped = res.skipped;
        _phase = 4;
      });
      _onLog('DONE · $_applied applied, $_skipped skipped');
      _onLog('out: ${p.basename(res.outPath)}');
      _scrollToEnd();
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e');
        _onLog('FAILED · $e');
        _scrollToEnd();
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _install() async {
    if (_output == null) return;
    if (Platform.isAndroid) await Permission.requestInstallPackages.request();
    await OpenFilex.open(_output!);
  }

  @override
  Widget build(BuildContext context) {
    final showProgress = _busy || _output != null || _error != null;
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: kPage,
      ),
      child: Scaffold(
        body: SafeArea(
          child: CustomScrollView(
            controller: _scroll,
            slivers: [
              SliverToBoxAdapter(child: _detailBar()),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    _aboutCard(),
                    const SizedBox(height: 11),
                    _sourceCard(),
                    const SizedBox(height: 11),
                    SizedBox(
                      width: double.infinity,
                      child: pillButton(
                          _busy ? 'Patching…' : 'Patch',
                          (_busy || !_compatible) ? null : _startPatch,
                          big: true),
                    ),
                    if (showProgress) ...[
                      const SizedBox(height: 11),
                      _progressCard(),
                    ],
                  ]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _detailBar() => Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 14, 8),
        child: Row(
          children: [
            IconButton(
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.arrow_back, color: kOnCard, size: 22),
            ),
            const Text('Patch detail',
                style: TextStyle(
                    color: kOnCard,
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 0.3)),
          ],
        ),
      );

  Widget _aboutCard() => darkCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            cardLabel('PATCH'),
            const SizedBox(height: 12),
            Text(t.info.name,
                style: const TextStyle(
                    color: kOnCard,
                    fontSize: 22,
                    fontWeight: FontWeight.w300,
                    letterSpacing: -0.3)),
            const SizedBox(height: 4),
            Text(t.targetPackage,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: kOnCardMute, fontSize: 12.5, fontWeight: FontWeight.w300)),
            if (t.info.description.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(t.info.description,
                  style: const TextStyle(
                      color: kOnCardMute,
                      fontSize: 13,
                      height: 1.55,
                      fontWeight: FontWeight.w300)),
            ],
            const SizedBox(height: 14),
            Row(children: [
              if (t.info.versions != null) ...[
                _metaChip(Icons.layers_outlined, t.info.versions!),
                const SizedBox(width: 8),
              ],
              _metaChip(Icons.person_outline, t.info.author),
            ]),
          ],
        ),
      );

  Widget _metaChip(IconData i, String t) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
            color: kCard2, borderRadius: BorderRadius.circular(999)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(i, size: 13, color: kOnCardMute),
          const SizedBox(width: 6),
          Text(t,
              style: const TextStyle(
                  color: kOnCardMute, fontSize: 11.5, fontWeight: FontWeight.w400)),
        ]),
      );

  Widget _sourceCard() => darkCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            cardLabel('SOURCE APK'),
            const SizedBox(height: 12),
            if (_meta == null)
              Text('Pick the app\'s APK, or get the original to patch.',
                  style: TextStyle(
                      color: kOnCard.withValues(alpha: 0.55),
                      fontSize: 13.5,
                      fontWeight: FontWeight.w300))
            else
              _selectedApk(),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: ghostButton('Pick file', Icons.folder_open_outlined,
                      _busy ? null : _pickApk),
                ),
                if (Platform.isAndroid) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: ghostButton(
                        'Scan', Icons.south_outlined, _busy ? null : _scanDownload),
                  ),
                ],
              ],
            ),
            if (Platform.isAndroid) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ghostButton('Use installed app',
                    Icons.phone_android_outlined, _busy ? null : _useInstalled),
              ),
            ],
            if (t.info.source != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ghostButton('Get original app', Icons.public_outlined,
                    _busy ? null : _getOriginal),
              ),
            ],
          ],
        ),
      );

  Widget _selectedApk() {
    final ok = _compatible;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: kCard2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
            color: ok ? kGood.withValues(alpha: 0.4) : kBrandRed.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(ok ? Icons.check_circle_outline : Icons.error_outline,
              size: 20, color: ok ? kGood : kBrandRed),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_meta!.package,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        color: kOnCard, fontSize: 14, fontWeight: FontWeight.w400)),
                const SizedBox(height: 2),
                Text(
                    ok
                        ? 'v${_meta!.versionName} · ready to patch'
                        : 'v${_meta!.versionName} · not supported by this patch',
                    style: const TextStyle(
                        color: kOnCardMute, fontSize: 12, fontWeight: FontWeight.w300)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _progressCard() {
    final done = _phase >= 4 && _output != null;
    final failed = _error != null;
    final progress = done ? 1.0 : _phase / 4;
    final label =
        failed ? 'Failed' : (done ? 'Done' : _phases[_phase.clamp(0, 3)]);
    return darkCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          cardLabel(
              done ? 'PATCH COMPLETE' : (failed ? 'PATCH FAILED' : 'PATCHING')),
          const SizedBox(height: 14),
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: progress),
              duration: const Duration(milliseconds: 550),
              curve: Curves.easeOutCubic,
              builder: (_, v, child) => SizedBox(
                width: 148,
                height: 148,
                child: CustomPaint(
                  painter: _RingPainter(v, danger: failed),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (done)
                          const Icon(Icons.check, color: kOnCard, size: 32)
                        else if (failed)
                          const Icon(Icons.close, color: kBrandRed, size: 32)
                        else
                          Text('${(_phase / 4 * 100).round()}%',
                              style: const TextStyle(
                                  color: kOnCard,
                                  fontSize: 26,
                                  fontWeight: FontWeight.w200)),
                        const SizedBox(height: 5),
                        Text(label,
                            style: const TextStyle(
                                color: kOnCardMute,
                                fontSize: 13,
                                letterSpacing: 1,
                                fontWeight: FontWeight.w400)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          if (!done && !failed)
            Center(
              child: Text('Step ${(_phase + 1).clamp(1, 4)} of 4',
                  style: const TextStyle(
                      color: kOnCardMute, fontSize: 12, letterSpacing: 1)),
            ),
          if (_log.isNotEmpty) ...[
            const SizedBox(height: 16),
            _terminal(),
          ],
          if (done) ...[
            Text(p.basename(_output!),
                style: const TextStyle(
                    color: kOnCard, fontSize: 15, fontWeight: FontWeight.w400)),
            const SizedBox(height: 3),
            Text('$_applied applied · $_skipped skipped',
                style: const TextStyle(
                    color: kOnCardMute, fontSize: 12.5, fontWeight: FontWeight.w300)),
            const SizedBox(height: 14),
            SizedBox(
                width: double.infinity,
                child: pillButton('Install', _install, big: true)),
          ],
          if (failed)
            Text(_error!,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: kOnCardMute, fontSize: 12.5, height: 1.5)),
        ],
      ),
    );
  }

  Widget _terminal() => Container(
        decoration: BoxDecoration(
          color: const Color(0xFF0A0C11),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kLine),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: kLine)),
              ),
              child: Row(
                children: [
                  _dot(const Color(0xFFFF5F57)),
                  const SizedBox(width: 6),
                  _dot(const Color(0xFFFEBC2E)),
                  const SizedBox(width: 6),
                  _dot(kGood),
                  const Spacer(),
                  const Text('reverser@patcher: ~',
                      style: TextStyle(
                          color: kOnCardMute,
                          fontFamily: 'monospace',
                          fontSize: 11)),
                ],
              ),
            ),
            SizedBox(
              height: 168,
              child: ListView(
                reverse: true,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                children: [
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.only(top: 2),
                      child: Text('█',
                          style: TextStyle(
                              color: kGood,
                              fontFamily: 'monospace',
                              fontSize: 12)),
                    ),
                  for (final line in _log.reversed) _logLine(line),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _dot(Color c) => Container(
      width: 9,
      height: 9,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle));

  Widget _logLine(String raw) {
    final low = raw.toLowerCase();
    Color color;
    String glyph;
    if (low.contains('failed')) {
      color = const Color(0xFFFF6B61);
      glyph = '✗';
    } else if (low.contains('done') || low.trimLeft().contains('ok [')) {
      color = kGood;
      glyph = '✓';
    } else if (low.contains('skip')) {
      color = const Color(0xFFE2B341);
      glyph = '•';
    } else if (raw.contains('+ ') || low.contains('apktool') || low.contains('apksigner')) {
      color = const Color(0xFF7FD1FF);
      glyph = '\$';
    } else {
      color = kOnCardMute;
      glyph = '›';
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1.5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 14,
            child: Text(glyph,
                style: TextStyle(
                    color: color, fontFamily: 'monospace', fontSize: 11.5)),
          ),
          Expanded(
            child: Text(raw,
                style: TextStyle(
                    color: color.withValues(alpha: 0.95),
                    fontFamily: 'monospace',
                    fontSize: 11.5,
                    height: 1.45)),
          ),
        ],
      ),
    );
  }
}

Widget topBar() => Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 14, 8),
      child: Row(
        children: [
          Image.asset('assets/brand/logo.png',
              width: 28, height: 28, filterQuality: FilterQuality.medium),
          const SizedBox(width: 10),
          const Text('reverser.id',
              style: TextStyle(
                  color: kOnCard,
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: kLine),
            ),
            child: const Text('PATCHER',
                style: TextStyle(
                    color: kOnCardMute,
                    fontSize: 10,
                    letterSpacing: 2,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );

Widget cardLabel(String t) => Text(t,
    style: const TextStyle(
        color: kOnCardMute,
        fontSize: 12,
        letterSpacing: 3,
        fontWeight: FontWeight.w500));

Widget darkCard({required Widget child}) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: kLine),
      ),
      child: child,
    );

Widget mutedOnCard(String t) => Text(t,
    style: const TextStyle(
        color: kOnCardMute, fontSize: 14, fontWeight: FontWeight.w300));

Widget ghostButton(String label, IconData icon, VoidCallback? onTap) => Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          height: 46,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
                color: onTap == null ? kLine.withValues(alpha: 0.4) : kLine),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: onTap == null ? kOnCardMute : kOnCard),
              const SizedBox(width: 9),
              Text(label,
                  style: TextStyle(
                      color: onTap == null ? kOnCardMute : kOnCard,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w400)),
            ],
          ),
        ),
      ),
    );

Widget pillButton(String label, VoidCallback? onTap, {bool big = false}) =>
    Material(
      color: onTap == null ? kCard2 : kOnCard,
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: big ? 50 : 42,
          padding: EdgeInsets.symmetric(horizontal: big ? 24 : 22),
          alignment: Alignment.center,
          child: Text(label,
              style: TextStyle(
                  color: onTap == null ? kOnCardMute : kInk,
                  fontSize: big ? 16 : 14.5,
                  fontWeight: FontWeight.w500)),
        ),
      ),
    );

class _FrondPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final origin = Offset(size.width * 0.78, size.height * 0.1);
    final rib = Paint()
      ..color = kOnCard.withValues(alpha: 0.10)
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final leaf = Paint()
      ..color = kOnCard.withValues(alpha: 0.07)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final a in [2.5, 2.15, 1.8]) {
      final dir = Offset(math.cos(a), math.sin(a));
      final len = size.width * 0.95;
      final end = origin + dir * len;
      final ctrl = origin + dir * (len * 0.5) + const Offset(0, 40);
      final path = Path()
        ..moveTo(origin.dx, origin.dy)
        ..quadraticBezierTo(ctrl.dx, ctrl.dy, end.dx, end.dy);
      canvas.drawPath(path, rib);
      for (double tt = 0.12; tt < 0.95; tt += 0.07) {
        final base = _quad(origin, ctrl, end, tt);
        final tan = _quad(origin, ctrl, end, tt + 0.01) - base;
        final n = tan / tan.distance;
        final norm = Offset(-n.dy, n.dx);
        final ll = 34.0 * (1 - tt);
        canvas.drawLine(base, base + norm * ll, leaf);
        canvas.drawLine(base, base - norm * ll, leaf);
      }
    }

    final dot = Paint()..color = kOnCard.withValues(alpha: 0.06);
    for (double y = size.height * 0.5; y < size.height; y += 16) {
      for (double x = 6; x < size.width * 0.45; x += 16) {
        canvas.drawCircle(Offset(x, y), 1.1, dot);
      }
    }
  }

  Offset _quad(Offset a, Offset b, Offset c, double t) {
    final u = 1 - t;
    return a * (u * u) + b * (2 * u * t) + c * (t * t);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class _RingPainter extends CustomPainter {
  final double progress;
  final bool danger;
  _RingPainter(this.progress, {this.danger = false});

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.width / 2 - 8;
    const start = -math.pi / 2;

    const dots = 60;
    final track = Paint()..color = kOnCard.withValues(alpha: 0.14);
    for (int i = 0; i < dots; i++) {
      final a = start + i / dots * 2 * math.pi;
      canvas.drawCircle(c + Offset(math.cos(a), math.sin(a)) * r, 1.4, track);
    }

    final arc = Paint()
      ..color = danger ? kBrandRed.withValues(alpha: 0.8) : kOnCard
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), start,
        2 * math.pi * progress.clamp(0, 1), false, arc);

    if (progress > 0 && progress < 1 && !danger) {
      final a = start + 2 * math.pi * progress;
      final knob = c + Offset(math.cos(a), math.sin(a)) * r;
      canvas.drawCircle(knob, 6, Paint()..color = kOnCard);
      canvas.drawCircle(knob, 3, Paint()..color = kCard);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.danger != danger;
}
