/// dmacro compiler CLI — thin shim over the library implementation.
///
/// In a consumer project:  dart run dmacro compile <file>
/// In this repository:     dart run bin/dmacro.dart compile <file>
///
/// To run the CLI with your own macros registered, write your own entry
/// point instead — see `runDmacro` in `package:dmacro/dmacro.dart`:
///
/// ```dart
/// // tool/dmacro.dart
/// import 'package:dmacro/dmacro.dart';
///
/// void main(List<String> args) => runDmacro(args, registerMacros: () {
///       defAsyncMacro('defwidget', (args) async => /* code → code */ '');
///     });
/// ```
library;

import 'package:dmacro/dmacro.dart' show runDmacro;

Future<void> main(List<String> args) => runDmacro(args);
