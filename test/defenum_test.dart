library;

import 'package:test/test.dart';
import 'package:dart_macros/dart_macros.dart';

void main() {
  setUpAll(registerBuiltins);
  setUp(resetEnumRegistry);

  // ─── defenum macro: output ────────────────────────────────────────────────────
  //
  // The defenum macro returns a raw Dart string atom (not a node) to prevent
  // expand() from re-invoking itself on the returned value.

  group('defenum macro — output', () {
    test('returns a Dart enum string with fromJson/toJson', () {
      final result = expand(['defenum', 'Status', 'active', 'inactive']);
      expect(result, isA<String>());
      final code = result as String;
      expect(code, contains('enum Status {'));
      expect(code, contains('active,'));
      expect(code, contains('inactive;'));
      expect(code, contains('Status.values.byName(s)'));
      expect(code, contains('String toJson() => name;'));
    });

    test('registers the enum name as a side effect', () {
      expect(isRegisteredEnum('Priority'), isFalse);
      expand(['defenum', 'Priority', 'low', 'medium', 'high']);
      expect(isRegisteredEnum('Priority'), isTrue);
    });

    test('empty enum is valid', () {
      final result = expand(['defenum', 'Empty']) as String;
      expect(result, equals('enum Empty {}'));
    });
  });

  // ─── emitter — programmatic path ($defEnum) ───────────────────────────────────

  group(r'defenum emitter node ($defEnum)', () {
    test('emits Dart enum with fromJson/toJson', () {
      final code = emit(['defenum', 'Status', ['active', 'inactive', 'pending']]);
      expect(code, contains('enum Status {'));
      expect(code, contains('active,'));
      expect(code, contains('inactive,'));
      expect(code, contains('pending;'));
      expect(code, contains('factory Status.fromJson(String s)'));
      expect(code, contains('Status.values.byName(s)'));
      expect(code, contains('String toJson() => name;'));
    });

    test('emits single-value enum', () {
      final code = emit(['defenum', 'Singleton', ['only']]);
      expect(code, contains('enum Singleton {'));
      expect(code, contains('only;'));
    });
  });

  // ─── .dmacro parser ──────────────────────────────────────────────────────────

  group('defenum parser (.dmacro syntax)', () {
    test('parses block syntax into flat node', () {
      final tokens = Tokenizer('defenum Status { active, inactive, pending }')
          .tokenize();
      final nodes = DartLikeParser(tokens).parseProgram();
      expect(nodes.length, equals(1));
      final node = nodes[0] as List;
      expect(node[0], equals('defenum'));
      expect(node[1], equals('Status'));
      // Flat form — values as args, not wrapped in a list yet (macro wraps them).
      expect(node.sublist(2), equals(['active', 'inactive', 'pending']));
    });

    test('allows trailing comma', () {
      final tokens = Tokenizer('defenum X { a, b, }').tokenize();
      final nodes = DartLikeParser(tokens).parseProgram();
      final node = nodes[0] as List;
      expect(node.sublist(2), equals(['a', 'b']));
    });

    test('allows no commas', () {
      final tokens = Tokenizer('defenum X { a b c }').tokenize();
      final nodes = DartLikeParser(tokens).parseProgram();
      final node = nodes[0] as List;
      expect(node.sublist(2), equals(['a', 'b', 'c']));
    });
  });

  // ─── defrecord integration ────────────────────────────────────────────────────

  group('defrecord with defenum field', () {
    test('fromJson uses values.byName for registered enum', () {
      expand(['defenum', 'Status', 'active', 'inactive']);
      final code = compileDartLike('''
defenum Status { active, inactive }

defrecord Order {
  String id;
  Status status;
}
''');
      expect(code, contains('Status.values.byName('));
    });

    test('toJson uses .name for registered enum', () {
      final code = compileDartLike('''
defenum Status { active, inactive }

defrecord Order {
  String id;
  Status status;
}
''');
      expect(code, contains('status.name'));
    });

    test('nullable enum field uses guard + values.byName', () {
      final code = compileDartLike('''
defenum Priority { low, high }

defrecord Task {
  String title;
  Priority? priority;
}
''');
      // Nullable guard: json['priority'] == null ? null : ...
      expect(code, contains("json['priority'] == null ? null :"));
      expect(code, contains('Priority.values.byName('));
      // toJson uses ?.name
      expect(code, contains('priority?.name'));
    });

    test('non-enum field is unaffected', () {
      final code = compileDartLike('''
defenum Status { active }

defrecord Item {
  String name;
  Status status;
}
''');
      // String field still uses simple cast, not values.byName
      expect(code, contains("json['name'] as String"));
    });

    test('unregistered bare-identifier field is treated as nested record', () {
      final code = compileDartLike('''
defrecord Address {
  String street;
}

defrecord Person {
  String name;
  Address address;
}
''');
      // Address treated as a nested record, not an enum
      expect(code, contains('Address.fromJson('));
      expect(code, isNot(contains('values.byName')));
    });
  });

  // ─── full compileDartLike round-trip ─────────────────────────────────────────

  group('compileDartLike full round-trip', () {
    test('defenum + defrecord emits analyzer-clean Dart structure', () {
      final code = compileDartLike('''
defenum Status { active, inactive, pending }

defrecord Order {
  String id;
  double amount;
  Status status;
}
''');
      // Enum definition present
      expect(code, contains('enum Status {'));
      // Class definition present
      expect(code, contains('class Order {'));
      // Constructor
      expect(code, contains('const Order({'));
      // copyWith
      expect(code, contains('Order copyWith('));
      // fromJson with enum-aware decode
      expect(code, contains('Status.values.byName('));
      // toJson with .name
      expect(code, contains('status.name'));
    });

    test('registry is cleared at the start of each compile', () {
      // First compile registers Status
      compileDartLike('defenum Status { active }');
      expect(isRegisteredEnum('Status'), isTrue,
          reason: 'registered during compile');

      // Second compile resets the registry before running, so Status is gone
      compileDartLike('defenum Other { x }');
      expect(isRegisteredEnum('Status'), isFalse,
          reason: 'cleared at start of second compile');
      expect(isRegisteredEnum('Other'), isTrue,
          reason: 'second compile registered Other');
    });
  });

  // ─── S-expression (.sexp) path ───────────────────────────────────────────────

  group('defenum via S-expression reader', () {
    test('expand works on sexp form', () {
      final result = expand(['defenum', 'Color', 'red', 'green', 'blue']);
      expect(result, isA<String>());
      expect(result as String, contains('enum Color {'));
      expect(isRegisteredEnum('Color'), isTrue);
    });

    test('compileDartLike from sexp string', () async {
      final code = await asyncCompile('''
(defenum Color red green blue)

(defrecord Pixel
  (String  name)
  (Color   color))
''');
      expect(code, contains('enum Color {'));
      expect(code, contains('Color.values.byName('));
      expect(code, contains('color.name'));
    });
  });
}
