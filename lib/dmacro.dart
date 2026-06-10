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
/// Create an entry point that registers your macros, then run the full CLI
/// through it:
///
/// ```dart
/// // tool/dmacro.dart
/// import 'package:dmacro/dmacro.dart';
///
/// void main(List<String> args) => runDmacro(args, registerMacros: () {
///       defAsyncMacro('defwidget', (args) async {
///         final name = unquote(args[0] as String);
///         return 'class $name extends StatelessWidget { /* ... */ }';
///       });
///     });
/// ```
///
/// ```bash
/// dart run tool/dmacro.dart compile lib/widgets.dmacro
/// ```
///
/// Your macros use the same API the built-ins are written with:
/// [defmacro] for sync transforms, `defAsyncMacro` for macros that need
/// I/O at generation time, [unquote] for string-literal arguments, and
/// `gensym` for hygienic temporaries.
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
export 'src/cli.dart' show runDmacro;
