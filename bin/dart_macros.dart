/// dart_macros CLI
///
/// Usage:
///   dart run bin/dart_macros.dart build [path]     — apply macros in place
///   dart run bin/dart_macros.dart preview [path]   — show what would change
///   dart run bin/dart_macros.dart clean [path]     — strip all generated code
import 'dart:io';

import '../lib/src/transformer.dart';

const _reset  = '\x1B[0m';
const _green  = '\x1B[32m';
const _yellow = '\x1B[33m';
const _cyan   = '\x1B[36m';
const _bold   = '\x1B[1m';

void main(List<String> args) async {
  if (args.isEmpty) {
    _printUsage();
    exit(0);
  }

  final command = args.first;
  final paths = args.skip(1).toList();
  if (paths.isEmpty) paths.add('.');

  switch (command) {
    case 'build':
      await _build(paths);
    case 'preview':
      await _runPreview(paths);
    case 'clean':
      await _clean(paths);
    case 'help':
    case '--help':
    case '-h':
      _printUsage();
    default:
      stderr.writeln('Unknown command: $command');
      _printUsage();
      exit(1);
  }
}

// ─── Commands ────────────────────────────────────────────────────────────────

Future<void> _build(List<String> paths) async {
  final transformer = Transformer();
  int totalFiles = 0;
  int totalClasses = 0;

  await _forEachDartFile(paths, (file) async {
    final source = await file.readAsString();
    final result = transformer.transform(source);

    if (result.changed) {
      await file.writeAsString(result.source);
      totalFiles++;
      totalClasses += result.classesTransformed;

      final classes = result.classNames.join(', ');
      print('$_green✓$_reset ${file.path}  $_cyan[$classes]$_reset');
    }
  });

  if (totalFiles == 0) {
    print('${_yellow}No annotated classes found.$_reset');
  } else {
    print(
      '\n$_bold$_green✓ Done.$_reset '
      'Processed $totalClasses class(es) across $totalFiles file(s).',
    );
  }
}

Future<void> _runPreview(List<String> paths) async {
  final transformer = Transformer();

  await _forEachDartFile(paths, (file) async {
    final source = await file.readAsString();
    final result = transformer.transform(source);

    if (result.changed) {
      print('\n$_bold${file.path}$_reset');
      print('─' * 60);
      print(transformer.preview(source));
    }
  });
}

Future<void> _clean(List<String> paths) async {
  // The transformer's _stripGenerated is internal; we expose it via a dummy transform.
  // A real clean would call the strip logic directly.
  final transformer = Transformer();
  int count = 0;

  await _forEachDartFile(paths, (file) async {
    final source = await file.readAsString();
    if (!source.contains('// ━━━ dart_macros generated ━━━')) return;

    // Re-transform with no macros matching strips the block
    final stripped = transformer.transform(source).source;
    await file.writeAsString(stripped);
    print('$_yellow✓ cleaned$_reset ${file.path}');
    count++;
  });

  print('\nCleaned $count file(s).');
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

Future<void> _forEachDartFile(
  List<String> paths,
  Future<void> Function(File) callback,
) async {
  for (final path in paths) {
    final type = FileSystemEntity.typeSync(path);

    if (type == FileSystemEntityType.file) {
      if (path.endsWith('.dart')) await callback(File(path));
    } else if (type == FileSystemEntityType.directory) {
      await for (final entity in Directory(path).list(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          await callback(entity);
        }
      }
    } else {
      stderr.writeln('Not found: $path');
    }
  }
}

void _printUsage() {
  print('''
${_bold}dart_macros$_reset — compile-time macros for Dart

${_bold}Usage:$_reset
  dart run bin/dart_macros.dart build   [path]   Apply macros in-place
  dart run bin/dart_macros.dart preview [path]   Show changes without writing
  dart run bin/dart_macros.dart clean   [path]   Strip all generated blocks
  dart run bin/dart_macros.dart help             Show this help

${_bold}Available annotations:$_reset
  @DataClass()   — copyWith · == · hashCode · toString
  @Singleton()   — private constructor · getInstance()
  @Logged()      — log() · logFields() helpers

${_bold}Example:$_reset
  dart run bin/dart_macros.dart build lib/
''');
}
