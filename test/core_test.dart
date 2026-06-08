import 'package:test/test.dart';
import 'package:dart_macros/dart_macros.dart';

void main() {
  setUpAll(registerBuiltins);

  // ─── expand ──────────────────────────────────────────────────────────────────

  group('expand — atoms', () {
    test('string passes through unchanged', () {
      expect(expand('hello'), equals('hello'));
    });

    test('integer passes through unchanged', () {
      expect(expand(42), equals(42));
    });

    test('double passes through unchanged', () {
      expect(expand(3.14), equals(3.14));
    });

    test('bool passes through unchanged', () {
      expect(expand(true), equals(true));
      expect(expand(false), equals(false));
    });

    test('null passes through unchanged', () {
      expect(expand(null), isNull);
    });

    test('empty list passes through unchanged', () {
      expect(expand([]), equals([]));
    });
  });

  group('expand — non-macro lists', () {
    test('unknown form head passes through, children expanded', () {
      final input = ['unknown', 'a', 'b'];
      expect(expand(input), equals(input));
    });

    test('nested lists are recursed into', () {
      final input = ['defn', 'void', 'foo', [], ['unless', ['>', 'x', 0], 'y']];
      final result = expand(input) as List;
      // The inner 'unless' should be expanded
      final bodyStmt = result[4] as List;
      expect(bodyStmt[0], equals('if'));
    });
  });

  group('expand — macro dispatch', () {
    test('unless expands to if with negated condition', () {
      final input = ['unless', ['>', 'balance', 0], ['print', '"negative"']];
      final result = expand(input) as List;
      expect(result[0], equals('if'));
      // condition should be negated: ['!', ['>', 'balance', 0]]
      final cond = result[1] as List;
      expect(cond[0], equals('!'));
      expect(cond[1], equals(['>', 'balance', 0]));
    });

    test('when expands to if without negation', () {
      final input = ['when', ['>', 'x', 0], ['print', '"positive"']];
      final result = expand(input) as List;
      expect(result[0], equals('if'));
      expect(result[1], equals(['>', 'x', 0]));
    });

    test('macro result is re-expanded (macros can expand to macros)', () {
      // unless → if, and the if is itself expanded recursively
      final input = ['unless', ['>', 'x', 0], ['when', 'y', 'z']];
      final result = expand(input) as List;
      expect(result[0], equals('if'));
      // the body is the expanded `when` → `if`
      final body = result[2] as List;
      expect(body[0], equals('if'));
    });
  });

  group('expand — idempotency', () {
    test('expand(expand(x)) == expand(x) for atoms', () {
      expect(expand(expand('hello')), equals(expand('hello')));
      expect(expand(expand(42)), equals(expand(42)));
    });

    test('expand(expand(x)) == expand(x) for unknown lists', () {
      final input = ['defn', 'void', 'foo', []];
      expect(expand(expand(input)), equals(expand(input)));
    });

    test('expand(expand(x)) == expand(x) for macros', () {
      final input = ['unless', ['>', 'x', 0], 'y'];
      expect(expand(expand(input)), equals(expand(input)));
    });

    test('expand(expand(x)) == expand(x) for nested macros', () {
      final input = ['when', 'c', ['unless', 'x', 'y']];
      expect(expand(expand(input)), equals(expand(input)));
    });
  });

  // ─── emit ─────────────────────────────────────────────────────────────────────

  group('emit — atoms', () {
    test('emits null', () {
      expect(emit(null), equals('null'));
    });

    test('emits bool', () {
      expect(emit(true), equals('true'));
      expect(emit(false), equals('false'));
    });

    test('emits int', () {
      expect(emit(42), equals('42'));
    });

    test('emits double', () {
      expect(emit(3.14), equals('3.14'));
    });

    test('emits string (identifier / raw)', () {
      expect(emit('hello'), equals('hello'));
    });
  });

  group('emit — binary operators (variadic)', () {
    test('emits + operator', () {
      expect(emit(['+', 'a', 'b']), equals('(a + b)'));
    });

    test('emits - operator', () {
      expect(emit(['-', 'x', 1]), equals('(x - 1)'));
    });

    test('emits * operator', () {
      expect(emit(['*', 'a', 'b']), equals('(a * b)'));
    });

    test('emits / operator', () {
      expect(emit(['/', 'a', 'b']), equals('(a / b)'));
    });

    test('emits == operator', () {
      expect(emit(['==', 'a', 'b']), equals('(a == b)'));
    });

    test('emits != operator', () {
      expect(emit(['!=', 'a', 'b']), equals('(a != b)'));
    });

    test('emits < operator', () {
      expect(emit(['<', 'a', 'b']), equals('(a < b)'));
    });

    test('emits > operator', () {
      expect(emit(['>', 'a', 'b']), equals('(a > b)'));
    });

    test('emits <= operator', () {
      expect(emit(['<=', 'a', 'b']), equals('(a <= b)'));
    });

    test('emits >= operator', () {
      expect(emit(['>=', 'a', 'b']), equals('(a >= b)'));
    });

    test('emits && operator', () {
      expect(emit(['&&', 'a', 'b']), equals('(a && b)'));
    });

    test('emits || operator', () {
      expect(emit(['||', 'a', 'b']), equals('(a || b)'));
    });

    test('emits ! (unary negation)', () {
      expect(emit(['!', 'x']), equals('!x'));
    });
  });

  group('emit — bindings', () {
    test('emits let (final binding)', () {
      expect(emit(['let', 'x', 42]), equals('final x = 42'));
    });

    test('emits var', () {
      expect(emit(['var', 'x', 0]), equals('var x = 0'));
    });

    test('emits set!', () {
      expect(emit(['set!', 'x', 5]), equals('x = 5'));
    });
  });

  group('emit — control flow', () {
    test('emits return', () {
      expect(emit(['return', 'x']), equals('return x'));
    });

    test('emits throw', () {
      expect(emit(['throw', 'e']), equals('throw e'));
    });

    test('emits if with 2 args (no else)', () {
      final out = emit(['if', 'cond', 'then']);
      expect(out, contains('if (cond)'));
      expect(out, contains('then'));
      expect(out, isNot(contains('else')));
    });

    test('emits if with 3 args (with else)', () {
      final out = emit(['if', 'cond', 'then', 'else_body']);
      expect(out, contains('if (cond)'));
      expect(out, contains('then'));
      expect(out, contains('else'));
      expect(out, contains('else_body'));
    });

    test('emits while', () {
      final out = emit(['while', ['<', 'i', 10], 'body']);
      expect(out, contains('while ('));
      expect(out, contains('(i < 10)'));
      expect(out, contains('body'));
    });

    test('emits for-in', () {
      final out = emit(['for-in', 'x', 'items', 'body']);
      expect(out, contains('for (final x in items)'));
      expect(out, contains('body'));
    });

    test('emits try', () {
      final out = emit(['try', 'body', 'e', 'catchBody']);
      expect(out, contains('try {'));
      expect(out, contains('catch (e)'));
      expect(out, contains('catchBody'));
    });
  });

  group('emit — do (sequence)', () {
    test('emits do as semicolon-separated statements', () {
      final out = emit(['do', ['let', 'a', 1], ['let', 'b', 2]]);
      expect(out, contains('final a = 1;'));
      expect(out, contains('final b = 2;'));
    });
  });

  group('emit — defn', () {
    test('emits function definition', () {
      final out = emit([
        'defn', 'int', 'add',
        [['int', 'a'], ['int', 'b']],
        ['return', ['+', 'a', 'b']],
      ]);
      expect(out, contains('int add(int a, int b)'));
      expect(out, contains('return (a + b)'));
    });
  });

  group('emit — defclass', () {
    test('emits class definition', () {
      final out = emit([
        'defclass', 'Point',
        ['field', 'double', 'x'],
        ['field', 'double', 'y'],
      ]);
      expect(out, contains('class Point'));
      expect(out, contains('final double x;'));
      expect(out, contains('final double y;'));
    });
  });

  group('emit — field', () {
    test('emits final field', () {
      expect(emit(['field', 'int', 'count']), equals('final int count;'));
    });
  });

  group('emit — ctor', () {
    test('emits const constructor with required named params', () {
      final out = emit(['ctor', 'Point', ['x', 'y']]);
      expect(out, contains('const Point('));
      expect(out, contains('required this.x'));
      expect(out, contains('required this.y'));
    });
  });

  group('emit — copywith', () {
    test('emits copyWith method', () {
      final out = emit([
        'copywith', 'Point',
        [['double', 'x'], ['double', 'y']],
      ]);
      expect(out, contains('copyWith('));
      expect(out, contains('double? x'));
      expect(out, contains('double? y'));
      expect(out, contains('x: x ?? this.x'));
    });
  });

  group('emit — equalop', () {
    test('emits == override', () {
      final out = emit([
        'equalop', 'Point',
        [['double', 'x'], ['double', 'y']],
      ]);
      expect(out, contains('@override'));
      expect(out, contains('operator =='));
      expect(out, contains('other is Point'));
      expect(out, contains('other.x == x'));
    });
  });

  group('emit — hashop', () {
    test('emits hashCode override', () {
      final out = emit([
        'hashop', null,
        [['double', 'x'], ['double', 'y']],
      ]);
      expect(out, contains('@override'));
      expect(out, contains('int get hashCode'));
      expect(out, contains('Object.hash(x, y)'));
    });
  });

  group('emit — tostringop', () {
    test('emits toString override', () {
      final out = emit([
        'tostringop', 'Point',
        [['double', 'x'], ['double', 'y']],
      ]);
      expect(out, contains('@override'));
      expect(out, contains("String toString()"));
      expect(out, contains('Point('));
      expect(out, contains(r'$x'));
    });
  });

  group('emit — method call', () {
    test('emits method call on receiver', () {
      expect(emit(['.add', 'list', 'item']), equals('list.add(item)'));
    });

    test('emits method call with no args', () {
      expect(emit(['.isEmpty', 'list']), equals('list.isEmpty()'));
    });
  });

  group('emit — property access', () {
    test('emits property access', () {
      expect(emit(['.-length', 'list']), equals('list.length'));
    });
  });

  group('emit — function call (default)', () {
    test('emits regular function call', () {
      expect(emit(['print', '"hello"']), equals('print("hello")'));
    });

    test('emits function call with multiple args', () {
      expect(emit(['foo', 'a', 'b', 'c']), equals('foo(a, b, c)'));
    });
  });

  group('emit — Splice guard', () {
    test('Splice reaching emit throws StateError', () {
      final splice = Splice([['let', 'a', 1]]);
      expect(() => emit(splice), throwsA(isA<StateError>()));
    });
  });
}
