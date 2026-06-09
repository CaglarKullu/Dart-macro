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
      final input = [
        'defn',
        'void',
        'foo',
        [],
        [
          'unless',
          ['>', 'x', 0],
          'y'
        ]
      ];
      final result = expand(input) as List;
      // The inner 'unless' should be expanded
      final bodyStmt = result[4] as List;
      expect(bodyStmt[0], equals('if'));
    });
  });

  group('expand — macro dispatch', () {
    test('unless expands to if with negated condition', () {
      final input = [
        'unless',
        ['>', 'balance', 0],
        ['print', '"negative"']
      ];
      final result = expand(input) as List;
      expect(result[0], equals('if'));
      // condition should be negated: ['!', ['>', 'balance', 0]]
      final cond = result[1] as List;
      expect(cond[0], equals('!'));
      expect(cond[1], equals(['>', 'balance', 0]));
    });

    test('when expands to if without negation', () {
      final input = [
        'when',
        ['>', 'x', 0],
        ['print', '"positive"']
      ];
      final result = expand(input) as List;
      expect(result[0], equals('if'));
      expect(result[1], equals(['>', 'x', 0]));
    });

    test('macro result is re-expanded (macros can expand to macros)', () {
      // unless → if, and the if is itself expanded recursively
      final input = [
        'unless',
        ['>', 'x', 0],
        ['when', 'y', 'z']
      ];
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
      final input = [
        'unless',
        ['>', 'x', 0],
        'y'
      ];
      expect(expand(expand(input)), equals(expand(input)));
    });

    test('expand(expand(x)) == expand(x) for nested macros', () {
      final input = [
        'when',
        'c',
        ['unless', 'x', 'y']
      ];
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
      final out = emit([
        'while',
        ['<', 'i', 10],
        'body'
      ]);
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
      final out = emit([
        'do',
        ['let', 'a', 1],
        ['let', 'b', 2]
      ]);
      expect(out, contains('final a = 1;'));
      expect(out, contains('final b = 2;'));
    });
  });

  group('emit — defn', () {
    test('emits function definition', () {
      final out = emit([
        'defn',
        'int',
        'add',
        [
          ['int', 'a'],
          ['int', 'b']
        ],
        [
          'return',
          ['+', 'a', 'b']
        ],
      ]);
      expect(out, contains('int add(int a, int b)'));
      expect(out, contains('return (a + b)'));
    });
  });

  group('emit — defclass', () {
    test('emits class definition', () {
      final out = emit([
        'defclass',
        'Point',
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
      final out = emit([
        'ctor',
        'Point',
        [
          ['int', 'x'],
          ['int', 'y']
        ]
      ]);
      expect(out, contains('const Point('));
      expect(out, contains('required this.x'));
      expect(out, contains('required this.y'));
    });

    test('nullable fields are optional (no required keyword)', () {
      final out = emit([
        'ctor',
        'Box',
        [
          ['String', 'id'],
          ['String?', 'label']
        ]
      ]);
      expect(out, contains('required this.id'));
      expect(out, isNot(contains('required this.label')));
      expect(out, contains('this.label'));
    });
  });

  group('emit — copywith', () {
    test('emits copyWith method', () {
      final out = emit([
        'copywith',
        'Point',
        [
          ['double', 'x'],
          ['double', 'y']
        ],
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
        'equalop',
        'Point',
        [
          ['double', 'x'],
          ['double', 'y']
        ],
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
        'hashop',
        null,
        [
          ['double', 'x'],
          ['double', 'y']
        ],
      ]);
      expect(out, contains('@override'));
      expect(out, contains('int get hashCode'));
      expect(out, contains('Object.hashAll([x, y])'));
    });
  });

  group('emit — tostringop', () {
    test('emits toString override', () {
      final out = emit([
        'tostringop',
        'Point',
        [
          ['double', 'x'],
          ['double', 'y']
        ],
      ]);
      expect(out, contains('@override'));
      expect(out, contains('String toString()'));
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
      final splice = Splice([
        ['let', 'a', 1]
      ]);
      expect(() => emit(splice), throwsA(isA<StateError>()));
    });
  });

  // ─── emit — unary minus ───────────────────────────────────────────────────────

  group('emit — unary minus', () {
    test('single-arg - is unary (prefix)', () {
      expect(emit(['-', 'x']), equals('-x'));
    });

    test('two-arg - is binary (infix)', () {
      expect(emit(['-', 'a', 'b']), equals('(a - b)'));
    });

    test('unary minus on literal number', () {
      expect(emit(['-', 42]), equals('-42'));
    });
  });

  // ─── emit — null coalesce ─────────────────────────────────────────────────────

  group('emit — null coalesce ??', () {
    test('emits ?? operator', () {
      expect(emit(['??', 'x', '"default"']), equals('(x ?? "default")'));
    });

    test('?? with null literal', () {
      expect(emit(['??', 'value', null]), equals('(value ?? null)'));
    });

    test('nested ?? chains', () {
      final out = emit(['??', ['??', 'a', 'b'], 'c']);
      expect(out, equals('((a ?? b) ?? c)'));
    });
  });

  // ─── emit — await ─────────────────────────────────────────────────────────────

  group('emit — await', () {
    test('emits await expression', () {
      expect(emit(['await', 'future']), equals('await future'));
    });

    test('await on a call expression', () {
      expect(emit(['await', ['fetchData', 'url']]), equals('await fetchData(url)'));
    });

    test('await nested in let binding', () {
      final out = emit(['let', 'result', ['await', ['load', '"path"']]]);
      expect(out, equals('final result = await load("path")'));
    });
  });

  // ─── emit — ternary ?: ───────────────────────────────────────────────────────

  group('emit — ternary ?:', () {
    test('emits ternary conditional', () {
      expect(emit(['?:', 'cond', 'a', 'b']), equals('(cond ? a : b)'));
    });

    test('ternary with comparison condition', () {
      final out = emit(['?:', ['>', 'x', 0], '"pos"', '"neg"']);
      expect(out, equals('((x > 0) ? "pos" : "neg")'));
    });

    test('nested ternaries', () {
      final out = emit(['?:', 'a', ['?:', 'b', 1, 2], 3]);
      expect(out, equals('(a ? (b ? 1 : 2) : 3)'));
    });
  });

  // ─── emit — named argument ───────────────────────────────────────────────────

  group('emit — named argument', () {
    test('emits named: key: value', () {
      expect(emit(['named', 'amount', 100]), equals('amount: 100'));
    });

    test('named arg with string value', () {
      expect(emit(['named', 'label', '"hello"']), equals('label: "hello"'));
    });

    test('named arg inside function call', () {
      final out = emit(['foo', ['named', 'x', 1], ['named', 'y', 2]]);
      expect(out, equals('foo(x: 1, y: 2)'));
    });
  });

  // ─── emit — list literal ─────────────────────────────────────────────────────

  group('emit — list literal', () {
    test('emits empty list', () {
      expect(emit(['list']), equals('[]'));
    });

    test('emits single-element list', () {
      expect(emit(['list', 1]), equals('[1]'));
    });

    test('emits multi-element list', () {
      expect(emit(['list', 'a', 'b', 'c']), equals('[a, b, c]'));
    });

    test('emits list with expression elements', () {
      final out = emit(['list', ['+', 'x', 1], ['-', 'y', 2]]);
      expect(out, equals('[(x + 1), (y - 2)]'));
    });
  });

  // ─── emit — cascade ──────────────────────────────────────────────────────────

  group('emit — cascade', () {
    test('emits cascade with method call', () {
      final out = emit(['cascade', 'sb', ['..write', '"hello"']]);
      expect(out, equals('sb..write("hello")'));
    });

    test('emits cascade with assignment', () {
      final out = emit(['cascade', 'obj', ['..=name', '"Alice"']]);
      expect(out, equals('obj..name = "Alice"'));
    });

    test('emits cascade chain: call then assignment', () {
      final out = emit([
        'cascade',
        'list',
        ['..add', 'item'],
        ['..=length', 0],
      ]);
      expect(out, equals('list..add(item)..length = 0'));
    });

    test('emits cascade with multiple call args', () {
      final out = emit([
        'cascade',
        'buffer',
        ['..write', '"a"', '"b"'],
      ]);
      expect(out, equals('buffer..write("a", "b")'));
    });
  });

  // ─── emit — null-aware method call ─────────────────────────────────────────

  group('emit — null-aware method call ?.', () {
    test('emits ?.method()', () {
      expect(emit(['?.map', 'list', 'fn']), equals('list?.map(fn)'));
    });

    test('emits ?.method() with no args', () {
      expect(emit(['?.isEmpty', 'str']), equals('str?.isEmpty()'));
    });

    test('emits ?.method() with multiple args', () {
      final out = emit(['?.add', 'list', 'a', 'b']);
      expect(out, equals('list?.add(a, b)'));
    });
  });

  // ─── emit — null-aware property access ───────────────────────────────────────

  group('emit — null-aware property access ?.-', () {
    test('emits ?.property', () {
      expect(emit(['?.-length', 'str']), equals('str?.length'));
    });

    test('emits ?.property with nested receiver', () {
      final out = emit(['?.-name', ['.-user', 'ctx']]);
      expect(out, equals('ctx.user?.name'));
    });
  });

  // ─── emit — defenum ───────────────────────────────────────────────────────────

  group('emit — defenum', () {
    test('emits enum with values', () {
      final out = emit(['defenum', 'Status', ['active', 'inactive']]);
      expect(out, contains('enum Status'));
      expect(out, contains('active'));
      expect(out, contains('inactive'));
    });

    test('enum values separated by commas', () {
      final out = emit(['defenum', 'Dir', ['north', 'south', 'east', 'west']]);
      expect(out, contains('north'));
      expect(out, contains('south'));
      expect(out, contains('east'));
      expect(out, contains('west'));
    });

    test('emits fromJson factory using values.byName', () {
      final out = emit(['defenum', 'Status', ['a', 'b']]);
      expect(out, contains('factory Status.fromJson(String s)'));
      expect(out, contains('Status.values.byName(s)'));
    });

    test('emits toJson returning name', () {
      final out = emit(['defenum', 'Status', ['a', 'b']]);
      expect(out, contains('String toJson() => name'));
    });

    test('empty defenum emits valid Dart', () {
      final out = emit(['defenum', 'Empty', []]);
      expect(out, equals('enum Empty {}'));
    });

    test('single-value enum', () {
      final out = emit(['defenum', 'Singleton', ['only']]);
      expect(out, contains('enum Singleton'));
      expect(out, contains('only'));
    });

    test('defenum is treated as a block (no trailing semicolon in do)', () {
      final out = emit([
        'do',
        ['defenum', 'S', ['a']],
        ['let', 'x', 1],
      ]);
      expect(out, isNot(contains('};')));
      expect(out, contains('final x = 1;'));
    });
  });

  // ─── emit — fromjson ─────────────────────────────────────────────────────────

  group('emit — fromjson', () {
    test('emits factory fromJson for scalar fields', () {
      final out = emit([
        'fromjson',
        'Foo',
        [
          ['String', 'name'],
          ['int', 'count']
        ],
      ]);
      expect(out, contains('factory Foo.fromJson(Map<String, dynamic> json)'));
      expect(out, contains("json['name'] as String"));
      expect(out, contains("json['count'] as int"));
    });

    test('double field uses (as num).toDouble()', () {
      final out = emit([
        'fromjson',
        'Foo',
        [
          ['double', 'price']
        ],
      ]);
      expect(out, contains("(json['price'] as num).toDouble()"));
    });

    test('DateTime field uses DateTime.parse', () {
      final out = emit([
        'fromjson',
        'Event',
        [
          ['DateTime', 'at']
        ],
      ]);
      expect(out, contains("DateTime.parse(json['at'] as String)"));
    });

    test('nullable scalar field uses direct cast (no null-guard)', () {
      final out = emit([
        'fromjson',
        'Foo',
        [
          ['String?', 'note']
        ],
      ]);
      expect(out, contains('as String?'));
      expect(out, isNot(contains('== null ? null :')));
    });

    test('List<String> field uses .map().toList()', () {
      final out = emit([
        'fromjson',
        'Foo',
        [
          ['List<String>', 'tags']
        ],
      ]);
      expect(out, contains("json['tags'] as List"));
      expect(out, contains('.toList()'));
    });

    test('Set<String> field uses .map().toSet()', () {
      final out = emit([
        'fromjson',
        'Foo',
        [
          ['Set<String>', 'unique']
        ],
      ]);
      expect(out, contains('.toSet()'));
    });

    test('enum field uses values.byName', () {
      final out = emit([
        'fromjson',
        'Order',
        [
          ['enum:Status', 'status']
        ],
      ]);
      expect(out, contains('Status.values.byName'));
      expect(out, contains("json['status'] as String"));
    });

    test('nullable enum field has null-guard before values.byName', () {
      final out = emit([
        'fromjson',
        'Item',
        [
          ['enum:Priority?', 'priority']
        ],
      ]);
      expect(out, contains("json['priority'] == null ? null"));
      expect(out, contains('Priority.values.byName'));
    });

    test('nested record field uses T.fromJson', () {
      final out = emit([
        'fromjson',
        'Post',
        [
          ['Author', 'author']
        ],
      ]);
      expect(out, contains("Author.fromJson(json['author'] as Map<String, dynamic>)"));
    });
  });

  // ─── emit — tojson ───────────────────────────────────────────────────────────

  group('emit — tojson', () {
    test('emits toJson for scalar fields', () {
      final out = emit([
        'tojson',
        null,
        [
          ['String', 'name'],
          ['int', 'count']
        ],
      ]);
      expect(out, contains('Map<String, dynamic> toJson()'));
      expect(out, contains("'name': name"));
      expect(out, contains("'count': count"));
    });

    test('DateTime field uses toIso8601String()', () {
      final out = emit([
        'tojson',
        null,
        [
          ['DateTime', 'at']
        ],
      ]);
      expect(out, contains('at.toIso8601String()'));
    });

    test('nullable DateTime uses ?.toIso8601String()', () {
      final out = emit([
        'tojson',
        null,
        [
          ['DateTime?', 'at']
        ],
      ]);
      expect(out, contains('at?.toIso8601String()'));
    });

    test('enum field uses .name', () {
      final out = emit([
        'tojson',
        null,
        [
          ['enum:Status', 'status']
        ],
      ]);
      expect(out, contains('status.name'));
    });

    test('nullable enum field uses ?.name', () {
      final out = emit([
        'tojson',
        null,
        [
          ['enum:Priority?', 'priority']
        ],
      ]);
      expect(out, contains('priority?.name'));
    });

    test('List<String> field is passed through directly', () {
      final out = emit([
        'tojson',
        null,
        [
          ['List<String>', 'tags']
        ],
      ]);
      expect(out, contains("'tags': tags"));
      expect(out, isNot(contains('.map(')));
    });

    test('Set<String> field is converted to List', () {
      final out = emit([
        'tojson',
        null,
        [
          ['Set<String>', 'unique']
        ],
      ]);
      expect(out, contains('.toList()'));
    });

    test('nested record field uses .toJson()', () {
      final out = emit([
        'tojson',
        null,
        [
          ['Author', 'author']
        ],
      ]);
      expect(out, contains('author.toJson()'));
    });

    test('nullable record uses ?.toJson()', () {
      final out = emit([
        'tojson',
        null,
        [
          ['Author?', 'author']
        ],
      ]);
      expect(out, contains('author?.toJson()'));
    });
  });

  // ─── emit — defn variants ─────────────────────────────────────────────────────

  group('emit — defn variants', () {
    test('emits arrow body function', () {
      final out = emit([
        'defn',
        'int',
        'square',
        [
          ['int', 'x']
        ],
        '__arrow__',
        ['*', 'x', 'x']
      ]);
      expect(out, contains('int square(int x) =>'));
      expect(out, contains('(x * x)'));
      expect(out, endsWith(';'));
    });

    test('emits async function with Future return type', () {
      final out = emit([
        'defn',
        'async Future<int>',
        'fetchCount',
        [],
        ['return', 42],
      ]);
      expect(out, contains('Future<int> fetchCount()'));
      expect(out, contains('async'));
      expect(out, contains('return 42'));
    });

    test('emits void function with no params', () {
      final out = emit([
        'defn',
        'void',
        'noop',
        [],
      ]);
      expect(out, contains('void noop()'));
    });

    test('emits function with multiple statements', () {
      final out = emit([
        'defn',
        'int',
        'add',
        [
          ['int', 'a'],
          ['int', 'b']
        ],
        ['let', 'sum', ['+', 'a', 'b']],
        ['return', 'sum'],
      ]);
      expect(out, contains('final sum = (a + b);'));
      expect(out, contains('return sum;'));
    });
  });

  // ─── emit — ctor edge cases ───────────────────────────────────────────────────

  group('emit — ctor edge cases', () {
    test('emits const constructor with no params', () {
      expect(emit(['ctor', 'Empty', []]), equals('const Empty();'));
    });

    test('enum-typed field in ctor uses required keyword', () {
      final out = emit([
        'ctor',
        'Order',
        [
          ['enum:Status', 'status']
        ],
      ]);
      expect(out, contains('required this.status'));
    });

    test('nullable enum-typed field in ctor has no required keyword', () {
      final out = emit([
        'ctor',
        'Item',
        [
          ['enum:Priority?', 'priority']
        ],
      ]);
      expect(out, isNot(contains('required this.priority')));
      expect(out, contains('this.priority'));
    });
  });

  // ─── emit — enum field stripping (_resolveType) ───────────────────────────────

  group('emit — _resolveType (enum: prefix stripping)', () {
    test('field emits resolved type for enum field', () {
      expect(emit(['field', 'enum:Status', 'status']),
          equals('final Status status;'));
    });

    test('field emits resolved type for nullable enum field', () {
      expect(emit(['field', 'enum:Priority?', 'priority']),
          equals('final Priority? priority;'));
    });

    test('field does not modify non-enum types', () {
      expect(emit(['field', 'String', 'name']), equals('final String name;'));
      expect(emit(['field', 'String?', 'note']), equals('final String? note;'));
    });

    test('copywith non-nullable enum param uses resolved type', () {
      final out = emit([
        'copywith',
        'Order',
        [
          ['enum:Status', 'status']
        ],
      ]);
      expect(out, contains('Status? status'));
      expect(out, isNot(contains('enum:Status')));
    });

    test('copywith nullable enum uses sentinel (Object?)', () {
      final out = emit([
        'copywith',
        'Item',
        [
          ['enum:Priority?', 'priority']
        ],
      ]);
      expect(out, contains('Object? priority = _dmUndefined'));
      expect(out, contains('priority as Priority?'));
      expect(out, isNot(contains('enum:Priority?')));
    });

    test('equalop with enum field uses == comparison (not _dmEq)', () {
      final out = emit([
        'equalop',
        'Order',
        [
          ['enum:Status', 'status']
        ],
      ]);
      expect(out, contains('other.status == status'));
      expect(out, isNot(contains('_dmEq')));
    });

    test('hashop with enum field uses the field name directly', () {
      final out = emit([
        'hashop',
        null,
        [
          ['enum:Status', 'status']
        ],
      ]);
      expect(out, contains('Object.hashAll([status])'));
      expect(out, isNot(contains('_dmHash')));
    });
  });

  // ─── emit — if spliced multi-statement body ───────────────────────────────────

  group('emit — if with splice-injected body', () {
    test('if with >3 args emits all as then-block (no else)', () {
      // This happens after swap! is spliced into an if body
      final out = emit([
        'if',
        'cond',
        ['let', 'a', 1],
        ['let', 'b', 2],
        ['return', 'a'],
      ]);
      expect(out, contains('if (cond)'));
      expect(out, contains('final a = 1;'));
      expect(out, contains('final b = 2;'));
      expect(out, contains('return a;'));
      expect(out, isNot(contains('else')));
    });
  });

  // ─── emit — block detection (_isBlock) ───────────────────────────────────────

  group('emit — _isBlock / _emitStmt (no spurious semicolons)', () {
    test('if in do body does not get trailing semicolon', () {
      final out = emit([
        'do',
        ['if', 'c', 'x'],
        ['let', 'y', 1],
      ]);
      expect(out, isNot(contains('};')));
      expect(out, contains('final y = 1;'));
    });

    test('while in do body does not get trailing semicolon', () {
      final out = emit([
        'do',
        ['while', 'c', 'body'],
        ['return', 'x'],
      ]);
      expect(out, isNot(contains('};')));
    });

    test('defn in do body does not get trailing semicolon', () {
      final out = emit([
        'do',
        ['defn', 'void', 'f', [], 'x'],
        ['let', 'z', 2],
      ]);
      expect(out, isNot(contains('};')));
    });

    test('raw string ending with } is treated as block', () {
      final out = emit([
        'do',
        'class Foo {}',
        ['let', 'x', 1],
      ]);
      expect(out, isNot(contains('};')));
      expect(out, contains('final x = 1;'));
    });

    test('simple expression in do gets semicolon', () {
      final out = emit([
        'do',
        ['print', '"hello"'],
        ['return', 'x'],
      ]);
      expect(out, contains('print("hello");'));
      expect(out, contains('return x;'));
    });
  });
}
