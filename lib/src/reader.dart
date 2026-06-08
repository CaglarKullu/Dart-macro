/// S-expression reader — converts source text into [Node] (List<dynamic>).
///
/// This is the "read" phase of the Lisp pipeline:
///   text → Reader → List<dynamic> → Expander → Emitter → Dart
///
/// Syntax:
///   (form1 form2 ...)   — list
///   "hello"             — string literal (emitted with quotes)
///   42   3.14           — numbers
///   true  false  null   — literals
///   symbol              — identifier or operator
///   ; comment           — ignored
library;

import 'core.dart';
import 'gensym.dart';

class ReaderException implements Exception {
  final String message;
  final int position;
  const ReaderException(this.message, this.position);

  @override
  String toString() => 'ReaderException at $position: $message';
}

class Reader {
  final String source;
  int _pos = 0;

  Reader(this.source);

  // ─── Public API ─────────────────────────────────────────────────────────────

  /// Reads all top-level forms from [source].
  List<Node> readAll() {
    final forms = <Node>[];
    _skip();
    while (_pos < source.length) {
      forms.add(_read());
      _skip();
    }
    return forms;
  }

  /// Reads a single form.
  Node readOne() {
    _skip();
    return _read();
  }

  // ─── Internal ───────────────────────────────────────────────────────────────

  Node _read() {
    _skip();
    if (_pos >= source.length) {
      throw ReaderException('Unexpected EOF', _pos);
    }
    final c = source[_pos];
    if (c == '(') return _readList();
    if (c == '"') return _readString();
    return _readAtom();
  }

  /// Reads `(form form ...)` — a list of nodes.
  List<Node> _readList() {
    _pos++; // consume '('
    final items = <Node>[];
    _skip();

    while (_pos < source.length && source[_pos] != ')') {
      items.add(_read());
      _skip();
    }

    if (_pos >= source.length) {
      throw ReaderException('Unclosed parenthesis', _pos);
    }
    _pos++; // consume ')'
    return items;
  }

  /// Reads `"..."` — a Dart string literal.
  /// The quotes are preserved in the returned value so the emitter
  /// outputs them as a Dart string literal rather than an identifier.
  String _readString() {
    _pos++; // consume opening "
    final buf = StringBuffer();

    while (_pos < source.length && source[_pos] != '"') {
      if (source[_pos] == '\\') {
        _pos++;
        if (_pos >= source.length) break;
        buf.write(switch (source[_pos]) {
          'n'  => '\n',
          't'  => '\t',
          '"'  => '"',
          '\\' => '\\',
          _    => source[_pos],
        });
      } else {
        buf.write(source[_pos]);
      }
      _pos++;
    }

    if (_pos >= source.length) {
      throw ReaderException('Unterminated string', _pos);
    }
    _pos++; // consume closing "

    // Keep surrounding quotes — the emitter will output them verbatim,
    // producing a valid Dart string literal.
    return '"${buf.toString()}"';
  }

  /// Reads an atom: number, boolean, null, or symbol/identifier.
  Node _readAtom() {
    final start = _pos;
    while (_pos < source.length &&
           !_isWhitespace(source[_pos]) &&
           source[_pos] != '(' &&
           source[_pos] != ')') {
      _pos++;
    }

    if (_pos == start) {
      throw ReaderException('Empty atom at position $_pos', _pos);
    }

    final token = source.substring(start, _pos);
    return _parseAtom(token);
  }

  Node _parseAtom(String token) {
    if (token == 'true')  return true;
    if (token == 'false') return false;
    if (token == 'null')  return null;

    final asInt = int.tryParse(token);
    if (asInt != null) return asInt;

    final asDouble = double.tryParse(token);
    if (asDouble != null) return asDouble;

    // Everything else: symbol, operator, Dart type, .method, .-prop, etc.
    return token;
  }

  void _skip() {
    while (_pos < source.length) {
      final c = source[_pos];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        _pos++;
      } else if (c == ';') {
        // Line comment — skip to end of line
        while (_pos < source.length && source[_pos] != '\n') { _pos++; }
      } else {
        break;
      }
    }
  }

  static bool _isWhitespace(String c) =>
      c == ' ' || c == '\t' || c == '\n' || c == '\r';
}

// ─── Convenience function ────────────────────────────────────────────────────

/// Compiles a [source] string of S-expressions to Dart source code.
///
/// Full pipeline: read → expand macros → emit Dart.
/// Macros must be registered before calling this.
/// Calls [resetGensym] first for deterministic output.
String compile(String source) {
  resetGensym();
  final forms = Reader(source).readAll();
  return forms
      .map((f) => emit(expand(f)))
      .join('\n\n');
}
