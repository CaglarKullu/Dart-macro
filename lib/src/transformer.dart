/// Applies macro generators to a Dart source string.
/// Idempotent: running twice produces the same result.
library;

import 'generator.dart';
import 'dart_source_parser.dart';

const _blockStart = '  // ━━━ dart_macros generated ━━━';
const _blockEnd = '  // ━━━ end dart_macros ━━━';

class TransformResult {
  final String source;
  final int classesTransformed;
  final List<String> classNames;

  const TransformResult({
    required this.source,
    required this.classesTransformed,
    required this.classNames,
  });

  bool get changed => classesTransformed > 0;
}

class Transformer {
  final DartParser _parser = DartParser();

  TransformResult transform(String source) {
    // 1. Strip any previously generated blocks (idempotency)
    final stripped = _stripGenerated(source);

    // 2. Parse annotated classes
    final classes = _parser.parse(stripped);
    if (classes.isEmpty) {
      return TransformResult(
          source: source, classesTransformed: 0, classNames: []);
    }

    // 3. Build insertion map: bodyEnd offset → generated code
    //    Process in reverse order so earlier offsets stay valid after edits.
    final transformed = <String>[];
    var result = stripped;

    // Collect all (bodyEnd, code) pairs in forward order, then apply in reverse.
    final insertions = <(int, String)>[];

    for (final cls in classes) {
      // Collect ALL generated code for this class into ONE marker block
      final parts = <String>[];

      for (final entry in macroRegistry.entries) {
        if (cls.hasAnnotation(entry.key)) {
          parts.add(entry.value.generate(cls));
          transformed.add(cls.name);
        }
      }

      if (parts.isNotEmpty) {
        final block = '$_blockStart\n\n${parts.join('\n\n')}\n$_blockEnd';
        insertions.add((cls.bodyEnd, '\n$block\n'));
      }
    }

    // Apply in reverse so earlier indices stay correct
    for (final (bodyEnd, code) in insertions.reversed) {
      result = result.substring(0, bodyEnd) + code + result.substring(bodyEnd);
    }

    return TransformResult(
      source: result,
      classesTransformed: transformed.length,
      classNames: transformed,
    );
  }

  /// Removes previously generated blocks so we start fresh each run.
  String _stripGenerated(String source) {
    final lines = source.split('\n');
    final out = <String>[];
    bool inBlock = false;

    for (final line in lines) {
      if (line.trimRight() == _blockStart) {
        inBlock = true;
        // Also remove the blank line before the block if present
        if (out.isNotEmpty && out.last.trim().isEmpty) out.removeLast();
        continue;
      }
      if (line.trimRight() == _blockEnd) {
        inBlock = false;
        continue;
      }
      if (!inBlock) out.add(line);
    }

    return out.join('\n');
  }

  /// Preview mode — returns a unified-diff-style string showing changes.
  String preview(String source) {
    final result = transform(source);
    if (!result.changed) return '(no changes)';

    final original = source.split('\n');
    final updated = result.source.split('\n');
    final buf = StringBuffer();

    // Very simple line diff
    int i = 0, j = 0;
    while (i < original.length || j < updated.length) {
      final a = i < original.length ? original[i] : null;
      final b = j < updated.length ? updated[j] : null;

      if (a == b) {
        buf.writeln('  $a');
        i++;
        j++;
      } else if (a != null && !result.source.contains(a)) {
        buf.writeln('- $a');
        i++;
      } else {
        buf.writeln('+ $b');
        j++;
      }
    }

    return buf.toString();
  }
}
