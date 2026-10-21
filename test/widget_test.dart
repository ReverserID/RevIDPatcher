import 'package:flutter_test/flutter_test.dart';

import 'package:reverser_id_app/core/template.dart';

void main() {
  test('template engine applies find/replace with backrefs', () {
    const rid = r'''
id: demo
name: Demo
author: reverser.id
target: com.demo

variant ^1\.4

rule map
file: smali/a.smali
find <<<
\.method x.*?\.end method
<<<
replace <<<
.method x
    const v0
.end method
<<<

rule cond
file: smali/b.smali
find <<<
(:cond_0\n)    old
<<<
replace <<<
$1    new
<<<
''';
    final t = PatchTemplate.parse(rid);
    expect(t.id, 'demo');
    expect(t.compatible('com.demo', '1.4'), isTrue);
    expect(t.compatible('com.demo', '1.3'), isFalse);

    final v = t.select('1.4')!;
    final map = applyRule(
        v.patches[0], '.method x\n    stuff\n    more\n.end method\n');
    expect(map.contains('const v0'), isTrue);
    expect(map.contains('stuff'), isFalse);

    final cond = applyRule(v.patches[1], 'a\n:cond_0\n    old\nb');
    expect(cond.contains(':cond_0\n    new'), isTrue);
  });
}
