/// Tier 3 — your own Dart-function macros, loaded with `useMacros`.
///
/// No `tool/dmacro.dart` entry point: `app.dmacro` pulls these in with
///   useMacros("example/showcase/macros/domain_macros.dart");
/// and dmacro runs this library in a worker isolate at generation time.
///
/// Exposes the conventional `registerMacros()` the `useMacros` directive calls.
library;

import 'package:dmacro/dmacro.dart';

void registerMacros() {
  // ── A sync macro: structure in, structure out ────────────────────────────
  // assertRange(x, lo, hi) → throws unless lo <= x <= hi. The macro sees the
  // expression nodes, so it can embed them in the error message — a function
  // never could.
  defmacro('assertRange', (args) {
    final value = args[0];
    final lo = args[1];
    final hi = args[2];
    return [
      'unless',
      ['&&', ['>=', value, lo], ['<=', value, hi]],
      ['throw', ['RangeError', '"value out of range"']],
    ];
  });

  // ── An async macro: full Dart, builds a class from a name + fields ────────
  // defendpoint Name { Type field; ... } → a typed request DTO with a
  // const constructor. `async` here stands in for the real superpower:
  // a Tier-3 macro can `await` files, HTTP, or a database at generation time.
  defAsyncMacro('defendpoint', (args) async {
    final name = unquote(args[0] as String);
    final fields = args.skip(1).cast<List>().toList();

    final decls = fields.map((f) => '  final ${f[0]} ${f[1]};').join('\n');
    final params = fields.map((f) {
      final optional = (f[0] as String).endsWith('?');
      return optional ? 'this.${f[1]}' : 'required this.${f[1]}';
    }).join(', ');

    return 'class $name {\n'
        '$decls\n\n'
        '  const $name({$params});\n'
        '}';
  });
}
