/// Parses Dart source code to extract annotated class declarations.
/// Uses a hand-rolled character-level parser rather than package:analyzer
/// so there are zero external dependencies.
library;

import 'models.dart';

class DartParser {
  /// Returns all classes that have at least one recognised annotation.
  List<ClassInfo> parse(String source) {
    final classes = <ClassInfo>[];
    int i = 0;

    while (i < source.length) {
      // Skip comments
      if (_startsWith(source, '//', i)) {
        i = _skipLineComment(source, i);
        continue;
      }
      if (_startsWith(source, '/*', i)) {
        i = _skipBlockComment(source, i);
        continue;
      }
      // Skip strings
      if (source[i] == '"' || source[i] == "'") {
        i = _skipString(source, i);
        continue;
      }

      // Look for @Annotation (possibly multiple)
      if (source[i] == '@') {
        final annos = <String>[];
        int j = i;

        // Collect consecutive annotations
        while (j < source.length && source[j] == '@') {
          final annoEnd = _readAnnotation(source, j);
          if (annoEnd == null) break;
          annos.add(annoEnd.$1);
          j = _skipWhitespace(source, annoEnd.$2);
        }

        if (annos.isEmpty) {
          i++;
          continue;
        }

        // After annotations, skip 'abstract', 'final', 'base', 'sealed'
        j = _skipWhitespace(source, j);
        for (final kw in ['abstract', 'final', 'base', 'sealed', 'mixin']) {
          if (_startsWith(source, kw, j) &&
              !_isIdentChar(source, j + kw.length)) {
            j = _skipWhitespace(source, j + kw.length);
          }
        }

        // Expect 'class'
        if (!_startsWith(source, 'class', j) || _isIdentChar(source, j + 5)) {
          i++;
          continue;
        }
        j += 5;
        j = _skipWhitespace(source, j);

        // Read class name
        final nameEnd = _readIdentifier(source, j);
        if (nameEnd == null) {
          i++;
          continue;
        }
        final className = nameEnd.$1;
        j = nameEnd.$2;

        // Skip type parameters, extends, implements, with — up to '{'
        while (j < source.length && source[j] != '{') {
          j++;
        }
        if (j >= source.length) break;

        final bodyStart = j;
        final bodyEnd = _findMatchingBrace(source, bodyStart);
        if (bodyEnd == -1) break;

        final body = source.substring(bodyStart + 1, bodyEnd);
        final fields = _parseFields(body);

        classes.add(ClassInfo(
          name: className,
          annotations: annos,
          fields: fields,
          bodyStart: bodyStart,
          bodyEnd: bodyEnd,
        ));

        i = bodyEnd + 1;
        continue;
      }

      i++;
    }

    return classes;
  }

  // ─── Field parsing ────────────────────────────────────────────────────────

  List<FieldInfo> _parseFields(String body) {
    // Strip nested method/constructor bodies so we only see class-level lines.
    final flat = _flattenBody(body);
    final fields = <FieldInfo>[];

    // Pattern: [static] [final|late final|late|var] Type[?] name [= ...] ;
    final pattern = RegExp(
      r'(?:^|\n)\s*'
      r'(?:static\s+)?' // optional static
      r'(final\s+|late\s+final\s+|late\s+|var\s+)?' // optional modifier
      r'((?:[A-Z]\w*|int|double|num|String|bool|dynamic|Object|List|Map|Set|Iterable|Future|Stream)'
      r'(?:<[^;]*?>)?' // optional generics (non-greedy)
      r'\s*\??)' // optional ?
      r'\s+(\w+)' // field name
      r'\s*(?:=[^;]*)?\s*;', // optional initialiser + ;
    );

    for (final m in pattern.allMatches(flat)) {
      final modifier = (m.group(1) ?? '').trim();
      final type = m.group(2)!.trim();
      final name = m.group(3)!.trim();

      // Filter out false positives
      if (_isKeyword(name)) continue;
      if (type == 'void') continue;
      if (name == 'super' || name == 'this') continue;

      fields.add(FieldInfo(
        name: name,
        type: type,
        isFinal: modifier.contains('final'),
      ));
    }

    return fields;
  }

  /// Removes the contents of nested `{ }` blocks (method bodies) so we only
  /// have field declarations at class scope.
  String _flattenBody(String body) {
    final buf = StringBuffer();
    int depth = 0;
    int i = 0;

    while (i < body.length) {
      if (_startsWith(body, '//', i)) {
        if (depth == 0) {
          final end = body.indexOf('\n', i);
          buf.write(end == -1 ? body.substring(i) : body.substring(i, end + 1));
          i = end == -1 ? body.length : end + 1;
        } else {
          i = _skipLineComment(body, i);
        }
        continue;
      }
      final c = body[i];
      if (c == '{') {
        depth++;
        i++;
        continue;
      }
      if (c == '}') {
        depth--;
        i++;
        continue;
      }
      if (depth == 0) buf.write(c);
      i++;
    }

    return buf.toString();
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  /// Returns (annotationName, indexAfterAnnotation) or null.
  (String, int)? _readAnnotation(String s, int i) {
    if (s[i] != '@') return null;
    i++;
    final id = _readIdentifier(s, i);
    if (id == null) return null;
    int j = id.$2;
    // skip optional (...)
    if (j < s.length && s[j] == '(') {
      int depth = 0;
      while (j < s.length) {
        if (s[j] == '(') {
          depth++;
        } else if (s[j] == ')') {
          depth--;
          if (depth == 0) {
            j++;
            break;
          }
        }
        j++;
      }
    }
    return (id.$1, j);
  }

  (String, int)? _readIdentifier(String s, int i) {
    if (i >= s.length) return null;
    if (!RegExp(r'[a-zA-Z_$]').hasMatch(s[i])) return null;
    final start = i;
    while (i < s.length && RegExp(r'\w').hasMatch(s[i])) {
      i++;
    }
    return (s.substring(start, i), i);
  }

  int _findMatchingBrace(String s, int open) {
    int depth = 0;
    for (int i = open; i < s.length; i++) {
      if (s[i] == '{') {
        depth++;
      } else if (s[i] == '}') {
        depth--;
        if (depth == 0) return i;
      }
    }
    return -1;
  }

  int _skipWhitespace(String s, int i) {
    while (i < s.length &&
        (s[i] == ' ' || s[i] == '\t' || s[i] == '\n' || s[i] == '\r')) {
      i++;
    }
    return i;
  }

  int _skipLineComment(String s, int i) {
    while (i < s.length && s[i] != '\n') {
      i++;
    }
    return i;
  }

  int _skipBlockComment(String s, int i) {
    i += 2;
    while (i < s.length - 1) {
      if (s[i] == '*' && s[i + 1] == '/') return i + 2;
      i++;
    }
    return s.length;
  }

  int _skipString(String s, int i) {
    final quote = s[i];
    i++;
    while (i < s.length) {
      if (s[i] == '\\') {
        i += 2;
        continue;
      }
      if (s[i] == quote) return i + 1;
      i++;
    }
    return s.length;
  }

  bool _startsWith(String s, String prefix, int i) =>
      s.length >= i + prefix.length &&
      s.substring(i, i + prefix.length) == prefix;

  bool _isIdentChar(String s, int i) =>
      i < s.length && RegExp(r'\w').hasMatch(s[i]);

  bool _isKeyword(String s) => const {
        'return',
        'if',
        'else',
        'for',
        'while',
        'switch',
        'case',
        'break',
        'continue',
        'new',
        'null',
        'true',
        'false',
        'this',
        'super',
        'void',
        'get',
        'set',
        'async',
        'await',
        'yield',
        'throw',
      }.contains(s);
}
