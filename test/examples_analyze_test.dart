/// Golden test: every example `.dmacro` must compile to Dart that the analyzer
/// accepts with **zero errors**.
///
/// This is the check CLAUDE.md mandates ("Run `dart analyze` on emitted output
/// as part of testing") and the one that guards the project's headline promise:
/// the emitter produces valid, analyzer-clean Dart. It compiles each example
/// through the real CLI (so async schema macros run too) and analyzes the
/// generated file.
library;

import 'dart:io';

import 'package:test/test.dart';

void main() {
  // Discover every example source. Both syntaxes go through the same emitter.
  final sources = Directory('example')
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dmacro') || f.path.endsWith('.sexp'))
      .toList()
    ..sort((a, b) => a.path.compareTo(b.path));

  test('found example sources to analyze', () {
    expect(sources, isNotEmpty);
  });

  late Directory tmpDir;
  setUp(() => tmpDir = Directory.systemTemp.createTempSync('dmacro_analyze_'));
  tearDown(() => tmpDir.deleteSync(recursive: true));

  for (final src in sources) {
    test('emitted Dart is analyzer-clean: ${src.path}', () async {
      final outPath = '${tmpDir.path}/out.dart';

      final compile = await Process.run(
        'dart',
        ['run', 'bin/dmacro.dart', 'compile', src.path, '-o', outPath],
        workingDirectory: Directory.current.path,
      );
      expect(compile.exitCode, 0,
          reason: 'compile failed:\n${compile.stderr}\n${compile.stdout}');

      final analyze = await Process.run(
        'dart',
        ['analyze', outPath],
        workingDirectory: Directory.current.path,
      );

      // `dart analyze` prints "  error - <loc> - <msg> - <rule>" for each error.
      // Infos/warnings are tolerated; hard errors (invalid Dart) are not.
      final out = '${analyze.stdout}${analyze.stderr}';
      final errors = out
          .split('\n')
          .where((l) => l.trimLeft().startsWith('error -'))
          .toList();
      expect(errors, isEmpty,
          reason: 'analyzer reported errors in emitted Dart:\n'
              '${errors.join('\n')}\n\n--- generated ---\n'
              '${File(outPath).readAsStringSync()}');
    });
  }
}
