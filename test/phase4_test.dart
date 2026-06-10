/// Phase 4 — Developer Experience tests.
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:dmacro/dmacro.dart';

void main() {
  setUpAll(registerBuiltins);

  // ─── 4.2 Located errors ──────────────────────────────────────────────────────

  group('located errors — tokenizer', () {
    test('unterminated string includes TokenizerException', () {
      expect(
        () => Tokenizer('"unterminated').tokenize(),
        throwsA(isA<TokenizerException>()),
      );
    });

    test('TokenizerException.toString() includes line/col', () {
      try {
        Tokenizer('\n\n"unterminated').tokenize();
      } on TokenizerException catch (e) {
        expect(e.toString(), contains('TokenizerException'));
        expect(e.line, greaterThan(0));
        expect(e.col, greaterThan(0));
      }
    });

    test('TokenizerException.toString() includes source line', () {
      try {
        Tokenizer('int x = "unterminated').tokenize();
      } on TokenizerException catch (e) {
        expect(e.toString(), contains('int x'));
      }
    });
  });

  group('located errors — parser', () {
    test('ParseException includes line/col', () {
      try {
        compileDartLike('void f() { 123 }');
      } on ParseException catch (e) {
        expect(e.line, greaterThan(0));
        expect(e.col, greaterThan(0));
        return;
      }
      fail('Expected ParseException');
    });

    test('ParseException.toString() includes location prefix', () {
      try {
        compileDartLike('void f() {\n  123\n}');
      } on ParseException catch (e) {
        // Should contain "line:col: " prefix in message
        expect(e.toString(), contains('ParseException:'));
        return;
      }
      fail('Expected ParseException');
    });

    test('missing closing brace gives ParseException at correct line', () {
      try {
        compileDartLike('void f() {\n  return 1;\n');
      } on ParseException catch (e) {
        expect(e, isA<ParseException>());
        return;
      }
      fail('Expected ParseException');
    });
  });

  // ─── 4.3 CLI ergonomics — --check ────────────────────────────────────────────

  group('--check mode', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('dmacro_test_');
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    test('--check exits non-zero when .dart is stale', () async {
      // Create a .dmacro file with no corresponding .dart
      final src = File('${tmpDir.path}/test.dmacro')
        ..writeAsStringSync('void foo() { return 1; }');
      final result = await Process.run(
        'dart',
        ['run', 'bin/dmacro.dart', 'compile', src.path, '--check'],
        workingDirectory: Directory.current.path,
      );
      expect(result.exitCode, isNot(0));
    });

    test('--check exits zero when .dart matches', () async {
      final srcPath = '${tmpDir.path}/test.dmacro';
      final outPath = '${tmpDir.path}/test.dart';
      File(srcPath).writeAsStringSync('void foo() { return 1; }');

      // First compile to create the .dart (no-format for determinism in CI)
      await Process.run(
        'dart',
        [
          'run',
          'bin/dmacro.dart',
          'compile',
          srcPath,
          '-o',
          outPath,
          '--no-format'
        ],
        workingDirectory: Directory.current.path,
      );

      // Now check with same flags — should be up to date
      final result = await Process.run(
        'dart',
        [
          'run',
          'bin/dmacro.dart',
          'compile',
          srcPath,
          '--check',
          '--no-format'
        ],
        workingDirectory: Directory.current.path,
      );
      expect(result.exitCode, equals(0));
    });
  });

  // ─── Per-field origin markers (statement-level attribution) ─────────────────

  group('per-field origin markers', () {
    test(
        'asyncCompileDartLikeWithOrigins default: top-level origin, no per-field',
        () async {
      const src = '''
defrecord Payment {
  double amount;
  String currency;
}
''';
      final out = await asyncCompileDartLikeWithOrigins(src, 'models.dmacro');
      // Top-level form origin is always present
      expect(out, contains('// @dmacro-origin: models.dmacro:'));
      // Per-field markers are OFF by default
      expect(out, isNot(contains('// @dmacro-origin: models.dmacro:2')));
      expect(out, isNot(contains('// @dmacro-origin: models.dmacro:3')));
    });

    test('fieldOrigins: true embeds per-field @dmacro-origin markers',
        () async {
      const src = '''
defrecord Payment {
  double amount;
  String currency;
}
''';
      final out = await asyncCompileDartLikeWithOrigins(src, 'models.dmacro',
          fieldOrigins: true);
      // Per-field markers present when explicitly enabled
      expect(out, contains('// @dmacro-origin: models.dmacro:2'));
      expect(out, contains('// @dmacro-origin: models.dmacro:3'));
      final origin2 = out.indexOf('// @dmacro-origin: models.dmacro:2');
      final finalAmount = out.indexOf('final double amount;');
      expect(origin2, lessThan(finalAmount),
          reason: 'origin marker should appear before the field declaration');
    });

    test('asyncCompileDartLike (no origin tracking) has no per-field markers',
        () async {
      const src = 'defrecord Point { double x; double y; }';
      final out = await asyncCompileDartLike(src);
      // No @dmacro-origin comments when not using WithOrigins
      expect(out, isNot(contains('@dmacro-origin')));
    });

    test('MacroExpansionError wraps crash with file:line context', () async {
      // Register a macro that throws during expansion to exercise the wrapping.
      defmacro('_throwForTest', (_) => throw StateError('boom'));
      await expectLater(
        asyncCompileDartLikeWithOrigins('_throwForTest();', 'crash.dmacro'),
        throwsA(isA<MacroExpansionError>()),
      );
    });

    test('MacroExpansionError message includes source path and line', () async {
      defmacro('_throwForTest', (_) => throw StateError('boom'));
      try {
        await asyncCompileDartLikeWithOrigins(
            '_throwForTest();', 'crash.dmacro');
        fail('Expected MacroExpansionError');
      } on MacroExpansionError catch (e) {
        expect(e.toString(), contains('crash.dmacro:1:'));
      }
    });
  });

  // ─── Token line/col correctness ──────────────────────────────────────────────

  group('token line/col', () {
    test('single-line token has line=1', () {
      final tokens = Tokenizer('void foo').tokenize();
      expect(tokens[0].line, equals(1));
      expect(tokens[0].col, equals(1));
    });

    test('second-line token has line=2', () {
      final tokens = Tokenizer('void\nfoo').tokenize();
      final foo = tokens.firstWhere((t) => t.value == 'foo');
      expect(foo.line, equals(2));
    });

    test('two-char operator has correct position', () {
      final tokens = Tokenizer('a == b').tokenize();
      final eq = tokens.firstWhere((t) => t.kind == TK.eq);
      expect(eq.col, equals(3));
    });
  });
}
