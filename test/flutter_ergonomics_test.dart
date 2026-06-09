/// Phase 6 — Flutter ergonomics.
///
/// These are *behavioural* tests: they compile a `defrecord`, append a `main`
/// that exercises the generated class, run it with `dart`, and assert it exits
/// cleanly. That proves the emitted JSON round-trips, equality is structural,
/// and copyWith can clear a nullable field — the things a Flutter model must do.
library;

import 'dart:io';

import 'package:test/test.dart';
import 'package:dart_macros/dart_macros.dart';

/// Compiles [dmacro], appends [mainBody], runs it, and returns the program's
/// stdout. Fails the test if the program exits non-zero.
Future<String> _runGenerated(String dmacro, String mainBody) async {
  final code = compileDartLike(dmacro);
  final dir = Directory.systemTemp.createTempSync('dmacro_ergo_');
  addTearDown(() => dir.deleteSync(recursive: true));
  final file = File('${dir.path}/program.dart')
    ..writeAsStringSync('$code\n\nvoid main() {\n$mainBody\n}\n');

  final result = await Process.run('dart', ['run', file.path]);
  expect(result.exitCode, 0,
      reason: 'generated program failed:\n${result.stderr}\n${result.stdout}\n'
          '--- code ---\n${file.readAsStringSync()}');
  return '${result.stdout}';
}

const _models = '''
defrecord Tag {
  String label;
  int    weight;
}

defrecord Post {
  String       id;
  String?      subtitle;
  List<String> tags;
  List<Tag>    related;
  double       score;
}
''';

void main() {
  setUpAll(registerBuiltins);

  group('6.1 JSON serialization', () {
    test('toJson → fromJson round-trips, including nested records and lists',
        () async {
      final out = await _runGenerated(_models, '''
  final p = Post(
    id: 'a', subtitle: 'sub', tags: ['x', 'y'],
    related: [Tag(label: 't', weight: 1)], score: 1.5,
  );
  final back = Post.fromJson(p.toJson());
  if (back != p) throw 'round-trip mismatch: \$back';
  print('ok');
''');
      expect(out.trim(), 'ok');
    });

    test('double field tolerates an integer JSON value', () async {
      final out = await _runGenerated(_models, '''
  final p = Post.fromJson({
    'id': 'a', 'subtitle': null, 'tags': ['x'], 'related': [], 'score': 2,
  });
  if (p.score != 2.0) throw 'expected 2.0, got \${p.score}';
  print('ok');
''');
      expect(out.trim(), 'ok');
    });

    test('nullable field survives a null round-trip', () async {
      final out = await _runGenerated(_models, '''
  final p = Post(id: 'a', subtitle: null, tags: [], related: [], score: 0.0);
  if (Post.fromJson(p.toJson()).subtitle != null) throw 'null lost';
  print('ok');
''');
      expect(out.trim(), 'ok');
    });

    test('Map<String, dynamic> field round-trips as a JSON object', () async {
      const model = '''
defrecord Config {
  String               id;
  Map<String, dynamic> metadata;
}
''';
      final out = await _runGenerated(model, '''
  final c = Config(id: 'a', metadata: {'k': 1, 'nested': {'x': true}});
  final back = Config.fromJson(c.toJson());
  if (back != c) throw 'round-trip mismatch: \$back';
  print('ok');
''');
      expect(out.trim(), 'ok');
    });
  });

  group('6.2 deep value equality', () {
    test('records with equal-but-distinct collections are == and hash-equal',
        () async {
      final out = await _runGenerated(_models, '''
  Post make() => Post(
    id: 'a', subtitle: null, tags: ['x', 'y'],
    related: [Tag(label: 't', weight: 1)], score: 1.5,
  );
  final a = make(), b = make();
  if (a != b) throw 'not equal';
  if (a.hashCode != b.hashCode) throw 'hash differs';
  if (!{a}.contains(b)) throw 'set keying broken';
  print('ok');
''');
      expect(out.trim(), 'ok');
    });

    test('a difference inside a list is detected', () async {
      final out = await _runGenerated(_models, '''
  final a = Post(id: 'a', subtitle: null, tags: ['x'], related: [], score: 0);
  final b = Post(id: 'a', subtitle: null, tags: ['y'], related: [], score: 0);
  if (a == b) throw 'should differ';
  print('ok');
''');
      expect(out.trim(), 'ok');
    });
  });

  group('6.3 copyWith explicit-null', () {
    test('can set, clear, and preserve a nullable field', () async {
      final out = await _runGenerated(_models, '''
  final base = Post(id: 'a', subtitle: 'hi', tags: [], related: [], score: 0);
  if (base.copyWith(subtitle: 'yo').subtitle != 'yo') throw 'set failed';
  if (base.copyWith(subtitle: null).subtitle != null) throw 'clear failed';
  if (base.copyWith().subtitle != 'hi') throw 'omit failed';
  print('ok');
''');
      expect(out.trim(), 'ok');
    });
  });

  group('emitted shape', () {
    test('defrecord emits fromJson factory and toJson method', () {
      final code = compileDartLike('defrecord A { int x; }');
      expect(code, contains('factory A.fromJson(Map<String, dynamic> json)'));
      expect(code, contains('Map<String, dynamic> toJson()'));
    });
  });
}
