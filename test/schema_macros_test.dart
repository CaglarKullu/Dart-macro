import 'dart:io';

import 'package:test/test.dart';
import 'package:dart_macros/dart_macros.dart';

void main() {
  setUpAll(() {
    registerBuiltins();
    registerSchemaMacros();
  });
  setUp(resetGensym);

  // ─── defFromJsonSchema — basic ────────────────────────────────────────────────

  group('defFromJsonSchema — basic', () {
    test('generates same AST as equivalent defrecord', () async {
      // Hand-written equivalent
      resetGensym();
      final manual = expand([
        'defrecord', 'Payment',
        ['double',  'amount'],
        ['String',  'currency'],
        ['String?', 'reference'],
        ['List<String>?', 'tags'],
      ]) as List;

      // Schema-driven
      resetGensym();
      final fromSchema = await asyncExpand(
        ['defFromJsonSchema', '"example/schema_demo/schemas/payment.json"'],
      ) as List;

      expect(fromSchema[0], equals(manual[0])); // defclass
      expect(fromSchema[1], equals(manual[1])); // Payment
      // Same number of members
      expect(fromSchema.length, equals(manual.length));
    });

    test('required fields are non-nullable', () async {
      final result = await asyncExpand(
        ['defFromJsonSchema', '"example/schema_demo/schemas/payment.json"'],
      ) as List;
      final members = result.sublist(2);
      final fields = members.whereType<List>().where((m) => m[0] == 'field').toList();
      final amount   = fields.firstWhere((f) => f[2] == 'amount');
      final currency = fields.firstWhere((f) => f[2] == 'currency');
      expect(amount[1],   equals('double'));
      expect(currency[1], equals('String'));
    });

    test('optional fields are nullable', () async {
      final result = await asyncExpand(
        ['defFromJsonSchema', '"example/schema_demo/schemas/payment.json"'],
      ) as List;
      final members = result.sublist(2);
      final fields = members.whereType<List>().where((m) => m[0] == 'field').toList();
      final reference = fields.firstWhere((f) => f[2] == 'reference');
      expect(reference[1], equals('String?'));
    });

    test('array items map to List<T>', () async {
      final result = await asyncExpand(
        ['defFromJsonSchema', '"example/schema_demo/schemas/payment.json"'],
      ) as List;
      final members = result.sublist(2);
      final fields = members.whereType<List>().where((m) => m[0] == 'field').toList();
      final tags = fields.firstWhere((f) => f[2] == 'tags');
      expect(tags[1], equals('List<String>?'));
    });

    test('emits valid Dart class with all expected members', () async {
      resetGensym();
      final expanded = await asyncExpand(
        ['defFromJsonSchema', '"example/schema_demo/schemas/payment.json"'],
      );
      final out = emit(expanded);
      expect(out, contains('class Payment'));
      expect(out, contains('final double amount;'));
      expect(out, contains('final String currency;'));
      expect(out, contains('final String? reference;'));
      expect(out, contains('final List<String>? tags;'));
      expect(out, contains('copyWith'));
      expect(out, contains('operator =='));
      expect(out, contains('hashCode'));
      expect(out, contains('toString()'));
    });
  });

  // ─── asyncCompileDartLike ─────────────────────────────────────────────────────

  group('asyncCompileDartLike — end to end', () {
    test('compiles defFromJsonSchema in .dmacro source', () async {
      const src = 'defFromJsonSchema("example/schema_demo/schemas/payment.json");';
      final out = await asyncCompileDartLike(src);
      expect(out, contains('class Payment'));
      expect(out, contains('final double amount;'));
      expect(out, contains('copyWith'));
    });

    test('output is deterministic', () async {
      const src = 'defFromJsonSchema("example/schema_demo/schemas/payment.json");';
      final a = await asyncCompileDartLike(src);
      final b = await asyncCompileDartLike(src);
      expect(a, equals(b));
    });
  });

  // ─── Error handling ───────────────────────────────────────────────────────────

  group('defFromJsonSchema — errors', () {
    test('missing file throws StateError with path in message', () async {
      await expectLater(
        asyncExpand(['defFromJsonSchema', '"no/such/file.json"']),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('no/such/file.json'),
          ),
        ),
      );
    });
  });

  // ─── async expander — backward compat ─────────────────────────────────────────

  group('asyncExpand — sync macro backward compat', () {
    test('unless works through async expander', () async {
      final result = await asyncExpand(['unless', 'cond', 'body']) as List;
      expect(result[0], equals('if'));
      expect((result[1] as List)[0], equals('!'));
    });

    test('when works through async expander', () async {
      final result = await asyncExpand(['when', 'c', 'b']) as List;
      expect(result[0], equals('if'));
      expect(result[1], equals('c'));
    });

    test('swap! splice works through async expander', () async {
      resetGensym();
      final result = await asyncExpand(['do', ['swap!', 'a', 'b']]) as List;
      expect(result[0], equals('do'));
      expect(result.length, equals(4));
    });

    test('asyncCompile is deterministic', () async {
      const src = '(let x 1)';
      final a = await asyncCompile(src);
      final b = await asyncCompile(src);
      expect(a, equals(b));
    });

    test('asyncExpand is idempotent for non-macro forms', () async {
      final form = ['if', 'cond', ['let', 'x', 1]];
      final once  = await asyncExpand(form);
      final twice = await asyncExpand(once);
      expect(once, equals(twice));
    });
  });

  // ─── Demo: generate and write models.dart ────────────────────────────────────

  group('schema demo — generate models.dart', () {
    test('generates and writes example/schema_demo/models.dart', () async {
      const src = 'defFromJsonSchema("example/schema_demo/schemas/payment.json");';
      final dart = await asyncCompileDartLike(src);
      File('example/schema_demo/models.dart').writeAsStringSync(dart);
      expect(dart, contains('class Payment'));
    });
  });
}
