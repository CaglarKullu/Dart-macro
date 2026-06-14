/// Phase 10.4 — Macro-author error attribution.
///
/// Verifies that expansion failures always name the macro and the source
/// location, whether the failing macro is sync or async, and that the trace
/// output shows each macro's name and arguments clearly.
library;

import 'package:test/test.dart';
import 'package:dmacro/dmacro.dart';

void main() {
  setUpAll(registerBuiltins);

  setUp(() {
    resetGensym();
    resetEnumRegistry();
  });

  // ─── Sync expand() wraps exceptions ──────────────────────────────────────────

  group('sync expand() — exception attribution', () {
    test('macro that throws is wrapped with its name', () {
      defmacro('syncBoom', (args) => throw StateError('intentional'));
      expect(
        () => expand(['syncBoom', 'x']),
        throwsA(
          isA<MacroExpansionError>().having(
            (e) => e.message,
            'message',
            allOf(contains('syncBoom'), contains('intentional')),
          ),
        ),
      );
    });

    test('MacroExpansionError from nested sync macro is re-thrown unchanged', () {
      defmacro('innerSync', (_) => throw MacroExpansionError('inner: bad args'));
      defmacro('outerSync', (args) => ['innerSync', ...args]);
      expect(
        () => expand(['outerSync', 'x']),
        throwsA(
          isA<MacroExpansionError>().having(
            (e) => e.message,
            'message',
            contains('inner: bad args'),
          ),
        ),
      );
    });
  });

  // ─── Async expand() wraps exceptions ─────────────────────────────────────────

  group('async expand() — exception attribution', () {
    test('async macro that throws is wrapped with its name', () async {
      defAsyncMacro(
          'asyncBoom', (args) async => throw StateError('async fail'));
      await expectLater(
        asyncExpand(['asyncBoom', 'x']),
        throwsA(
          isA<MacroExpansionError>().having(
            (e) => e.message,
            'message',
            allOf(contains('asyncBoom'), contains('async fail')),
          ),
        ),
      );
    });
  });

  // ─── WithOrigins compile names the macro and the file:line ──────────────────

  group('WithOrigins — macro name + file:line in error', () {
    test('broken macro → error contains macro name and file:line', () async {
      defAsyncMacro(
          'brokenWidget',
          (args) async => throw ArgumentError('bad schema'));
      MacroExpansionError? caught;
      try {
        // Use sexp format: always valid syntax regardless of parser rules
        await asyncCompileWithOrigins('(brokenWidget x)', 'widgets.dmacro');
      } on MacroExpansionError catch (e) {
        caught = e;
      }
      expect(caught, isNotNull);
      final msg = caught!.message;
      expect(msg, contains('widgets.dmacro'));
      expect(msg, contains('brokenWidget'));
      expect(msg, contains('bad schema'));
    });

    test('error message starts with file:line prefix', () async {
      defAsyncMacro('boom2', (_) async => throw StateError('oops'));
      MacroExpansionError? caught;
      try {
        // Two blank lines before the macro call → form is on line 3
        await asyncCompileWithOrigins('\n\n(boom2 x)', 'src/model.dmacro');
      } on MacroExpansionError catch (e) {
        caught = e;
      }
      expect(caught!.message, startsWith('src/model.dmacro:3:'));
    });
  });

  // ─── Trace output — macro name shown separately ───────────────────────────────

  group('trace — macro name and args format', () {
    test('trace shows [N] macroName  args…', () async {
      defmacro('myMacro', (args) => args[0]);
      final sink = StringBuffer();
      await asyncCompileWithTrace('(myMacro hello)', 'src.sexp', sink);
      final out = sink.toString();
      // New format: "[1] myMacro  hello" — macro name before args, not all inside parens
      expect(out, contains('[1] myMacro'));
      expect(out, contains('hello'));
    });

    test('trace shows → for successful expansion', () async {
      defmacro('identityM', (args) => args[0]);
      final sink = StringBuffer();
      await asyncCompileWithTrace('(identityM x)', 'src.sexp', sink);
      expect(sink.toString(), contains('→'));
    });

    test('trace shows ✗ and macro name when macro fails', () async {
      defAsyncMacro('badMacro', (_) async => throw StateError('trace fail'));
      final sink = StringBuffer();
      try {
        await asyncCompileWithTrace('(badMacro x)', 'src.sexp', sink);
      } on MacroExpansionError {
        // expected
      }
      final out = sink.toString();
      expect(out, contains('✗'));
      expect(out, contains('badMacro'));
      expect(out, contains('trace fail'));
    });

    test('nested macro calls are indented', () async {
      defmacro('outerT', (args) => ['innerT', ...args]);
      defmacro('innerT', (args) => args[0]);
      final sink = StringBuffer();
      await asyncCompileWithTrace('(outerT x)', 'src.sexp', sink);
      final lines = sink.toString().split('\n');
      final outerLine = lines.firstWhere((l) => l.contains('] outerT'));
      final innerLine = lines.firstWhere((l) => l.contains('] innerT'));
      // inner should have more leading whitespace than outer
      expect(
        innerLine.indexOf('['),
        greaterThan(outerLine.indexOf('[')),
      );
    });
  });

  // ─── 10.2: throw in expression position ──────────────────────────────────────

  group('throw as expression (10.2 parser fix)', () {
    test('throw in ternary else branch emits correctly', () async {
      const src = '''
String validate(String s) {
  return s.isNotEmpty ? s : throw ArgumentError("empty");
}
''';
      final out = await asyncCompileDartLike(src);
      expect(out, contains('throw ArgumentError'));
      expect(out, isNot(contains('throw;')));
    });

    test('emit() handles [throw, expr] node from expression position', () {
      final node = ['throw', ['ArgumentError', '"bad"']];
      expect(emit(node), equals('throw ArgumentError("bad")'));
    });

    test('return with throw-ternary round-trips cleanly', () async {
      const src = '''
String requireNonEmpty(String s) {
  return s.isNotEmpty ? s : throw ArgumentError("must not be empty");
}
''';
      final out = await asyncCompileDartLike(src);
      expect(out, contains('throw ArgumentError'));
      expect(out, isNot(contains('throw;')));
    });

    test('throw in ternary false branch is emitted correctly in full compile', () {
      // Without the fix, 'throw' was returned as a bare identifier and
      // SomeException() was left unconsumed, causing a parse error or wrong output.
      final out = compileDartLike(
        'String f(String x) { return x.isNotEmpty ? x : throw StateError("empty"); }',
      );
      expect(out, contains('throw StateError'));
      expect(out, isNot(contains('throw;')));
    });
  });
}
