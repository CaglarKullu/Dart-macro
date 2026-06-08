/// Tokenizer for .dmacro source files.
/// Converts Dart-like source text into a flat list of [Token]s.
library;

enum TK {
  lparen, rparen, lbrace, rbrace,
  semi, comma, dot, question,
  plus, minus, star, slash,
  eq, neq, lt, gt, lte, gte, and, or,
  bang, assign,
  ident, integer, float, string,
  eof,
}

class Token {
  final TK kind;
  final Object? value;
  const Token(this.kind, this.value);

  @override
  String toString() => '${kind.name}($value)';
}

class TokenizerException implements Exception {
  final String message;
  final int position;
  const TokenizerException(this.message, this.position);
  @override
  String toString() => 'TokenizerException at $position: $message';
}

class Tokenizer {
  final String source;
  int _pos = 0;

  Tokenizer(this.source);

  List<Token> tokenize() {
    final tokens = <Token>[];
    while (_pos < source.length) {
      _skipWhitespaceAndComments();
      if (_pos >= source.length) break;
      final tok = _nextToken();
      if (tok != null) tokens.add(tok);
    }
    tokens.add(const Token(TK.eof, null));
    return tokens;
  }

  Token? _nextToken() {
    final c = source[_pos];

    // Two-character operators — check first
    final two = _pos + 1 < source.length ? source.substring(_pos, _pos + 2) : '';
    switch (two) {
      case '==': _pos += 2; return const Token(TK.eq,  '==');
      case '!=': _pos += 2; return const Token(TK.neq, '!=');
      case '<=': _pos += 2; return const Token(TK.lte, '<=');
      case '>=': _pos += 2; return const Token(TK.gte, '>=');
      case '&&': _pos += 2; return const Token(TK.and, '&&');
      case '||': _pos += 2; return const Token(TK.or,  '||');
    }

    // Single-character tokens
    switch (c) {
      case '(': _pos++; return const Token(TK.lparen,   '(');
      case ')': _pos++; return const Token(TK.rparen,   ')');
      case '{': _pos++; return const Token(TK.lbrace,   '{');
      case '}': _pos++; return const Token(TK.rbrace,   '}');
      case ';': _pos++; return const Token(TK.semi,     ';');
      case ',': _pos++; return const Token(TK.comma,    ',');
      case '.': _pos++; return const Token(TK.dot,      '.');
      case '?': _pos++; return const Token(TK.question, '?');
      case '+': _pos++; return const Token(TK.plus,     '+');
      case '-': _pos++; return const Token(TK.minus,    '-');
      case '*': _pos++; return const Token(TK.star,     '*');
      case '/': _pos++; return const Token(TK.slash,    '/');
      case '<': _pos++; return const Token(TK.lt,       '<');
      case '>': _pos++; return const Token(TK.gt,       '>');
      case '!': _pos++; return const Token(TK.bang,     '!');
      case '=': _pos++; return const Token(TK.assign,   '=');
    }

    // String literal
    if (c == '"') return _readString();

    // Number
    if (_isDigit(c)) return _readNumber();

    // Identifier or keyword
    if (_isAlpha(c)) return _readIdent();

    // Skip unknown character
    _pos++;
    return null;
  }

  Token _readString() {
    _pos++; // opening "
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
    _pos++; // closing "
    // Keep surrounding quotes — emitter outputs them verbatim as a Dart string literal
    return Token(TK.string, '"${buf.toString()}"');
  }

  Token _readNumber() {
    final start = _pos;
    while (_pos < source.length && (_isDigit(source[_pos]) || source[_pos] == '.')) {
      _pos++;
    }
    final s = source.substring(start, _pos);
    if (s.contains('.')) {
      return Token(TK.float, double.parse(s));
    }
    return Token(TK.integer, int.parse(s));
  }

  Token _readIdent() {
    final start = _pos;
    while (_pos < source.length && (_isAlphaNum(source[_pos]) || source[_pos] == '_')) {
      _pos++;
    }
    // Allow trailing ! for macro names: swap!, assert!
    // Only if NOT followed by = (which would be !=, already handled)
    if (_pos < source.length &&
        source[_pos] == '!' &&
        (_pos + 1 >= source.length || source[_pos + 1] != '=')) {
      _pos++;
    }
    return Token(TK.ident, source.substring(start, _pos));
  }

  void _skipWhitespaceAndComments() {
    while (_pos < source.length) {
      final c = source[_pos];
      if (c == ' ' || c == '\t' || c == '\n' || c == '\r') {
        _pos++;
      } else if (_pos + 1 < source.length &&
                 source[_pos] == '/' && source[_pos + 1] == '/') {
        while (_pos < source.length && source[_pos] != '\n') _pos++;
      } else {
        break;
      }
    }
  }

  static bool _isDigit(String c) => c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
  static bool _isAlpha(String c) {
    final code = c.codeUnitAt(0);
    return (code >= 65 && code <= 90) || (code >= 97 && code <= 122) || c == '_';
  }
  static bool _isAlphaNum(String c) => _isAlpha(c) || _isDigit(c);
}
