/// dmacro — Lisp-style macro preprocessor for Dart.
///
/// Code is data: source parses to nested lists (`Node`), macros are functions
/// `(List<Node>) → Node`, and the emitter writes plain Dart back out.
///
/// ## Using the built-in macros
///
/// Add dmacro as a dependency and compile straight away — no entry point
/// needed:
///
/// ```bash
/// dart run dmacro compile lib/models.dmacro
/// ```
///
/// ## Writing your own macros (the point of this package)
///
/// Write your macro as a plain Dart library exposing `registerMacros()`, then
/// load it from your `.dmacro` source with `useMacros` — no entry point:
///
/// ```dart
/// // lib/widget_macros.dart
/// import 'package:dmacro/dmacro.dart';
///
/// void registerMacros() {
///   defAsyncMacro('defwidget', (args) async {
///     final name = unquote(args[0] as String);
///     return 'class $name extends StatelessWidget { /* ... */ }';
///   });
/// }
/// ```
///
/// ```dart
/// // lib/widgets.dmacro
/// useMacros("lib/widget_macros.dart");
/// defwidget SubmitButton { String label; }
/// ```
///
/// ```bash
/// dart run dmacro compile lib/widgets.dmacro
/// ```
///
/// Your macros use the same API the built-ins are written with:
/// [defmacro] for sync transforms, `defAsyncMacro` for macros that need
/// I/O at generation time, [unquote] for string-literal arguments, and
/// `gensym` for hygienic temporaries.
///
/// Prefer registering in code instead? [runDmacro]'s `registerMacros` callback
/// still works — write a `tool/dmacro.dart` entry point and run it directly.
library dmacro;

export 'src/core.dart';
export 'src/nodes.dart';
export 'src/builtins.dart';
export 'src/reader.dart';
export 'src/tokenizer.dart';
export 'src/dart_parser.dart';
export 'src/gensym.dart';
export 'src/splice.dart' show $splice;
export 'src/async_expand.dart';
export 'src/schema_macros.dart';
export 'src/macro_loader.dart' show loadMacroLibrary, shutdownMacroWorkers;
export 'src/cli.dart' show runDmacro;
