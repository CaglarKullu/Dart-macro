/// On-demand end-to-end smoke test for the headline "add the dep and go" path.
///
/// Creates a throwaway consumer project that depends on this package by path,
/// then exercises the full promise a new user hits:
///   1. `dart pub get` resolves dmacro (and nothing else — zero runtime deps),
///   2. `dart run dmacro compile` works with no custom entry point,
///   3. a built-in macro (`defrecord`) and a user macro loaded via `useMacros`
///      both expand,
///   4. the generated Dart is analyzer-clean.
///
/// Run from the repository root:
///   dart run tool/smoke_test.dart
///
/// Kept out of the default `dart test` suite because it runs `dart pub get`
/// (network + a few seconds); this is a release-readiness check, not a unit
/// test. Exits non-zero on any failure.
library;

import 'dart:io';

Future<void> main() async {
  final repoRoot = Directory.current.absolute.path;
  final dir = Directory.systemTemp.createTempSync('dmacro_smoke_');
  stdout.writeln('smoke: project at ${dir.path}');

  try {
    Directory('${dir.path}/lib').createSync();
    Directory('${dir.path}/macros').createSync();

    File('${dir.path}/pubspec.yaml').writeAsStringSync('''
name: smoke_app
description: Throwaway consumer project for the dmacro smoke test.
publish_to: none
environment:
  sdk: '>=3.5.0 <4.0.0'
dev_dependencies:
  dmacro:
    path: $repoRoot
''');

    // A user macro library loaded with useMacros — no tool/dmacro.dart.
    File('${dir.path}/macros/app_macros.dart').writeAsStringSync('''
import 'package:dmacro/dmacro.dart';
void registerMacros() {
  defAsyncMacro('defmodel', (args) async {
    final name = unquote(args[0] as String);
    final fields = args.skip(1).cast<List>().toList();
    final decls = fields.map((f) => '  final \${f[0]} \${f[1]};').join('\\n');
    final params = fields.map((f) => 'this.\${f[1]}').join(', ');
    return 'class \$name {\\n\$decls\\n  const \$name(\$params);\\n}';
  });
}
''');

    File('${dir.path}/lib/models.dmacro').writeAsStringSync('''
useMacros("macros/app_macros.dart");

defrecord Point { double x; double y; }

defmodel Tag {
  String label;
  int count;
}
''');

    await _run('dart', ['pub', 'get'], dir.path, 'pub get');
    await _run('dart', ['run', 'dmacro', 'compile', 'lib/models.dmacro'],
        dir.path, 'compile');

    final generated = File('${dir.path}/lib/models.dart');
    if (!generated.existsSync()) {
      _fail('compile produced no lib/models.dart');
    }
    final out = generated.readAsStringSync();
    _expect(out.contains('class Point {'), 'builtin defrecord did not expand');
    _expect(out.contains('Point copyWith('),
        'defrecord did not generate copyWith');
    _expect(out.contains('class Tag {'),
        'user macro (useMacros/defmodel) did not expand');

    await _run('dart', ['analyze', 'lib/models.dart'], dir.path, 'analyze');

    stdout.writeln('\nsmoke: PASS — builtin + useMacros macro compiled and '
        'analyzed clean in a fresh project.');
  } finally {
    dir.deleteSync(recursive: true);
  }
}

Future<void> _run(
    String exe, List<String> args, String cwd, String label) async {
  stdout.writeln('smoke: \$ $exe ${args.join(' ')}');
  final r = await Process.run(exe, args, workingDirectory: cwd);
  if (r.exitCode != 0) {
    stderr.writeln(r.stdout);
    stderr.writeln(r.stderr);
    _fail('$label failed (exit ${r.exitCode})');
  }
}

void _expect(bool cond, String message) {
  if (!cond) _fail(message);
}

Never _fail(String message) {
  stderr.writeln('\nsmoke: FAIL — $message');
  exit(1);
}
