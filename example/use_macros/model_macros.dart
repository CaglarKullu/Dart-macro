/// A Dart-function macro library — no entry point, no runDmacro wiring.
///
/// `models.dmacro` loads this with `useMacros("example/use_macros/model_macros.dart")`
/// and the `defmodel` macro becomes available like a builtin. dmacro runs this
/// library in a worker isolate at generation time.
///
/// Run it:
///   dart run dmacro compile example/use_macros/models.dmacro
library;

import 'package:dmacro/dmacro.dart';

/// Conventional entry the `useMacros` directive calls to register macros.
void registerMacros() {
  // defmodel TypeName { Type field; ... }  →  a small immutable value class.
  defAsyncMacro('defmodel', (args) async {
    final name = unquote(args[0] as String);
    final fields = args.skip(1).cast<List>().toList();

    final decls = fields.map((f) => '  final ${f[0]} ${f[1]};').join('\n');
    final params = fields.map((f) => 'this.${f[1]}').join(', ');

    return 'class $name {\n'
        '$decls\n\n'
        '  const $name($params);\n'
        '}';
  });
}
