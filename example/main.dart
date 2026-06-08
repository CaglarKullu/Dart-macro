/// dmacro example — Lisp-style macros in Dart.
///
/// Run:  dart run example/main.dart
///
/// This file itself IS the macro program. The code you write is Dart data
/// (nested lists). The macro system expands it, then emits real Dart.
library;

import '../lib/src/core.dart';
import '../lib/src/builtins.dart';

void main() {
  registerBuiltins();

  // ── 1. Custom control flow (impossible as functions) ──────────────────────

  final unlessExample = ['unless', ['>', 'balance', 0],
    ['print', '"Balance is negative!"'],
  ];

  // ── 2. swap! — variable injection into caller scope ───────────────────────

  final swapExample = ['do',
    ['var', 'x', 1],
    ['var', 'y', 2],
    ['swap!', 'x', 'y'],
    ['print', 'x'],  // prints 2
  ];

  // ── 3. assert-that — error message CONTAINS SOURCE EXPRESSION ────────────
  // A function can only see the value — the macro sees the code itself.

  final assertExample = ['assert-that', ['>', 'amount', 0]];

  // ── 4. with-retry — custom control flow with injected state ──────────────

  final retryExample = ['with-retry', 3, ['fetchData', 'url']];

  // ── 5. defrecord — generates ENTIRE class from one line ──────────────────
  // macro_kit can only append to existing classes.
  // This creates the class itself — fields, ctor, copyWith, ==, hashCode, toString.

  final recordExample = ['defrecord', 'Payment',
    ['double',  'amount'],
    ['String',  'currency'],
    ['String?', 'reference'],
  ];

  // ── 6. defunion — sealed class hierarchy ─────────────────────────────────

  final unionExample = ['defunion', 'PaymentState',
    ['Idle'],
    ['Loading'],
    ['Success',  ['Payment', 'payment']],
    ['Failure',  ['String',  'error']],
  ];

  // ── 7. Macros calling macros ──────────────────────────────────────────────

  final nestedExample = ['unless',
    ['&&', ['>', 'x', 0], ['<', 'x', 10000]],
    ['throw', 'Exception("out of range")'],
  ];

  // ── 8. and-let — cascading bindings ──────────────────────────────────────

  final andLetExample = ['and-let',
    ['user',    ['getUser',    'userId']],
    ['account', ['getAccount', '.-id_user']],
    ['print',   'account'],
  ];

  // ── Pipeline: expand → emit ───────────────────────────────────────────────

  final demos = [
    ('unless — custom control flow',               unlessExample),
    ('swap! — injects temp var into caller scope', swapExample),
    ('assert-that — error contains source expr',   assertExample),
    ('with-retry — stateful retry loop',           retryExample),
    ('defrecord — generates entire class',         recordExample),
    ('defunion — sealed class hierarchy',          unionExample),
    ('macros calling macros',                      nestedExample),
    ('and-let — cascading bindings',               andLetExample),
  ];

  final sep = '─' * 64;

  for (final (title, code) in demos) {
    print('\n$sep');
    print('▸ $title');
    print('\nINPUT:\n  $code');

    final expanded  = expand(code);
    final dartCode  = emit(expanded);

    print('\nEMITTED DART:');
    for (final line in dartCode.split('\n')) {
      print('  $line');
    }
  }
}
