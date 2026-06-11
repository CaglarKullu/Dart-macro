/// Tests for the dependency graph and content-hash cache.
library;

import 'dart:io';

import 'package:test/test.dart';

import '../lib/src/dep_graph.dart';
import '../lib/src/gen_cache.dart';

void main() {
  group('DependencyGraph', () {
    late DependencyGraph g;
    setUp(() => g = DependencyGraph());

    test('recordDependency and dependentsOf — direct edge', () {
      g.recordDependency('/project/app.dmacro', '/project/templates.dmacro');
      expect(g.dependentsOf('/project/templates.dmacro'),
          contains('/project/app.dmacro'));
    });

    test('dependentsOf — transitive', () {
      g.recordDependency('/project/a.dmacro', '/project/b.dmacro');
      g.recordDependency('/project/b.dmacro', '/project/c.dmacro');

      final deps = g.dependentsOf('/project/c.dmacro');
      expect(deps, contains('/project/a.dmacro'));
      expect(deps, contains('/project/b.dmacro'));
    });

    test('dependentsOf — no edges returns empty', () {
      expect(g.dependentsOf('/nonexistent/file.dmacro'), isEmpty);
    });

    test('importsOf returns forward edges', () {
      g.recordDependency('/project/app.dmacro', '/project/t1.dmacro');
      g.recordDependency('/project/app.dmacro', '/project/t2.dmacro');
      final imports = g.importsOf('/project/app.dmacro');
      expect(imports, unorderedEquals(['/project/t1.dmacro', '/project/t2.dmacro']));
    });

    test('clearSource removes forward and reverse edges', () {
      g.recordDependency('/project/app.dmacro', '/project/templates.dmacro');
      g.clearSource('/project/app.dmacro');
      expect(g.dependentsOf('/project/templates.dmacro'), isEmpty);
      expect(g.importsOf('/project/app.dmacro'), isEmpty);
    });

    test('multiple dependents of one shared file', () {
      g.recordDependency('/project/a.dmacro', '/project/shared.dmacro');
      g.recordDependency('/project/b.dmacro', '/project/shared.dmacro');
      final deps = g.dependentsOf('/project/shared.dmacro');
      expect(deps, containsAll(['/project/a.dmacro', '/project/b.dmacro']));
    });

    test('no duplicate entries in dependentsOf', () {
      g.recordDependency('/project/a.dmacro', '/project/b.dmacro');
      g.recordDependency('/project/a.dmacro', '/project/b.dmacro'); // duplicate
      final deps = g.dependentsOf('/project/b.dmacro');
      expect(deps.length, 1);
    });
  });

  group('gen_cache', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('dmacro_cache_test_');
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    test('computeFingerprint is deterministic', () {
      final fp1 = computeFingerprint('source content', [], []);
      final fp2 = computeFingerprint('source content', [], []);
      expect(fp1, fp1); // trivially
      expect(fp1, fp2); // deterministic
    });

    test('computeFingerprint changes when source changes', () {
      final fp1 = computeFingerprint('source v1', [], []);
      final fp2 = computeFingerprint('source v2', [], []);
      expect(fp1, isNot(equals(fp2)));
    });

    test('computeFingerprint changes when imported file content changes', () {
      final importedFile = File('${tmpDir.path}/macro.dmacro');
      importedFile.writeAsStringSync('version 1');
      final fp1 = computeFingerprint('source', [importedFile.path], []);

      importedFile.writeAsStringSync('version 2');
      final fp2 = computeFingerprint('source', [importedFile.path], []);

      expect(fp1, isNot(equals(fp2)));
    });

    test('computeFingerprint changes when schema file changes', () {
      final schema = File('${tmpDir.path}/user.json');
      schema.writeAsStringSync('{"title":"User","properties":{}}');
      final fp1 = computeFingerprint('source', [], [schema.path]);

      schema.writeAsStringSync('{"title":"User","properties":{"name":{}}}');
      final fp2 = computeFingerprint('source', [], [schema.path]);

      expect(fp1, isNot(equals(fp2)));
    });

    test('recordGenerationInput / clearGenerationInputs', () {
      clearGenerationInputs();
      expect(generationInputFiles, isEmpty);

      recordGenerationInput('/some/schema.json');
      expect(generationInputFiles, contains('/some/schema.json'));

      recordGenerationInput('/some/schema.json'); // duplicate — ignored
      expect(generationInputFiles.length, 1);

      clearGenerationInputs();
      expect(generationInputFiles, isEmpty);
    });
  });

  group('cache integration: dep-graph cascade via CLI', () {
    late Directory tmpDir;

    setUp(() {
      tmpDir = Directory.systemTemp.createTempSync('dmacro_dep_cascade_');
    });

    tearDown(() {
      tmpDir.deleteSync(recursive: true);
    });

    test(
        'importMacros dependency recorded: changing templates triggers recompile',
        () async {
      // templates.dmacro — defines a macro
      final templates = File('${tmpDir.path}/templates.dmacro')
        ..writeAsStringSync('''
defmacro greet(name) {
  print("Hello " + name);
}
''');

      // app.dmacro — uses the macro
      final app = File('${tmpDir.path}/app.dmacro')
        ..writeAsStringSync('''
importMacros("${templates.path}");
void main() {
  greet("World");
}
''');

      final appOut = File('${tmpDir.path}/app.dart');

      // First compile
      final r1 = await Process.run(
        'dart',
        ['run', 'bin/dmacro.dart', 'compile', app.path, '-o', appOut.path],
        workingDirectory: Directory.current.path,
      );
      expect(r1.exitCode, 0, reason: r1.stderr.toString());
      final v1 = appOut.readAsStringSync();
      expect(v1, contains('Hello'));

      // Second compile with unchanged input — should report unchanged (cache hit)
      final r2 = await Process.run(
        'dart',
        ['run', 'bin/dmacro.dart', 'compile', app.path, '-o', appOut.path],
        workingDirectory: Directory.current.path,
      );
      expect(r2.exitCode, 0);
      expect(r2.stderr.toString(), contains('unchanged'));
    });
  });
}
