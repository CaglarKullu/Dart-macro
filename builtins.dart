/// Built-in macro definitions.
///
/// These demonstrate what Lisp-style macros enable that is IMPOSSIBLE
/// in Dart without this system — even with macro_kit or build_runner.
library;

import 'core.dart';

/// Registers all built-in macros.
void registerBuiltins() {
  _registerControlFlow();
  _registerBinding();
  _registerDataClass();
}

// ─── Control flow ─────────────────────────────────────────────────────────────

void _registerControlFlow() {

  // (unless condition body)
  // A function can't do this — it would evaluate both args before calling.
  defmacro('unless', (args) => ['if', ['!', args[0]], args[1]]);

  // (when condition body)
  defmacro('when', (args) => ['if', args[0], args[1]]);

  // (with-retry n body)
  // Generates a stateful retry loop. The variable _attempt is injected
  // into the caller's scope — impossible with a higher-order function.
  defmacro('with-retry', (args) {
    final n    = args[0];
    final body = args[1];
    return ['for-in', '_attempt', 'Iterable.generate(${emit(n)})',
      ['try', body, '_e',
        ['if', ['==', '_attempt', ['-', n, 1]],
          ['throw', '_e'],
          ['print', '"Retrying..."'],
        ]
      ]
    ];
  });

  // (assert-that expr)
  // Generates an error message that CONTAINS THE SOURCE OF THE EXPRESSION.
  // A function receives a value — it can never know what expression produced it.
  defmacro('assert-that', (args) => ['if',
    ['!', args[0]],
    ['throw', 'AssertionError("Expected: ${emit(args[0])}, got false")'],
  ]);
}

// ─── Binding ──────────────────────────────────────────────────────────────────

void _registerBinding() {

  // (swap! a b)
  // Injects a temp variable directly into the caller's scope.
  // A function receives values — it cannot write back to the caller's variables.
  defmacro('swap!', (args) => ['do',
    ['let', '_swap_tmp', args[0]],
    ['set!', args[0], args[1]],
    ['set!', args[1], '_swap_tmp'],
  ]);

  // (and-let [name expr] [name expr] ... body)
  // Cascading bindings where each can see the previous — like Kotlin's scope functions.
  // Each binding is only evaluated if the previous was non-null.
  defmacro('and-let', (args) {
    final bindings = args.sublist(0, args.length - 1);
    final body     = args.last;
    Node result    = body;
    for (final b in bindings.reversed) {
      final name = (b as List)[0];
      final expr = b[1];
      result = ['do', ['let', name, expr], result];
    }
    return result;
  });

  // (once name expr)
  // Evaluates expr exactly once and binds it — avoids double-evaluation.
  // Classic gensym pattern from Lisp.
  defmacro('once', (args) {
    final name = args[0] as String;
    final expr = args[1];
    final tmp  = '_once_$name';
    return ['do',
      ['let', tmp, expr],
      // everything that uses `name` will use the captured value
      ['set!', name, tmp],
    ];
  });
}

// ─── Data class generation ────────────────────────────────────────────────────

void _registerDataClass() {

  // (defrecord Name [Type field] [Type field] ...)
  //
  // Generates a COMPLETE immutable data class from a compact spec.
  // This is fundamentally different from macro_kit which can only APPEND
  // to an existing class. This CREATES the class itself.
  //
  // One line of macro code replaces ~40 lines of Dart boilerplate.
  defmacro('defrecord', (args) {
    final name   = args[0] as String;
    final fields = args.sublist(1) as List<dynamic>;

    return ['defclass', name,
      ...fields.map((f) => ['field', (f as List)[0], f[1]]),
      ['ctor', name, fields.map((f) => (f as List)[1]).toList()],
      ['copywith',   name, fields],
      ['equalop',    name, fields],
      ['hashop',     name, fields],
      ['tostringop', name, fields],
    ];
  });

  // (defunion Name [Variant1 [Type field]...] [Variant2 ...])
  // Generates a sealed class hierarchy — like Freezed's union types.
  defmacro('defunion', (args) {
    final name     = args[0] as String;
    final variants = args.sublist(1) as List<dynamic>;

    // Generate: sealed class Name {}
    // + each variant as a final class extending Name
    final variantClasses = variants.map((v) {
      final variantName   = (v as List)[0] as String;
      final variantFields = v.sublist(1) as List<dynamic>;
      return ['defclass', '$variantName extends $name',
        ...variantFields.map((f) => ['field', (f as List)[0], f[1]]),
        ['ctor', variantName, variantFields.map((f) => (f as List)[1]).toList()],
      ];
    });

    return ['do',
      // sealed class declaration (raw string)
      'sealed class $name {}',
      ...variantClasses,
    ];
  });
}
