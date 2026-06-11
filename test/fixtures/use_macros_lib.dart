/// Test fixture for `useMacros`: a Dart macro library with no entry point.
///
/// Loaded by test/use_macros_test.dart via
/// `useMacros("test/fixtures/use_macros_lib.dart")`. Exposes the conventional
/// `registerMacros()` plus an alternately-named registration function to
/// exercise the `#fnName` fragment.
library;

import 'package:dmacro/dmacro.dart';

void registerMacros() {
  // Async Dart-function macro: builds a class from structured field args.
  defAsyncMacro('defwidget', (args) async {
    final name = unquote(args[0] as String);
    final fields = args.skip(1).cast<List>().toList();
    final decls = fields.map((f) => '  final ${f[0]} ${f[1]};').join('\n');
    return 'class $name {\n$decls\n}';
  });

  // Sync macro whose output contains a builtin (`unless`) and another worker
  // macro (`mustBePositive`) — proves the parent keeps expanding worker output.
  defmacro('checkAmount', (args) {
    final v = args[0];
    return [
      'block',
      ['mustBePositive', v],
    ];
  });

  defmacro('mustBePositive', (args) {
    final v = args[0];
    return [
      'unless',
      ['>', v, 0],
      ['throw', ['ArgumentError', '"must be positive"']],
    ];
  });

  // Always throws — exercises macro-author error attribution across the isolate.
  defAsyncMacro('boom', (args) async {
    throw StateError('kaboom');
  });
}

/// Alternate registration function reached via `#registerExtra`.
void registerExtra() {
  defAsyncMacro('defmarker', (args) async => 'const marker = true;');
}
