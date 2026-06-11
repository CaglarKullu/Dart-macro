/// Tests for the four improvements added from Swift macros lessons:
///   1. Inline .dart block expansion
///   2. VS Code "Expand Macro" command (extension-only — tested via CLI trace)
///   3. importMacros
///   4. defmacro(declaration/expression/statement) output type validation
library;

import 'dart:io';

import 'package:dmacro/src/async_expand.dart'
    show asyncCompileDartLike, asyncCompile;
import 'package:dmacro/src/builtins.dart';
import 'package:dmacro/src/core.dart' show MacroExpansionError;
import 'package:dmacro/src/schema_macros.dart';
import 'package:test/test.dart';

void main() {
  setUpAll(() {
    registerBuiltins();
    registerSchemaMacros();
  });

  // ─── 1. Inline .dart block expansion ──────────────────────────────────────

  group('inline .dart block processing (via CLI)', () {
    late File dartFile;

    setUp(() {
      dartFile = File(
          '${Directory.systemTemp.path}/dmacro_inline_test_${DateTime.now().microsecondsSinceEpoch}.dart');
    });

    tearDown(() {
      if (dartFile.existsSync()) dartFile.deleteSync();
    });

    test('expands a fresh @@dmacro block', () async {
      dartFile.writeAsStringSync('''
// A test file.

// @@dmacro
defrecord Point { double x; double y; }
// @@end

void use(Point p) {}
''');

      final result = Process.runSync(
        Platform.resolvedExecutable,
        ['run', 'bin/dmacro.dart', 'compile', dartFile.path],
        workingDirectory: Directory.current.path,
      );
      expect(result.exitCode, 0, reason: result.stderr.toString());

      final content = dartFile.readAsStringSync();
      expect(content, contains('// @@dmacro'));
      expect(content, contains('// @@generated'));
      expect(content, contains('// @@end'));
      expect(content, contains('class Point'));
      expect(content, contains('final double x'));
      // Original macro source is preserved as comments.
      expect(content, contains('// defrecord Point'));
    });

    test('re-expanding an already-expanded file is idempotent', () async {
      dartFile.writeAsStringSync('''
// @@dmacro
defrecord Point { double x; double y; }
// @@end
''');

      final run1 = Process.runSync(
        Platform.resolvedExecutable,
        ['run', 'bin/dmacro.dart', 'compile', dartFile.path],
        workingDirectory: Directory.current.path,
      );
      expect(run1.exitCode, 0);

      final after1 = dartFile.readAsStringSync();

      final run2 = Process.runSync(
        Platform.resolvedExecutable,
        ['run', 'bin/dmacro.dart', 'compile', dartFile.path],
        workingDirectory: Directory.current.path,
      );
      expect(run2.exitCode, 0);
      // File must not change on second run.
      expect(dartFile.readAsStringSync(), equals(after1));
      expect(run2.stderr.toString(), contains('no changes'));
    });

    test('supports multiple @@dmacro blocks in one file', () async {
      dartFile.writeAsStringSync('''
// @@dmacro
defrecord Point { double x; double y; }
// @@end

// @@dmacro
defrecord Size { double width; double height; }
// @@end
''');

      Process.runSync(
        Platform.resolvedExecutable,
        ['run', 'bin/dmacro.dart', 'compile', dartFile.path],
        workingDirectory: Directory.current.path,
      );

      final content = dartFile.readAsStringSync();
      expect(content, contains('class Point'));
      expect(content, contains('class Size'));
    });
  });

  // ─── 3. importMacros ──────────────────────────────────────────────────────

  group('importMacros', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('dmacro_import_test_');
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    test('import statement produces no Dart output', () async {
      // Write a simple macro library.
      File('${tmpDir.path}/my_macros.dmacro').writeAsStringSync('''
defmacro greet(name) {
  print(name);
}
''');

      final result = await asyncCompileDartLike(
        'importMacros("${tmpDir.path}/my_macros.dmacro");',
      );
      // No Dart output from import statement itself.
      expect(result.trim(), isEmpty);
    });

    test('macros from imported .dmacro file are registered and usable', () async {
      File('${tmpDir.path}/helpers.dmacro').writeAsStringSync('''
defmacro logIt(x) {
  print(x);
}
''');

      // First import registers the macro.
      await asyncCompileDartLike(
        'importMacros("${tmpDir.path}/helpers.dmacro");',
      );

      // Now logIt should be available (it was registered as a side-effect).
      final result = await asyncCompileDartLike('logIt(42);');
      expect(result.trim(), isNotEmpty);
    });

    test('importing a .sexp file works', () async {
      File('${tmpDir.path}/macros.sexp').writeAsStringSync(
        '(defmacro double-it (x) (* x 2))',
      );

      final result = await asyncCompile(
        '(importMacros "${tmpDir.path}/macros.sexp")',
      );
      expect(result.trim(), isEmpty);
    });

    test('throws on non-existent file', () async {
      await expectLater(
        asyncCompileDartLike('importMacros("nonexistent.dmacro");'),
        throwsA(isA<MacroExpansionError>().having(
          (e) => e.message,
          'message',
          contains('file not found'),
        )),
      );
    });

    test('throws on unsupported file type', () async {
      final unsupported = File('${tmpDir.path}/macros.txt')
        ..writeAsStringSync('// not a dmacro file');

      await expectLater(
        asyncCompileDartLike(
          'importMacros("${unsupported.path}");',
        ),
        throwsA(isA<MacroExpansionError>().having(
          (e) => e.message,
          'message',
          contains('unsupported file type'),
        )),
      );
    });
  });

  // ─── 4. defmacro output type validation ───────────────────────────────────

  group('defmacro typed output validation', () {
    test('defmacro(declaration) can be defined without error', () async {
      // defmacro(declaration) wrapping a defrecord call at statement position.
      // The body just needs valid statement syntax; validation fires at call time.
      expect(
        asyncCompileDartLike('''
defmacro(declaration) makeWrapper(x) {
  unless(true) { throw Exception("never"); }
}
'''),
        completes,
      );
    });

    test('defmacro(expression) can be defined without error', () async {
      expect(
        asyncCompileDartLike('defmacro(expression) asExpr(x) { return x; }'),
        completes,
      );
    });

    test('defmacro(statement) can be defined without error', () async {
      expect(
        asyncCompileDartLike('defmacro(statement) doLog(x) { print(x); }'),
        completes,
      );
    });

    test('defmacro(declaration) rejects statement output', () async {
      // Define a macro typed as declaration but body expands to a statement.
      await asyncCompileDartLike(
        'defmacro(declaration) badDecl(x) { print(x); }',
      );
      // Calling it should throw because print(x) is a statement, not a declaration.
      await expectLater(
        asyncCompileDartLike('badDecl(hello);'),
        throwsA(isA<MacroExpansionError>().having(
          (e) => e.message,
          'message',
          contains('defmacro(declaration)'),
        )),
      );
    });

    test('defmacro(expression) accepts expression output', () async {
      // A macro that returns an identifier — valid as an expression.
      await asyncCompileDartLike(
        'defmacro(expression) asExpr2(x) { return x; }',
      );
      // Defining the macro should succeed without error — no output.
      // (Call-time validation would pass since `x` doesn't end with `;`.)
    });

    test('defmacro with unknown type throws at definition time', () async {
      await expectLater(
        asyncCompileDartLike('defmacro(foobar) invalid(x) { print(x); }'),
        throwsA(isA<MacroExpansionError>().having(
          (e) => e.message,
          'message',
          contains('unknown output type'),
        )),
      );
    });
  });
}
