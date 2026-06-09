import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:dmacro/dmacro.dart';

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
        'defrecord',
        'Payment',
        ['double', 'amount'],
        ['String', 'currency'],
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
      final fields =
          members.whereType<List>().where((m) => m[0] == 'field').toList();
      final amount = fields.firstWhere((f) => f[2] == 'amount');
      final currency = fields.firstWhere((f) => f[2] == 'currency');
      expect(amount[1], equals('double'));
      expect(currency[1], equals('String'));
    });

    test('optional fields are nullable', () async {
      final result = await asyncExpand(
        ['defFromJsonSchema', '"example/schema_demo/schemas/payment.json"'],
      ) as List;
      final members = result.sublist(2);
      final fields =
          members.whereType<List>().where((m) => m[0] == 'field').toList();
      final reference = fields.firstWhere((f) => f[2] == 'reference');
      expect(reference[1], equals('String?'));
    });

    test('array items map to List<T>', () async {
      final result = await asyncExpand(
        ['defFromJsonSchema', '"example/schema_demo/schemas/payment.json"'],
      ) as List;
      final members = result.sublist(2);
      final fields =
          members.whereType<List>().where((m) => m[0] == 'field').toList();
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
      const src =
          'defFromJsonSchema("example/schema_demo/schemas/payment.json");';
      final out = await asyncCompileDartLike(src);
      expect(out, contains('class Payment'));
      expect(out, contains('final double amount;'));
      expect(out, contains('copyWith'));
    });

    test('output is deterministic', () async {
      const src =
          'defFromJsonSchema("example/schema_demo/schemas/payment.json");';
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
      final result = await asyncExpand([
        'do',
        ['swap!', 'a', 'b']
      ]) as List;
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
      final form = [
        'if',
        'cond',
        ['let', 'x', 1]
      ];
      final once = await asyncExpand(form);
      final twice = await asyncExpand(once);
      expect(once, equals(twice));
    });
  });

  // ─── Demo: generate and write models.dart ────────────────────────────────────

  group('schema demo — generate models.dart', () {
    test('generates and writes example/schema_demo/models.dart', () async {
      const src =
          'defFromJsonSchema("example/schema_demo/schemas/payment.json");';
      final dart = await asyncCompileDartLike(src);
      File('example/schema_demo/models.dart').writeAsStringSync(dart);
      expect(dart, contains('class Payment'));
    });
  });

  // ─── defAllFromJsonSchema ─────────────────────────────────────────────────────

  group('schema format → DateTime', () {
    late Directory tmpDir;
    setUp(() => tmpDir = Directory.systemTemp.createTempSync('dmacro_dt_'));
    tearDown(() => tmpDir.deleteSync(recursive: true));

    test('string with format date-time/date maps to DateTime', () async {
      File('${tmpDir.path}/event.json').writeAsStringSync(jsonEncode({
        'title': 'Event',
        'type': 'object',
        'required': ['id', 'startsAt'],
        'properties': {
          'id': {'type': 'string'},
          'startsAt': {'type': 'string', 'format': 'date-time'},
          'day': {'type': 'string', 'format': 'date'},
        },
      }));
      final result = await asyncExpand(
        ['defFromJsonSchema', '"${tmpDir.path}/event.json"'],
      ) as List;
      final fields =
          result.sublist(2).whereType<List>().where((m) => m[0] == 'field');
      expect(
          fields.firstWhere((f) => f[2] == 'startsAt')[1], equals('DateTime'));
      expect(fields.firstWhere((f) => f[2] == 'day')[1], equals('DateTime?'));
    });

    test('generated DateTime field round-trips through JSON', () async {
      File('${tmpDir.path}/event.json').writeAsStringSync(jsonEncode({
        'title': 'Event',
        'type': 'object',
        'required': ['id', 'startsAt'],
        'properties': {
          'id': {'type': 'string'},
          'startsAt': {'type': 'string', 'format': 'date-time'},
        },
      }));
      final code = await asyncCompileDartLike(
        'defFromJsonSchema("${tmpDir.path}/event.json");',
      );
      final prog = File('${tmpDir.path}/prog.dart')..writeAsStringSync('''
$code

void main() {
  final e = Event(id: 'a', startsAt: DateTime.utc(2026, 1, 2, 3, 4, 5));
  final back = Event.fromJson(e.toJson());
  if (back != e) throw 'round-trip mismatch: \$back';
  if (e.toJson()['startsAt'] is! String) throw 'DateTime not serialized to String';
  print('ok');
}
''');
      final r = await Process.run('dart', ['run', prog.path]);
      expect(r.exitCode, 0, reason: '${r.stderr}\n${r.stdout}\n$code');
      expect('${r.stdout}'.trim(), 'ok');
    });
  });

  group('defAllFromJsonSchema', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('dmacro_schema_test_');
    });
    tearDown(() => tmpDir.deleteSync(recursive: true));

    test('generates a do-form with one record per file', () async {
      File('${tmpDir.path}/user.json').writeAsStringSync(jsonEncode({
        'title': 'User',
        'type': 'object',
        'required': ['id', 'name'],
        'properties': {
          'id': {'type': 'integer'},
          'name': {'type': 'string'},
        },
      }));
      File('${tmpDir.path}/address.json').writeAsStringSync(jsonEncode({
        'title': 'Address',
        'type': 'object',
        'required': ['street'],
        'properties': {
          'street': {'type': 'string'},
          'city': {'type': 'string'},
        },
      }));

      final result = await asyncExpand(
        ['defAllFromJsonSchema', '"${tmpDir.path}"'],
      ) as List;

      // Top-level 'do' node expanded — we get a defclass for each schema
      final out = emit(result);
      expect(out, contains('class User'));
      expect(out, contains('class Address'));
      expect(out, contains('final int id;'));
      expect(out, contains('final String street;'));
    });

    test('files are processed in alphabetical order (deterministic)', () async {
      File('${tmpDir.path}/b_schema.json').writeAsStringSync(jsonEncode({
        'title': 'BSchema',
        'type': 'object',
        'required': ['x'],
        'properties': {
          'x': {'type': 'integer'}
        },
      }));
      File('${tmpDir.path}/a_schema.json').writeAsStringSync(jsonEncode({
        'title': 'ASchema',
        'type': 'object',
        'required': ['y'],
        'properties': {
          'y': {'type': 'string'}
        },
      }));

      final result = await asyncExpand(
        ['defAllFromJsonSchema', '"${tmpDir.path}"'],
      ) as List;
      final out = emit(result);
      // Both classes present regardless of creation order
      expect(out, contains('class ASchema'));
      expect(out, contains('class BSchema'));
    });

    test('output is deterministic', () async {
      File('${tmpDir.path}/item.json').writeAsStringSync(jsonEncode({
        'title': 'Item',
        'type': 'object',
        'required': ['id'],
        'properties': {
          'id': {'type': 'integer'}
        },
      }));

      resetGensym();
      final a =
          emit(await asyncExpand(['defAllFromJsonSchema', '"${tmpDir.path}"']));
      resetGensym();
      final b =
          emit(await asyncExpand(['defAllFromJsonSchema', '"${tmpDir.path}"']));
      expect(a, equals(b));
    });

    test('missing directory throws StateError with path', () async {
      await expectLater(
        asyncExpand(['defAllFromJsonSchema', '"no/such/dir"']),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('no/such/dir'),
          ),
        ),
      );
    });

    test('empty directory throws StateError', () async {
      await expectLater(
        asyncExpand(['defAllFromJsonSchema', '"${tmpDir.path}"']),
        throwsA(isA<StateError>()),
      );
    });
  });

  // ─── defFromOpenApi ───────────────────────────────────────────────────────────

  group('defFromOpenApi', () {
    test('extracts a named schema from components/schemas', () async {
      final result = await asyncExpand([
        'defFromOpenApi',
        '"example/openapi_demo/petstore.json"',
        '"Pet"',
      ]) as List;
      final out = emit(result);
      expect(out, contains('class Pet'));
      expect(out, contains('final int id;'));
      expect(out, contains('final String name;'));
    });

    test('required fields are non-nullable', () async {
      final result = await asyncExpand([
        'defFromOpenApi',
        '"example/openapi_demo/petstore.json"',
        '"Pet"',
      ]) as List;
      final out = emit(result);
      expect(out, contains('final int id;'));
      expect(out, contains('final String name;'));
    });

    test('optional fields are nullable', () async {
      final result = await asyncExpand([
        'defFromOpenApi',
        '"example/openapi_demo/petstore.json"',
        '"Pet"',
      ]) as List;
      final out = emit(result);
      expect(out, contains('final String? tag;'));
    });

    test('\$ref fields map to the referenced type name', () async {
      final result = await asyncExpand([
        'defFromOpenApi',
        '"example/openapi_demo/petstore.json"',
        '"Pet"',
      ]) as List;
      final out = emit(result);
      // category is a $ref to Category — should map to the type name
      expect(out, contains('Category?'));
    });

    test('can extract a different schema from the same file', () async {
      final result = await asyncExpand([
        'defFromOpenApi',
        '"example/openapi_demo/petstore.json"',
        '"Category"',
      ]) as List;
      final out = emit(result);
      expect(out, contains('class Category'));
      expect(out, contains('final String name;'));
      expect(out, contains('final int? id;'));
    });

    test('missing file throws StateError with path', () async {
      await expectLater(
        asyncExpand([
          'defFromOpenApi',
          '"no/such/spec.json"',
          '"Pet"',
        ]),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('no/such/spec.json'),
          ),
        ),
      );
    });

    test('unknown schema name throws StateError listing available schemas',
        () async {
      await expectLater(
        asyncExpand([
          'defFromOpenApi',
          '"example/openapi_demo/petstore.json"',
          '"NoSuchSchema"',
        ]),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            allOf(contains('NoSuchSchema'), contains('Pet')),
          ),
        ),
      );
    });

    test('missing components/schemas throws StateError', () async {
      late Directory tmpDir;
      tmpDir = Directory.systemTemp.createTempSync('dmacro_openapi_test_');
      addTearDown(() => tmpDir.deleteSync(recursive: true));

      File('${tmpDir.path}/empty.json')
          .writeAsStringSync(jsonEncode({'openapi': '3.0.0'}));

      await expectLater(
        asyncExpand([
          'defFromOpenApi',
          '"${tmpDir.path}/empty.json"',
          '"Thing"',
        ]),
        throwsA(isA<StateError>()),
      );
    });

    test('compiles through asyncCompileDartLike', () async {
      const src =
          'defFromOpenApi("example/openapi_demo/petstore.json", "Category");';
      final out = await asyncCompileDartLike(src);
      expect(out, contains('class Category'));
      expect(out, contains('final String name;'));
    });
  });

  // ─── Schema enum generation ───────────────────────────────────────────────

  group('schema enum generation', () {
    late Directory tmpDir;
    setUp(() => tmpDir = Directory.systemTemp.createTempSync('dmacro_enum_'));
    tearDown(() => tmpDir.deleteSync(recursive: true));

    test('top-level enum schema emits Dart enum', () async {
      File('${tmpDir.path}/status.json').writeAsStringSync(jsonEncode({
        'title': 'Status',
        'type': 'string',
        'enum': ['active', 'inactive', 'pending'],
      }));
      // The defenum macro expands the node to a raw Dart string.
      final result = await asyncExpand(
        ['defFromJsonSchema', '"${tmpDir.path}/status.json"'],
      ) as String;
      expect(result, contains('enum Status {'));
      expect(result, contains('active'));
      expect(result, contains('inactive'));
      expect(result, contains('pending'));
      expect(result, contains('values.byName(s)'));
    });

    test('defenum node emits valid Dart enum with fromJson/toJson', () {
      final out = emit(['defenum', 'Status', ['active', 'inactive']]);
      expect(out, contains('enum Status'));
      expect(out, contains('active'));
      expect(out, contains('inactive'));
      expect(out, contains('factory Status.fromJson(String s)'));
      expect(out, contains('values.byName(s)'));
      expect(out, contains('String toJson() => name'));
    });

    test('inline enum property generates both enum declaration and record',
        () async {
      File('${tmpDir.path}/order.json').writeAsStringSync(jsonEncode({
        'title': 'Order',
        'type': 'object',
        'required': ['id', 'status'],
        'properties': {
          'id': {'type': 'string'},
          'status': {
            'type': 'string',
            'enum': ['pending', 'paid', 'cancelled'],
          },
        },
      }));
      final code = await asyncCompileDartLike(
        'defFromJsonSchema("${tmpDir.path}/order.json");',
      );
      expect(code, contains('enum Status'));
      expect(code, contains('pending'));
      expect(code, contains('class Order'));
      expect(code, contains('final Status status;'));
    });

    test('enum field serializes via values.byName and .name', () async {
      File('${tmpDir.path}/order.json').writeAsStringSync(jsonEncode({
        'title': 'Order',
        'type': 'object',
        'required': ['id', 'status'],
        'properties': {
          'id': {'type': 'string'},
          'status': {
            'type': 'string',
            'enum': ['pending', 'paid'],
          },
        },
      }));
      final code = await asyncCompileDartLike(
        'defFromJsonSchema("${tmpDir.path}/order.json");',
      );
      expect(code, contains('values.byName'));
      expect(code, contains('.name'));
    });

    test('defAllFromJsonSchema resolves \$ref to top-level enum schema',
        () async {
      File('${tmpDir.path}/status.json').writeAsStringSync(jsonEncode({
        'title': 'Status',
        'type': 'string',
        'enum': ['active', 'inactive'],
      }));
      File('${tmpDir.path}/user.json').writeAsStringSync(jsonEncode({
        'title': 'User',
        'type': 'object',
        'required': ['name'],
        'properties': {
          'name': {'type': 'string'},
          'status': {r'$ref': '#/components/schemas/Status'},
        },
      }));
      final code = emit(await asyncExpand(
        ['defAllFromJsonSchema', '"${tmpDir.path}"'],
      ));
      expect(code, contains('enum Status'));
      expect(code, contains('class User'));
      expect(code, contains('final Status? status;'));
    });

    test('nullable enum field uses sentinel copyWith correctly', () async {
      File('${tmpDir.path}/item.json').writeAsStringSync(jsonEncode({
        'title': 'Item',
        'type': 'object',
        'required': ['id'],
        'properties': {
          'id': {'type': 'string'},
          'priority': {
            'type': 'string',
            'enum': ['low', 'medium', 'high'],
          },
        },
      }));
      final code = await asyncCompileDartLike(
        'defFromJsonSchema("${tmpDir.path}/item.json");',
      );
      expect(code, contains('enum Priority'));
      // Nullable enum field uses sentinel pattern in copyWith
      expect(code, contains('Object? priority = _dmUndefined'));
      // fromJson handles null
      expect(code, contains('priority'));
    });

    test('enum field round-trips through JSON', () async {
      File('${tmpDir.path}/order.json').writeAsStringSync(jsonEncode({
        'title': 'Order',
        'type': 'object',
        'required': ['id', 'status'],
        'properties': {
          'id': {'type': 'string'},
          'status': {
            'type': 'string',
            'enum': ['pending', 'paid', 'cancelled'],
          },
        },
      }));
      final code = await asyncCompileDartLike(
        'defFromJsonSchema("${tmpDir.path}/order.json");',
      );
      final prog = File('${tmpDir.path}/prog.dart')
        ..writeAsStringSync('''
$code

void main() {
  final o = Order(id: 'x', status: Status.paid);
  final back = Order.fromJson(o.toJson());
  if (back.status != o.status) throw 'round-trip mismatch: \${back.status}';
  if (o.toJson()['status'] != 'paid') throw 'toJson wrong: \${o.toJson()["status"]}';
  print('ok');
}
''');
      final r = await Process.run('dart', ['run', prog.path]);
      expect(r.exitCode, 0, reason: '${r.stderr}\n${r.stdout}\n$code');
      expect('${r.stdout}'.trim(), 'ok');
    });
  });
}
