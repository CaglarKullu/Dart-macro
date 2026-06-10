/// Tokenizer for .dmacro source files.
/// Converts Dart-like source text into a flat list of [Token]s.
library;

enum TK {
  lparen,
  rparen,
  lbrace,
  rbrace,
  lbracket,
  rbracket,
  semi,
  comma,
  dot,
  cascade,
  question,
  colon,
  arrow,
  plus,
  minus,
  star,
  slash,
  eq,
  neq,
  lt,
  gt,
  lte,
  gte,
  and,
  or,
  bang,
  assign,
  nullCoalesce,
  ident,
  integer,
  float,
  string,
  at,
  eof,
}

class Token {
  final TK kind;
  final Object? value;
  final int line;
  final int col;
  const Token(this.kind, this.value, [this.line = 0, this.col = 0]);

  @override
  String toString() => '${kind.name}($value)';
}

class TokenizerException implements Exception {
  final String message;
  final int position;
  final int line;
  final int col;
  final String sourceLine;
  const TokenizerException(this.message, this.position,
      {this.line = 0, this.col = 0, this.sourceLine = ''});

  @override
  String toString() {
    final loc = line > 0 ? '$line:$col: ' : '';
    if (sourceLine.isEmpty) return 'TokenizerException: $loc$message';
    final caret = ' ' * (col > 0 ? col - 1 : 0) + '^';
    return 'TokenizerException: $loc$message\n  $sourceLine\n  $caret';
  }
}

class Tokenizer {
  final String source;
  int _pos = 0;
  int _line = 1;
  int _col = 1;

  Tokenizer(this.source);

  List<Token> tokenize() {
    final tokens = <Token>[];
    while (_pos < source.length) {
      _skipWhitespaceAndComments();
      if (_pos >= source.length) break;
      final tok = _nextToken();
      if (tok != null) tokens.add(tok);
    }
    tokens.add(Token(TK.eof, null, _line, _col));
    return tokens;
  }

  /// Returns (line, col, sourceLine) for a byte offset.
  (int, int, String) _locAt(int offset) {
    int line = 1, col = 1;
    for (int i = 0; i < offset && i < source.length; i++) {
      if (source[i] == '\n') {
        line++;
        col = 1;
      } else {
        col++;
      }
    }
    // Extract the source line for the caret display.
    int start = offset;
    while (start > 0 && source[start - 1] != '\n') {
      start--;
    }
    int end = offset;
    while (end < source.length && source[end] != '\n') {
      end++;
    }
    return (line, col, source.substring(start, end));
  }

  Token? _nextToken() {
    final startLine = _line;
    final startCol = _col;
    final c = source[_pos];

    // Two-character operators — check first (order matters: .. before ., ?? before ?, => before =)
    final two =
        _pos + 1 < source.length ? source.substring(_pos, _pos + 2) : '';
    switch (two) {
      case '==':
        _advance2();
        return Token(TK.eq, '==', startLine, startCol);
      case '!=':
        _advance2();
        return Token(TK.neq, '!=', startLine, startCol);
      case '<=':
        _advance2();
        return Token(TK.lte, '<=', startLine, startCol);
      case '>=':
        _advance2();
        return Token(TK.gte, '>=', startLine, startCol);
      case '&&':
        _advance2();
        return Token(TK.and, '&&', startLine, startCol);
      case '||':
        _advance2();
        return Token(TK.or, '||', startLine, startCol);
      case '..':
        _advance2();
        return Token(TK.cascade, '..', startLine, startCol);
      case '??':
        _advance2();
        return Token(TK.nullCoalesce, '??', startLine, startCol);
      case '=>':
        _advance2();
        return Token(TK.arrow, '=>', startLine, startCol);
    }

    // Single-character tokens
    switch (c) {
      case '(':
        _advance1();
        return Token(TK.lparen, '(', startLine, startCol);
      case ')':
        _advance1();
        return Token(TK.rparen, ')', startLine, startCol);
      case '{':
        _advance1();
        return Token(TK.lbrace, '{', startLine, startCol);
      case '}':
        _advance1();
        return Token(TK.rbrace, '}', startLine, startCol);
      case '[':
        _advance1();
        return Token(TK.lbracket, '[', startLine, startCol);
      case ']':
        _advance1();
        return Token(TK.rbracket, ']', startLine, startCol);
      case ';':
        _advance1();
        return Token(TK.semi, ';', startLine, startCol);
      case ',':
        _advance1();
        return Token(TK.comma, ',', startLine, startCol);
      case '.':
        _advance1();
        return Token(TK.dot, '.', startLine, startCol);
      case '?':
        _advance1();
        return Token(TK.question, '?', startLine, startCol);
      case ':':
        _advance1();
        return Token(TK.colon, ':', startLine, startCol);
      case '+':
        _advance1();
        return Token(TK.plus, '+', startLine, startCol);
      case '-':
        _advance1();
        return Token(TK.minus, '-', startLine, startCol);
      case '*':
        _advance1();
        return Token(TK.star, '*', startLine, startCol);
      case '/':
        _advance1();
        return Token(TK.slash, '/', startLine, startCol);
      case '<':
        _advance1();
        return Token(TK.lt, '<', startLine, startCol);
      case '>':
        _advance1();
        return Token(TK.gt, '>', startLine, startCol);
      case '!':
        _advance1();
        return Token(TK.bang, '!', startLine, startCol);
      case '=':
        _advance1();
        return Token(TK.assign, '=', startLine, startCol);
      case '@':
        _advance1();
        return Token(TK.at, '@', startLine, startCol);
    }

    // String literal
    if (c == '"') return _readString(startLine, startCol);

    // Number
    if (_isDigit(c)) return _readNumber(startLine, startCol);

    // Identifier or keyword
    if (_isAlpha(c)) return _readIdent(startLine, startCol);

    // Skip unknown character
    _advance1();
    return null;
  }

  Token _readString(int line, int col) {
    _advance1(); // opening "
    final buf = StringBuffer();
    while (_pos < source.length && source[_pos] != '"') {
      if (source[_pos] == '\\') {
        _advance1();
        if (_pos >= source.length) break;
        buf.write(switch (source[_pos]) {
          'n' => '\n',
          't' => '\t',
          '"' => '"',
          '\\' => '\\',
          _ => source[_pos],
        });
      } else {
        buf.write(source[_pos]);
      }
      _advance1();
    }
    if (_pos >= source.length) {
      final (el, ec, sl) = _locAt(_pos);
      throw TokenizerException('Unterminated string literal', _pos,
          line: el, col: ec, sourceLine: sl);
    }
    _advance1(); // closing "
    return Token(TK.string, '"${buf.toString()}"', line, col);
  }

  Token _readNumber(int line, int col) {
    final buf = StringBuffer();
    while (_pos < source.length &&
        (_isDigit(source[_pos]) || source[_pos] == '.')) {
      buf.write(source[_pos]);
      _advance1();
    }
    final s = buf.toString();
    if (s.contains('.')) {
      return Token(TK.float, double.parse(s), line, col);
    }
    return Token(TK.integer, int.parse(s), line, col);
  }

  Token _readIdent(int line, int col) {
    final buf = StringBuffer();
    while (_pos < source.length &&
        (_isAlphaNum(source[_pos]) || source[_pos] == '_')) {
      buf.write(source[_pos]);
      _advance1();
    }
    // Allow trailing ! for macro names: swap!, assert!
    // Only if NOT followed by = (which would be !=, already handled)
    if (_pos < source.length &&
        source[_pos] == '!' &&
        (_pos + 1 >= source.length || source[_pos + 1] != '=')) {
      buf.write('!');
      _advance1();
    }
    return Token(TK.ident, buf.toString(), line, col);
  }

  void _skipWhitespaceAndComments() {
    while (_pos < source.length) {
      final c = source[_pos];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        _advance1();
      } else if (_pos + 1 < source.length &&
          source[_pos] == '/' &&
          source[_pos + 1] == '/') {
        while (_pos < source.length && source[_pos] != '\n') {
          _advance1();
        }
      } else {
        break;
      }
    }
  }

  void _advance1() {
    if (_pos < source.length && source[_pos] == '\n') {
      _line++;
      _col = 1;
    } else {
      _col++;
    }
    _pos++;
  }

  void _advance2() {
    _advance1();
    _advance1();
  }

  static bool _isDigit(String c) =>
      c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
  static bool _isAlpha(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 65 && code <= 90) ||
        (code >= 97 && code <= 122) ||
        c == '_';
  }

  static bool _isAlphaNum(String c) => _isAlpha(c) || _isDigit(c);
}
