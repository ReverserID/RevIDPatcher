
class PatchTemplate {
  final String id;
  final TemplateInfo info;
  final String targetPackage;
  final List<Variant> variants;

  PatchTemplate(this.id, this.info, this.targetPackage, this.variants);

  static PatchTemplate parse(String text) {
    final lines = text.replaceAll('\r\n', '\n').split('\n');

    String? id, pkg, source, versions;
    var name = '', author = '', description = '';
    var tags = const <String>[];
    final variants = <Variant>[];

    bool hasVariant = false;
    String? vRegex;
    var vRules = <Rule>[];

    bool hasRule = false;
    String? rName, rFile, rFind, rReplace;
    var rCount = 1;
    var rMust = <String>[];

    void flushRule() {
      if (!hasRule) return;
      if (rFile == null || rFind == null || rReplace == null) {
        throw PatchException('rule "${rName ?? '?'}" missing file/find/replace');
      }
      vRules.add(Rule(
        name: rName ?? '',
        file: rFile!,
        find: rFind!,
        replace: rReplace!,
        count: rCount,
        mustContain: List<String>.unmodifiable(rMust),
      ));
      hasRule = false;
      rName = rFile = rFind = rReplace = null;
      rCount = 1;
      rMust = <String>[];
    }

    void flushVariant() {
      if (!hasVariant) return;
      variants.add(Variant(
          versionNameRegex: vRegex, patches: List<Rule>.unmodifiable(vRules)));
      hasVariant = false;
      vRegex = null;
      vRules = <Rule>[];
    }

    var i = 0;
    while (i < lines.length) {
      final line = lines[i];
      final t = line.trim();

      if (t == 'find <<<' || t == 'replace <<<') {
        final isFind = t.startsWith('find');
        final buf = <String>[];
        i++;
        while (i < lines.length && lines[i].trim() != '<<<') {
          buf.add(lines[i]);
          i++;
        }
        i++;
        final content = buf.join('\n');
        if (isFind) {
          rFind = content;
        } else {
          rReplace = content;
        }
        continue;
      }
      i++;

      if (t.isEmpty || t.startsWith('#')) continue;

      if (t == 'variant' || t.startsWith('variant ')) {
        flushRule();
        flushVariant();
        final rx = t.length > 7 ? t.substring(7).trim() : '';
        hasVariant = true;
        vRegex = rx.isEmpty ? null : rx;
        vRules = <Rule>[];
        continue;
      }

      if (t.startsWith('rule ')) {
        flushRule();
        if (!hasVariant) {
          hasVariant = true;
          vRegex = null;
          vRules = <Rule>[];
        }
        hasRule = true;
        rName = t.substring(5).trim();
        continue;
      }

      final idx = line.indexOf(':');
      if (idx <= 0) continue;
      final key = line.substring(0, idx).trim();
      final val = line.substring(idx + 1).trim();
      if (hasRule) {
        switch (key) {
          case 'file':
            rFile = val;
          case 'count':
            rCount = int.tryParse(val) ?? 1;
          case 'must':
            rMust.add(val);
        }
      } else {
        switch (key) {
          case 'id':
            id = val;
          case 'target':
            pkg = val;
          case 'name':
            name = val;
          case 'author':
            author = val;
          case 'desc':
            description = val;
          case 'tags':
            tags = val
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList();
          case 'versions':
            versions = val;
          case 'source':
            source = val;
        }
      }
    }
    flushRule();
    flushVariant();

    if (id == null || pkg == null) {
      throw PatchException('template missing id/target');
    }
    return PatchTemplate(
      id,
      TemplateInfo(
        name: name,
        author: author,
        description: description,
        tags: tags,
        source: source,
        versions: versions,
      ),
      pkg,
      variants,
    );
  }

  Variant? select(String versionName) {
    for (final v in variants) {
      final rx = v.versionNameRegex;
      if (rx == null) return v;
      if (RegExp(rx).hasMatch(versionName)) return v;
    }
    return null;
  }

  bool compatible(String package, String versionName) =>
      package == targetPackage && select(versionName) != null;
}

class TemplateInfo {
  final String name;
  final String author;
  final String description;
  final List<String> tags;

  final String? source;

  final String? versions;

  TemplateInfo({
    required this.name,
    required this.author,
    required this.description,
    required this.tags,
    this.source,
    this.versions,
  });
}

class Variant {
  final String? versionNameRegex;
  final List<Rule> patches;
  Variant({required this.versionNameRegex, required this.patches});
}

class Rule {
  final String name;
  final String file;
  final String find;
  final String replace;
  final int count;
  final List<String> mustContain;
  Rule({
    required this.name,
    required this.file,
    required this.find,
    required this.replace,
    this.count = 1,
    this.mustContain = const [],
  });
}

class PatchException implements Exception {
  final String message;
  PatchException(this.message);
  @override
  String toString() => message;
}

String applyRule(Rule rule, String src) {
  final re = RegExp(rule.find, dotAll: true);
  final matches = re.allMatches(src).toList();
  if (matches.length != rule.count) {
    throw PatchException(
        '[${rule.name}] anchor matched ${matches.length}x (want ${rule.count})');
  }
  final buf = StringBuffer();
  int last = 0;
  int applied = 0;
  for (final m in matches) {
    if (applied >= rule.count) break;
    buf.write(src.substring(last, m.start));
    buf.write(_expand(rule.replace, m));
    last = m.end;
    applied++;
  }
  buf.write(src.substring(last));
  final out = buf.toString();
  for (final anchor in rule.mustContain) {
    if (!out.contains(anchor)) {
      throw PatchException('[${rule.name}] result missing "$anchor"');
    }
  }
  return out;
}

String _expand(String repl, RegExpMatch m) {
  final out = StringBuffer();
  int i = 0;
  while (i < repl.length) {
    final c = repl[i];
    if (c == r'$') {
      if (i + 1 < repl.length && repl[i + 1] == r'$') {
        out.write(r'$');
        i += 2;
        continue;
      }
      if (i + 1 < repl.length && repl[i + 1] == '{') {
        final end = repl.indexOf('}', i);
        if (end > 0) {
          final n = int.tryParse(repl.substring(i + 2, end));
          if (n != null) out.write(m.group(n) ?? '');
          i = end + 1;
          continue;
        }
      }
      final mm = RegExp(r'^\d+').firstMatch(repl.substring(i + 1));
      if (mm != null) {
        final n = int.parse(mm.group(0)!);
        out.write(m.group(n) ?? '');
        i += 1 + mm.group(0)!.length;
        continue;
      }
    }
    out.write(c);
    i++;
  }
  return out.toString();
}
