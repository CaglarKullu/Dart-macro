/// Tier 2 — computed templates (task 10.3).
///
/// `$map(items, binder…, template)` expands the template once per item and
/// splices the results into the enclosing list. Together with rest params
/// (`defmacro name(...rest)`) this lets TEMPLATE macros iterate — the gap
/// between Tier 1 (pure substitution) and Tier 3 (Dart functions).
library;

import 'package:dmacro/dmacro.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    registerBuiltins();
    registerSchemaMacros();
  });

  group(r'$map — node level', () {
    test('single binder maps template over items', () {
      final result = expand([
        r'$map',
        ['a', 'b', 'c'],
        'v',
        ['print', 'v'],
      ]);
      expect(result, isA<Splice>());
      final nodes = (result as Splice).nodes;
      expect(nodes, [
        ['print', 'a'],
        ['print', 'b'],
        ['print', 'c'],
      ]);
    });

    test('multiple binders destructure list elements', () {
      final result = expand([
        r'$map',
        [
          ['String', 'host'],
          ['int', 'port'],
        ],
        't',
        'n',
        ['register', 't', 'n'],
      ]) as Splice;
      expect(result.nodes, [
        ['register', 'String', 'host'],
        ['register', 'int', 'port'],
      ]);
    });

    test(r'nested $map flattens inner splice into outer', () {
      final result = expand([
        r'$map',
        [
          ['a', 'b'],
          ['c', 'd'],
        ],
        'row',
        [r'$map', 'row', 'x', ['print', 'x']],
      ]) as Splice;
      expect(result.nodes, [
        ['print', 'a'],
        ['print', 'b'],
        ['print', 'c'],
        ['print', 'd'],
      ]);
    });

    test('template containing macro calls is expanded (Splice contents)', () {
      final result = expand([
        r'$map',
        ['cond1'],
        'c',
        ['unless', 'c', ['throw', ['Exception', '"x"']]],
      ]) as Splice;
      // unless must have expanded to if(!c) — Splice contents are not
      // allowed to escape unexpanded.
      final first = result.nodes[0] as List;
      expect(first[0], 'if');
      expect(first[1], ['!', 'cond1']);
    });

    test('empty items produce an empty splice', () {
      final result = expand([r'$map', [], 'v', ['print', 'v']]);
      expect((result as Splice).nodes, isEmpty);
    });
  });

  group(r'$map — .dmacro end to end', () {
    test(r'rest param + $map generates statements in a function body',
        () async {
      final out = await asyncCompileDartLike('''
defmacro logAll(...vals) {
  \$map(vals, v) { print(v); }
}
void main() {
  logAll(alpha, beta, gamma);
}
''');
      expect(out, contains('print(alpha);'));
      expect(out, contains('print(beta);'));
      expect(out, contains('print(gamma);'));
    });

    test('destructuring over block-syntax fields at top level', () async {
      // The flagship case: iterate over record-style fields. The macro call
      // sits at top level, so the resulting Splice is handled by emitForm.
      final out = await asyncCompileDartLike('''
defmacro declareAll(name, ...fields) {
  \$map(fields, t, n) { register(t, n); }
}
declareAll Config { String host; int port; }
''');
      expect(out, contains('register(String, host)'));
      expect(out, contains('register(int, port)'));
    });

    test(r'$map template composes with built-in macros', () async {
      final out = await asyncCompileDartLike('''
defmacro requireAll(...conds) {
  \$map(conds, c) { unless(c) { throw Exception("required"); } }
}
void check(int x) {
  requireAll(x > 0, x < 100);
}
''');
      expect(out, contains('if (!(x > 0))'));
      expect(out, contains('if (!(x < 100))'));
      expect(out, contains('throw Exception'));
    });

    test('fixed params bind before the rest param', () async {
      final out = await asyncCompileDartLike('''
defmacro tagAll(tag, ...vals) {
  \$map(vals, v) { log(tag, v); }
}
void main() {
  tagAll(audit, a, b);
}
''');
      expect(out, contains('log(audit, a);'));
      expect(out, contains('log(audit, b);'));
    });

    test('output is deterministic', () async {
      const src = '''
defmacro logAll(...vals) {
  \$map(vals, v) { print(v); }
}
void main() {
  logAll(x, y);
}
''';
      final a = await asyncCompileDartLike(src);
      final b = await asyncCompileDartLike(src);
      expect(a, b);
    });
  });

  group(r'$map — S-expression path', () {
    test(r'rest param + $map in sexp syntax', () async {
      final out = await asyncCompile(
        '(defmacro logAll (...vals) (\$map vals v (print v)))\n'
        '(logAll a b c)',
      );
      expect(out, contains('print(a)'));
      expect(out, contains('print(b)'));
      expect(out, contains('print(c)'));
    });
  });

  group(r'$map — errors', () {
    test('non-list items throws with macro attribution', () {
      expect(
        () async => asyncCompileDartLike(
            'void main() { \$map(notAList, v) { print(v); } }'),
        throwsA(isA<MacroExpansionError>().having(
          (e) => e.message,
          'message',
          allOf(contains(r'$map'), contains('must be a list')),
        )),
      );
    });

    test('destructure arity mismatch names the bad element', () {
      expect(
        () => expand([
          r'$map',
          [
            ['only-one'],
          ],
          'a',
          'b',
          ['use', 'a', 'b'],
        ]),
        throwsA(isA<ArgumentError>().having(
          (e) => e.message,
          'message',
          contains('cannot destructure'),
        )),
      );
    });

    test('too few args for a rest-param macro throws', () async {
      expect(
        () async => asyncCompileDartLike('''
defmacro tagAll(tag, ...vals) {
  \$map(vals, v) { log(tag, v); }
}
tagAll();
'''),
        throwsA(isA<MacroExpansionError>().having(
          (e) => e.message,
          'message',
          contains('at least 1'),
        )),
      );
    });
  });
}
