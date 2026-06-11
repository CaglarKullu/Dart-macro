/// Regression tests for per-file macro isolation.
///
/// A macro defined in one source file must not leak into another file compiled
/// in the same directory or watch build. Before the fix, the global macro
/// registry was never rolled back between files, so a `defmacro` in file A was
/// silently usable from file B purely by compile order.
library;

import 'dart:io';

import 'package:dmacro/dmacro.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    registerBuiltins();
    registerSchemaMacros();
  });

  group('snapshot / restore primitives', () {
    test('restoreMacros rolls back a file-local defmacro', () {
      expect(isMacro('ephemeral'), isFalse);

      final snapshot = snapshotMacros();
      defmacro('ephemeral', (args) => ['ok']);
      expect(isMacro('ephemeral'), isTrue);

      restoreMacros(snapshot);
      expect(isMacro('ephemeral'), isFalse,
          reason: 'file-local macro should be gone after restore');
    });

    test('restoreMacros keeps the baseline (builtins) intact', () {
      final snapshot = snapshotMacros();
      defmacro('temp', (args) => ['ok']);
      restoreMacros(snapshot);

      // A builtin registered before the snapshot must survive the rollback.
      expect(isMacro('unless'), isTrue);
    });
  });

  group('directory compile isolates macros across files (via CLI)', () {
    late Directory dir;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('dmacro_isolation_');
      // a_defines sorts before b_uses, so without isolation `leaky` would leak
      // forward into b_uses.
      File('${dir.path}/a_defines.dmacro').writeAsStringSync('''
defmacro leaky(x) {
  unless (x) { throw Exception("leaked"); }
}
void useHere(bool b) { leaky(b); }
''');
      File('${dir.path}/b_uses.dmacro').writeAsStringSync('''
void other(bool b) { leaky(b); }
''');
    });

    tearDown(() => dir.deleteSync(recursive: true));

    test('a macro defined in one file does not expand in a sibling', () async {
      final result = await Process.run(
        'dart',
        ['run', 'bin/dmacro.dart', 'compile', dir.path],
        workingDirectory: Directory.current.path,
      );
      expect(result.exitCode, 0,
          reason: 'compile failed:\n${result.stderr}\n${result.stdout}');

      // The file that owns the macro expands it.
      final a = File('${dir.path}/a_defines.dart').readAsStringSync();
      expect(a, contains('throw Exception("leaked")'));

      // The sibling does NOT — `leaky(b)` stays a bare call.
      final b = File('${dir.path}/b_uses.dart').readAsStringSync();
      expect(b, contains('leaky(b);'),
          reason: 'macro leaked across files: b_uses should not expand leaky');
      expect(b, isNot(contains('throw Exception("leaked")')));
    });
  });
}
