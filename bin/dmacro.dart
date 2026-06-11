/// dmacro compiler CLI — thin shim over the library implementation.
///
/// In a consumer project:  dart run dmacro compile <file>
/// In this repository:     dart run bin/dmacro.dart compile <file>
///
/// Your own macros don't need a custom entry point: load them from the
/// `.dmacro` source with `useMacros("lib/my_macros.dart")` (a Dart library
/// exposing `registerMacros()`) and this same CLI picks them up. If you'd
/// rather register in code, see `runDmacro` in `package:dmacro/dmacro.dart`.
library;

import 'package:dmacro/dmacro.dart' show runDmacro;

Future<void> main(List<String> args) => runDmacro(args);
