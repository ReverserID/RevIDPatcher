import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart'
    show rootBundle, AssetManifest, MethodChannel, PlatformException;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;

import 'axml.dart';
import 'template.dart';

typedef LogSink = void Function(String line);

class Tools {
  final String apktool;
  final String apksigner;
  final String keystore;
  final String home;
  final String tmp;
  final String opt;
  Tools(this.apktool, this.apksigner, this.keystore, this.home, this.tmp,
      this.opt);
}

class PatchResult {
  final String outPath;
  final String templateId;
  final int applied;
  final int skipped;
  PatchResult(this.outPath, this.templateId, this.applied, this.skipped);
}

class Patcher {
  static const _ch = MethodChannel('id.reverser/patch');
  static const _repoRaw =
      'https://raw.githubusercontent.com/ReverserID/reverserid-patches/master';

  static Future<Directory> _work() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory(p.join(base.path, 'rid'));
    await d.create(recursive: true);
    return d;
  }

  static Future<String> _extractAsset(String asset, String destName) async {
    final base = await _work();
    final tools = Directory(p.join(base.path, 'tools'));
    await tools.create(recursive: true);
    final dest = File(p.join(tools.path, destName));
    if (!await dest.exists()) {
      final data = await rootBundle.load(asset);
      await dest.writeAsBytes(data.buffer.asUint8List(
          data.offsetInBytes, data.lengthInBytes));
    }
    return dest.path;
  }

  static Future<Tools> ensureTools() async {
    final base = await _work();
    final home = Directory(p.join(base.path, 'home'));
    final tmp = Directory(p.join(base.path, 'tmp'));
    final opt = Directory(p.join(base.path, 'dexopt'));
    for (final d in [home, tmp, opt]) {
      await d.create(recursive: true);
    }

    final apktool = Platform.isAndroid
        ? await _extractAsset('assets/tools/apktool-rid.jar', 'apktool-rid.jar')
        : await _extractAsset('assets/tools/apktool.jar', 'apktool.jar');
    return Tools(
      apktool,
      await _extractAsset('assets/tools/apksigner.zip', 'apksigner.zip'),
      await _extractAsset('assets/tools/rid.keystore', 'rid.keystore'),
      home.path,
      tmp.path,
      opt.path,
    );
  }

  static Future<Directory> _cacheDir() async {
    final base = await _work();
    final d = Directory(p.join(base.path, 'cache', 'templates'));
    await d.create(recursive: true);
    return d;
  }

  static Future<List<PatchTemplate>> _loadBundled() async {
    final out = <PatchTemplate>[];
    try {
      final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
      final names = manifest.listAssets().where(
          (a) => a.startsWith('assets/templates/') && a.endsWith('.rid'));
      for (final a in names) {
        try {
          out.add(PatchTemplate.parse(await rootBundle.loadString(a)));
        } catch (_) {}
      }
    } catch (_) {}
    return out;
  }

  static Future<List<PatchTemplate>> loadTemplates() async {
    final byId = <String, PatchTemplate>{};
    for (final t in await _loadBundled()) {
      byId[t.id] = t;
    }
    try {
      final cache = await _cacheDir();
      await for (final e in cache.list()) {
        if (e is File && e.path.endsWith('.rid')) {
          try {
            final t = PatchTemplate.parse(await e.readAsString());
            byId[t.id] = t;
          } catch (_) {}
        }
      }
    } catch (_) {}
    final out = byId.values.toList();
    out.sort((a, b) => a.info.name.compareTo(b.info.name));
    return out;
  }

  static Future<List<PatchTemplate>> syncTemplates() async {
    final idxRes = await http
        .get(Uri.parse('$_repoRaw/index.json'))
        .timeout(const Duration(seconds: 15));
    if (idxRes.statusCode != 200) {
      throw Exception('index.json HTTP ${idxRes.statusCode}');
    }
    final data = jsonDecode(idxRes.body) as Map<String, dynamic>;
    final entries = (data['templates'] as List).cast<Map<String, dynamic>>();
    final cache = await _cacheDir();
    for (final e in entries) {
      final path = e['path'] as String?;
      if (path == null || !path.endsWith('.rid')) continue;
      final res = await http
          .get(Uri.parse('$_repoRaw/$path'))
          .timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) continue;
      PatchTemplate.parse(res.body);
      await File(p.join(cache.path, p.basename(path))).writeAsString(res.body);
    }
    return loadTemplates();
  }

  static Future<String> installedApk(String package) async {
    final base = await _work();
    final cache = Directory(p.join(base.path, 'cache'));
    await cache.create(recursive: true);
    final dest = p.join(cache.path, 'installed-$package.apk');
    try {
      final path = await _ch.invokeMethod<String>('installedApk', {
        'package': package,
        'dest': dest,
      });
      if (path == null) throw PatchException('not installed');
      return path;
    } on PlatformException catch (e) {
      throw PatchException('cannot use installed app: ${e.message}');
    }
  }

  static Future<ApkMeta?> readMeta(String apkPath) async {
    final bytes = await File(apkPath).readAsBytes();
    final zip = ZipDecoder().decodeBytes(bytes);
    final mf = zip.files.firstWhere(
      (f) => f.name == 'AndroidManifest.xml',
      orElse: () => ArchiveFile('', 0, const <int>[]),
    );
    if (mf.name.isEmpty) return null;
    return Axml.parseManifest(Uint8List.fromList(mf.content as List<int>));
  }

  static Future<PatchResult> patch({
    required String apkPath,
    required PatchTemplate template,
    required String outPath,
    required LogSink log,
  }) async {
    final tools = await ensureTools();
    final base = await _work();
    final dec = Directory(p.join(base.path, 'decoded'));
    final unsigned = File(p.join(base.path, 'unsigned.apk'));
    if (await dec.exists()) await dec.delete(recursive: true);

    final meta = await readMeta(apkPath);
    if (meta == null) throw PatchException('cannot read APK manifest');
    log('target: ${meta.package} ${meta.versionName}');
    if (meta.package != template.targetPackage) {
      throw PatchException(
          'template ${template.id} targets ${template.targetPackage}, APK is ${meta.package}');
    }
    final variant = template.select(meta.versionName);
    if (variant == null) {
      throw PatchException('no variant for version ${meta.versionName}');
    }

    final skipRes = Platform.isAndroid;
    final dexNames =
        Platform.isAndroid ? _dexNamesFor(variant) : const <String>[];

    log('decoding…');
    var api = 29;
    if (Platform.isAndroid) {
      api = await _dexDecode(tools, apkPath, dec.path, dexNames, log);
    } else {
      await _decode(tools, apkPath, dec.path, log);
    }

    log('applying patches…');
    int applied = 0, skipped = 0;
    final appliedFiles = <String>[];
    for (final rule in variant.patches) {
      if (skipRes && rule.file.startsWith('res/')) {
        log('  skip (res) [${rule.name}]');
        skipped++;
        continue;
      }
      final f = File(p.join(dec.path, rule.file.replaceAll('/', p.separator)));
      if (!await f.exists()) {
        throw PatchException('[${rule.name}] missing ${rule.file}');
      }
      final raw = await f.readAsString();
      final crlf = raw.contains('\r\n');
      final src = raw.replaceAll('\r\n', '\n');
      var out = applyRule(rule, src);
      if (crlf) out = out.replaceAll('\n', '\r\n');
      await f.writeAsString(out);
      log('  ok [${rule.name}]');
      appliedFiles.add(rule.file);
      applied++;
    }
    log('applied $applied, skipped $skipped');

    log('rebuilding…');
    if (Platform.isAndroid) {
      await _dexBuild(
          tools, apkPath, dec.path, unsigned.path, appliedFiles, api, log);
    } else {
      await _build(tools, dec.path, unsigned.path, log);
    }

    log('signing…');
    await _sign(tools, unsigned.path, outPath, log);
    log('done → $outPath');
    return PatchResult(outPath, template.id, applied, skipped);
  }

  static Future<void> _apktool(Tools t, List<String> args, LogSink log) async {
    log('+ apktool ${args.take(4).join(' ')}…');
    try {
      await _ch.invokeMethod('apktool', {
        'jar': t.apktool,
        'args': args,
        'tmp': t.tmp,
        'opt': t.opt,
      });
    } on PlatformException catch (e) {
      throw PatchException('apktool failed: ${e.message}');
    }
  }

  static List<String> _dexNamesFor(Variant v) {
    final set = <String>{};
    for (final r in v.patches) {
      final seg = r.file.split('/').first;
      if (seg == 'smali') {
        set.add('classes.dex');
      } else if (seg.startsWith('smali_classes')) {
        set.add('classes${seg.substring('smali_classes'.length)}.dex');
      }
    }
    return set.toList();
  }

  static Future<int> _dexDecode(
      Tools t, String apk, String out, List<String> dex, LogSink log) async {
    log('+ baksmali ${dex.join(', ')}…');
    try {
      final api = await _ch.invokeMethod<String>('dexDecode', {
        'jar': t.apktool,
        'opt': t.opt,
        'apk': apk,
        'dex': dex,
        'out': out,
      });
      return int.tryParse(api ?? '') ?? 29;
    } on PlatformException catch (e) {
      throw PatchException('decode failed: ${e.message}');
    }
  }

  static Future<void> _dexBuild(Tools t, String apk, String smali, String out,
      List<String> files, int api, LogSink log) async {
    final dexes = files
        .where((f) => !f.startsWith('res/'))
        .map((f) => f.split('/').first)
        .toSet();
    log('+ patch classes + splice ${dexes.join(', ')}…');
    try {
      await _ch.invokeMethod('dexBuild', {
        'jar': t.apktool,
        'opt': t.opt,
        'apk': apk,
        'files': files,
        'smali': smali,
        'output': out,
        'api': '$api',
      });
    } on PlatformException catch (e) {
      throw PatchException('rebuild failed: ${e.message}');
    }
  }

  static Future<void> _run(
      String exe, List<String> args, Map<String, String> env, LogSink log,
      {bool cleanEnv = false}) async {
    log('+ ${p.basename(exe)} ${args.take(3).join(' ')}…');
    final r = await Process.run(exe, args,
        environment: env, includeParentEnvironment: !cleanEnv);
    if (r.exitCode != 0) {
      final err = (r.stderr.toString() + r.stdout.toString())
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .toList();
      final tail = err.length > 6 ? err.sublist(err.length - 6) : err;
      throw PatchException('command failed (${r.exitCode}):\n${tail.join('\n')}');
    }
  }

  static Future<void> _decode(
      Tools t, String apk, String out, LogSink log) async {
    if (Platform.isAndroid) {
      await _apktool(t, ['d', '-r', '-f', apk, '-o', out], log);
    } else {
      await _run('java', ['-jar', t.apktool, 'd', '-f', apk, '-o', out],
          {'_JAVA_OPTIONS': '-Xmx384M'}, log);
    }
  }

  static Future<void> _build(
      Tools t, String dir, String out, LogSink log) async {
    if (Platform.isAndroid) {
      await _apktool(t, ['b', dir, '-o', out], log);
    } else {
      await _run('java', ['-jar', t.apktool, 'b', dir, '-o', out],
          {'_JAVA_OPTIONS': '-Xmx384M'}, log);
    }
  }

  static Future<void> _sign(
      Tools t, String unsigned, String out, LogSink log) async {
    final f = File(out);
    if (await f.exists()) await f.delete();
    if (Platform.isAndroid) {
      log('+ apksigner sign…');
      try {
        await _ch.invokeMethod('sign', {
          'signer': t.apksigner,
          'opt': t.opt,
          'input': unsigned,
          'output': out,
          'keystore': t.keystore,
          'alias': 'key',
          'pass': 'android',
        });
      } on PlatformException catch (e) {
        throw PatchException('signing failed: ${e.message}');
      }
    } else {

      final home = Platform.environment['ANDROID_HOME'] ?? '';
      final bt = Directory(p.join(home, 'build-tools'));
      final ver = bt.existsSync()
          ? (bt.listSync().whereType<Directory>().toList()
                ..sort((a, b) => a.path.compareTo(b.path)))
              .last
              .path
          : '';
      final apksigner = p.join(ver, 'apksigner.bat');
      await _run(apksigner, [
        'sign', '--ks', t.keystore, '--ks-key-alias', 'key',
        '--ks-pass', 'pass:android', '--key-pass', 'pass:android',
        '--out', out, unsigned,
      ], {}, log);
    }
  }
}
