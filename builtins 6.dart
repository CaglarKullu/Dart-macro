/// Built-in macros — written with the typed node API.
///
/// Compare the two macro definition styles:
///
///   RAW LIST:   defmacro('unless', (args) => ['if', ['!', args[0]], args[1]]);
///   TYPED API:  defmacro('unless', (args) => $if($not(args[0]), args[1]));
///
/// Same output. The typed API just reads like Dart.
library;

import 'core.dart';
import 'nodes.dart';

void registerBuiltins() {
  _registerControlFlow();
  _registerBinding();
  _registerDataClass();
}

void _registerControlFlow() {
  defmacro('unless', (args) => $if($not(args[0]), args[1]));

  defmacro('when', (args) => $if(args[0], args[1]));

  defmacro('with-retry', (args) {
    final n    = args[0];
    final body = args[1];
    return $forIn('_attempt', 'Iterable.generate(${emit(n)})',
      $try(body, '_e',
        $if($eq('_attempt', $sub(n, 1)),
          $throw('_e'),
          $call('print', [$str('Retrying...')]),
        ),
      ),
    );
  });

  defmacro('assert-that', (args) => $if(
    $not(args[0]),
    $throw('AssertionError("Expected: ${emit(args[0])}, got false")'),
  ));
}

void _registerBinding() {
  defmacro('swap!', (args) => $do([
    $let('_tmp', args[0]),
    $set(args[0] as String, args[1]),
    $set(args[1] as String, '_tmp'),
  ]));

  defmacro('and-let', (args) {
    final bindings = args.sublist(0, args.length - 1);
    final body     = args.last;
    var result     = body;
    for (final b in bindings.reversed) {
      final name = (b as List)[0] as String;
      final expr = b[1];
      result = $do([$let(name, expr), result]);
    }
    return result;
  });
}

void _registerDataClass() {
  defmacro('defrecord', (args) {
    final name   = args[0] as String;
    final fields = args.sublist(1)
        .map((f) => Field((f as List)[0] as String, f[1] as String))
        .toList();

    return $class(name, [
      ...fields.map((f) => $field(f.type, f.name)),
      $ctor(name, fields.map((f) => f.name).toList()),
      $copyWith(name, fields),
      $equality(name, fields),
      $hashCode(fields),
      $toString(name, fields),
    ]);
  });

  defmacro('defunion', (args) {
    final name     = args[0] as String;
    final variants = args.sublist(1);
    final variantClasses = variants.map((v) {
      final variantName   = (v as List)[0] as String;
      final variantFields = v.sublist(1)
          .map((f) => Field((f as List)[0] as String, f[1] as String))
          .toList();
      return $class('$variantName extends $name', [
        ...variantFields.map((f) => $field(f.type, f.name)),
        $ctor(variantName, variantFields.map((f) => f.name).toList()),
      ]);
    }).toList();

    return $do(['sealed class $name {}', ...variantClasses]);
  });
}
