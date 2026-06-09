/// dmacro quick demo — run with: dart run example/main.dart
library;

import '../lib/src/core.dart';
import '../lib/src/builtins.dart';

void main() {
  registerBuiltins();

  _section('defrecord — generates an entire immutable class');
  _show(
    'defrecord Payment { double amount; String currency; String? reference; }',
    expand([
      'defrecord',
      'Payment',
      ['double', 'amount'],
      ['String', 'currency'],
      ['String?', 'reference'],
    ]),
  );

  _section('defunion — sealed class hierarchy (state machine)');
  _show(
    'defunion OrderStatus { Pending {} Shipped { String trackingId; } Cancelled { String reason; } }',
    expand([
      'defunion',
      'OrderStatus',
      ['Pending'],
      [
        'Shipped',
        ['String', 'trackingId']
      ],
      [
        'Cancelled',
        ['String', 'reason']
      ],
    ]),
  );

  _section('unless — custom control flow (expands to if + !)');
  _show(
    'unless (amount > 0) { throw Exception("bad amount"); }',
    expand([
      'unless',
      ['>', 'amount', 0],
      ['throw', 'Exception("bad amount")']
    ]),
  );

  _section('assertThat — error message contains the source expression');
  _show(
    'assertThat(itemCount > 0)',
    expand([
      'assert-that',
      ['>', 'itemCount', 0]
    ]),
  );

  _section('swap! — injects a temp variable into the caller scope');
  _show(
    'swap!(a, b)',
    expand([
      'do',
      ['swap!', 'a', 'b']
    ]),
  );

  _section('withRetry — stateful retry loop with injected counter');
  _show(
    'withRetry(3, postJson(endpoint, payload))',
    expand([
      'with-retry',
      3,
      ['postJson', 'endpoint', 'payload']
    ]),
  );
}

void _section(String title) {
  print('\n${'─' * 70}');
  print('▸ $title');
  print('${'─' * 70}');
}

void _show(String source, Node expanded) {
  print('\nYou write:\n  $source\n\nEmitted Dart:');
  for (final line in emit(expanded).split('\n')) {
    print('  $line');
  }
}
