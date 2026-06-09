/// Dart-friendly usage — three approaches compared.
///
/// The problem: Lisp macros need homoiconic syntax (code = data).
/// Dart syntax is not homoiconic. Something has to give.
///
/// This file shows the three practical choices.
library;

import '../lib/src/core.dart';
import '../lib/src/nodes.dart';
import '../lib/src/builtins.dart';

void main() {
  registerBuiltins();

  print('═' * 64);
  print('Three approaches to using macros in Dart');
  print('═' * 64);

  _approach1_Sexpressions();
  _approach2_TypedBuilder();
  _approach3_Hybrid();
  _macroDefinitionComparison();
}

// ─────────────────────────────────────────────────────────────────────────────
// APPROACH 1: S-expression source files (.sexp)
//
// Pros: full power, cleanest syntax for what it is
// Cons: foreign to Dart developers
// ─────────────────────────────────────────────────────────────────────────────

void _approach1_Sexpressions() {
  print('\n▸ APPROACH 1 — S-expression source (.sexp files)\n');

  final source = '''
(defrecord Payment
  (double  amount)
  (String  currency)
  (String? reference))

(defn bool validatePayment ((double amount))
  (unless (> amount 0)
    (throw (Exception "Amount must be positive")))
  (return true))
  ''';

  print('  You write:');
  for (final line in source.trim().split('\n')) {
    print('    $line');
  }
  print('');
  print('  dart run bin/dmacro.dart compile payment.sexp -o payment.dart');
  print('');
  print('  Verdict: powerful, but foreign syntax. Needs tooling support.');
}

// ─────────────────────────────────────────────────────────────────────────────
// APPROACH 2: Typed Dart builder API (no S-expressions visible)
//
// Pros: 100% Dart, no new syntax, great IDE support, fully typed
// Cons: verbose, you're building a description of code rather than writing it
// Best for: code generation tools, not inline application code
// ─────────────────────────────────────────────────────────────────────────────

void _approach2_TypedBuilder() {
  print('▸ APPROACH 2 — Typed Dart builder API\n');

  // You write normal Dart to build and emit code.
  // No S-expressions visible. Just Dart function calls.
  final validateFn = $defn(
    returns: 'bool',
    name: 'validatePayment',
    params: [Param('double', 'amount')],
    body: [
      $call('unless',
          [$gt('amount', 0), $throw('Exception("Amount must be positive")')]),
      $return('true'),
    ],
  );

  print('  You write:');
  print('''
    final validateFn = \$defn(
      returns: "bool",
      name: "validatePayment",
      params: [Param("double", "amount")],
      body: [
        \$call("unless", [\$gt("amount", 0),
          \$throw("Exception(\\"Amount must be positive\\")")]),
        \$return("true"),
      ],
    );
    
    // Then emit:
    print(emit(expand(validateFn)));
  ''');

  print('  Emits:');
  final dartCode = emit(expand(validateFn));
  for (final line in dartCode.split('\n')) {
    print('    $line');
  }

  print('');
  print('  Verdict: 100% Dart. Good for codegen tools and build scripts.');
  print(
      '  Uncomfortable for application code — you\'re building, not writing.\n');
}

// ─────────────────────────────────────────────────────────────────────────────
// APPROACH 3: Hybrid — S-expressions just for the parts that need macros
//
// Keep regular Dart for everything else.
// Use a small inline compile() call at the boundary.
//
// Pros: macro power where needed, normal Dart everywhere else
// Cons: context switch at the boundary
// ─────────────────────────────────────────────────────────────────────────────

void _approach3_Hybrid() {
  print('▸ APPROACH 3 — Hybrid: normal Dart + inline compile() calls\n');

  print('  // In your build script or code generator:');
  print('');
  print('''
  // Normal Dart for most things.
  // compile() only at the points that need macro power.

  final models = compile(\'\'\'
    (defrecord Payment
      (double  amount)
      (String  currency)
      (String? reference))

    (defrecord TransferRequest
      (Payment payment)
      (String  fromAccount)
      (String  toAccount))
  \'\'\');

  // Normal Dart for the rest of your app.
  // The generated Dart code gets written to a file:
  File(\'models.g.dart\').writeAsString(models);
  ''');

  print('  Verdict: S-expressions are quarantined to data-model declarations.');
  print('  The syntax is foreign but the SCOPE is small and well-defined.');
  print(
      '  Similar to SQL or regex — a different language for a specific purpose.\n');
}

// ─────────────────────────────────────────────────────────────────────────────
// The honest summary: what ACTUALLY works
// ─────────────────────────────────────────────────────────────────────────────

void _macroDefinitionComparison() {
  print('▸ THE KEY INSIGHT — where the API lives matters\n');

  print('''
  ┌───────────────────────────────────────────────────────────┐
  │                                                           │
  │  Macro DEFINITION (who writes them: library authors)      │
  │  ✅ 100% Dart — fully solved by typed node API            │
  │                                                           │
  │    defmacro("unless",                                     │
  │      (args) => \$if(\$not(args[0]), args[1]));              │
  │                                                           │
  │    defmacro("defrecord", (args) {                         │
  │      final name = args[0] as String;                      │
  │      final fields = args.sublist(1)                       │
  │        .map((f) => Field(f[0], f[1])).toList();           │
  │      return \$class(name, [                               │
  │        ...fields.map((f) => \$field(f.type, f.name)),     │
  │        \$ctor(name, fields.map((f) => f.name).toList()),  │
  │        \$copyWith(name, fields),                          │
  │        \$equality(name, fields),                          │
  │        ...                                                │
  │      ]);                                                  │
  │    });                                                    │
  │                                                           │
  │  Macro USE (who uses them: application developers)        │
  │  ⚠️  Three options — each with a tradeoff                 │
  │                                                           │
  │  A. S-expression files (.sexp): cleanest, foreign feel    │
  │  B. Typed builder API: 100% Dart, verbose                 │
  │  C. Hybrid: S-expressions for codegen, Dart elsewhere     │
  │  D. Dart-like files (.dmacro): looks like Dart  ◀ BUILT   │
  │                                                           │
  │  Option D — the "inline Dart syntax" that earlier looked  │
  │  like a future layer — now EXISTS. The .dmacro tokenizer  │
  │  + parser (Phase 3) accept Dart-like syntax and produce   │
  │  the same AST as the reader, so it is the recommended     │
  │  path today. See example/payment.dmacro.                  │
  │                                                           │
  └───────────────────────────────────────────────────────────┘
  ''');

  print('▸ PRACTICAL RECOMMENDATION\n');
  print('''
  For a Dart package today:

  1. Define macros in Dart using the typed node API (\$if, \$not, etc.)
  2. Publish them as a normal pub.dev package
  3. Users write .dmacro files (Dart-like) or .sexp files (S-expression)
  4. `dmacro compile` regenerates a complete .dart file (committed, like build_runner output)

  This gives you:
  - Macro DEFINITIONS in pure Dart ✅
  - Real expression-level transforms (unlike macro_kit) ✅
  - Full Dart language power inside macros ✅
  - Compile-time I/O — read JSON schemas / OpenAPI specs at build time ✅
  - No build_runner, no WebSocket, no daemon process ✅
  - Inline syntax that looks like Dart (.dmacro) ✅  ← the parser layer is built
  ''');
}
