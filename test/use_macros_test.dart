/// Tests `useMacros` — loading Dart-function macros from a .dart library with
/// no `tool/dmacro.dart` entry point. The library runs in a worker isolate and
/// the directive registers a proxy per macro it exposes.
///
/// Uses the public API only (`package:dmacro/dmacro.dart`), plus the committed
/// fixture at test/fixtures/use_macros_lib.dart.
library;

import 'dart:io';

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

    test('block syntax passes structured field args across the isolate',
        () async {
      // defwidget Name { T f; } parses to ['defwidget','Name',['T','f'],…];
      // the nested field lists must survive encode/decode to the worker.
      final source = '''
useMacros("$_fixture");

defwidget Card {
  String title;
  double? elevation;
}
''';
      final out = await asyncCompileDartLike(source);
      expect(out, contains('class Card {'));
      expect(out, contains('final String title;'));
      expect(out, contains('final double? elevation;'));
    });

    test('a worker macro returning a Splice expands as sibling forms', () async {
      final source = '''
useMacros("$_fixture");

defpair("Alpha", "Beta");
''';
      final out = await asyncCompileDartLike(source);
      expect(out, contains('class Alpha {}'));
      expect(out, contains('class Beta {}'));
    });

    test('an async worker macro can do real I/O at generation time', () async {
      final tmp = await File(
              '${Directory.systemTemp.path}/dmacro_usemacros_${DateTime.now().microsecondsSinceEpoch}.txt')
          .writeAsString('Loaded');
      addTearDown(() => tmp.deleteSync());

      final source = '''
useMacros("$_fixture");

defFromFile("${tmp.path}");
''';
      final out = await asyncCompileDartLike(source);
      expect(out, contains('class Loaded {}'));
    });

    test('loads through the S-expression (.sexp) path too', () async {
      final source = '''
(useMacros "$_fixture")
(defwidget "Gauge" (double value))
''';
      final out = await asyncCompile(source);
      expect(out, contains('class Gauge {'));
      expect(out, contains('final double value;'));
    });

    test('recompiling unchanged source is byte-identical (idempotent)',
        () async {
      final source = '''
useMacros("$_fixture");

defwidget Tag { String name; }
''';
      final first = await asyncCompileDartLike(source);
      shutdownMacroWorkers(); // force a fresh worker for the second run
      final second = await asyncCompileDartLike(source);
      expect(second, equals(first));
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
