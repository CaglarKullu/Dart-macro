/// Tests `useMacros` — loading Dart-function macros from a .dart library with
/// no `tool/dmacro.dart` entry point. The library runs in a worker isolate and
/// the directive registers a proxy per macro it exposes.
///
/// Uses the public API only (`package:dmacro/dmacro.dart`), plus the committed
/// fixture at test/fixtures/use_macros_lib.dart.
library;

import 'package:dmacro/dmacro.dart';
import 'package:test/test.dart';

const _fixture = 'test/fixtures/use_macros_lib.dart';

void main() {
  setUp(() {
    registerBuiltins();
    registerSchemaMacros();
  });

  // Tear down worker isolates so they don't leak across tests / hang the run.
  tearDown(shutdownMacroWorkers);

  group('useMacros — loads Dart macros without an entry point', () {
    test('a worker macro expands in a .dmacro source', () async {
      final source = '''
useMacros("$_fixture");

defwidget Button {
  String label;
  int count;
}
''';
      final out = await asyncCompileDartLike(source);
      expect(out, contains('class Button {'));
      expect(out, contains('final String label;'));
      expect(out, contains('final int count;'));
      // The useMacros directive itself emits no Dart.
      expect(out, isNot(contains('useMacros')));
    });

    test('worker output composes with builtins and re-entrant worker macros',
        () async {
      // checkAmount → [block [mustBePositive v]]; mustBePositive → unless(...);
      // unless is a parent builtin. All three layers must resolve.
      final source = '''
useMacros("$_fixture");

void withdraw(int amount) {
  checkAmount(amount);
}
''';
      final out = await asyncCompileDartLike(source);
      expect(out, contains('if (!(amount > 0))'));
      expect(out, contains('throw ArgumentError("must be positive")'));
    });

    test('loading the same library twice is a no-op (cached)', () async {
      final source = '''
useMacros("$_fixture");
useMacros("$_fixture");

defwidget Box { double size; }
''';
      final out = await asyncCompileDartLike(source);
      expect(out, contains('class Box {'));
    });

    test('a #fnName fragment selects an alternate registration function',
        () async {
      final source = '''
useMacros("$_fixture#registerExtra");

defmarker();
''';
      final out = await asyncCompileDartLike(source);
      expect(out, contains('const marker = true;'));
    });
  });

  group('useMacros — error handling', () {
    test('a throwing worker macro is attributed to the macro name', () async {
      final source = '''
useMacros("$_fixture");

void f() {
  boom();
}
''';
      await expectLater(
        () => asyncCompileDartLike(source),
        throwsA(isA<MacroExpansionError>().having(
            (e) => e.message, 'message', contains('boom'))),
      );
    });

    test('an unresolvable library surfaces a clear MacroExpansionError',
        () async {
      final source = '''
useMacros("test/fixtures/does_not_exist.dart");
''';
      await expectLater(
        () => asyncCompileDartLike(source),
        throwsA(isA<MacroExpansionError>().having(
            (e) => e.message, 'message', contains('useMacros'))),
      );
    });
  });
}
