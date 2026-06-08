/// Dart-like parser for .dmacro source files.
///
/// Parses syntax that looks almost exactly like Dart, producing the same
/// [Node] (List<dynamic>) representation as the S-expression reader.
///
/// This means macros work identically regardless of whether you write them
/// in S-expression syntax or Dart-like syntax — the expander sees the same AST.
library;

import 'core.dart';
import 'tokenizer.dart';

class ParseException implements Exception {
  final String message;
  const ParseException(this.message);
  @override
  String toString() => 'ParseException: $message';
}

class DartLikeParser {
  final List<Token> _tokens;
  int _pos = 0;

  DartLikeParser(this._tokens);

  // ─── Entry point ────────────────────────────────────────────────────────────

  List<Node> parseProgram() {
    final nodes = <Node>[];
    while (!_atEnd()) nodes.add(_declaration());
    return nodes;
  }

  // ─── Declarations ────────────────────────────────────────────────────────────

  Node _declaration() {
    if (_check(TK.ident, 'defrecord')) return _defrecord();
    if (_check(TK.ident, 'defunion'))  return _defunion();
    return _fnDecl();
  }

  Node _defrecord() {
    _expect(TK.ident, 'defrecord');
    final name = _expect(TK.ident).value as String;
    _expect(TK.lbrace);
    final fields = <List<String>>[];
    while (!_check(TK.rbrace)) {
      final t = _parseType();
      final n = _expect(TK.ident).value as String;
      _expect(TK.semi);
      fields.add([t, n]);
    }
    _expect(TK.rbrace);
    return ['defrecord', name, ...fields];
  }

  Node _defunion() {
    _expect(TK.ident, 'defunion');
    final name = _expect(TK.ident).value as String;
    _expect(TK.lbrace);
    final variants = <Node>[];
    while (!_check(TK.rbrace)) {
      final vName = _expect(TK.ident).value as String;
      final vFields = <List<String>>[];
      if (_check(TK.lbrace)) {
        _advance();
        while (!_check(TK.rbrace)) {
          final t = _parseType();
          final n = _expect(TK.ident).value as String;
          _expect(TK.semi);
          vFields.add([t, n]);
        }
        _expect(TK.rbrace);
      }
      variants.add([vName, ...vFields]);
    }
    _expect(TK.rbrace);
    return ['defunion', name, ...variants];
  }

  Node _fnDecl() {
    final returnType = _parseType();
    final name       = _expect(TK.ident).value as String;
    _expect(TK.lparen);
    final params = _parseParams();
    _expect(TK.rparen);
    final body = _blockStatements();
    return ['defn', returnType, name, params, ...body];
  }

  List<List<String>> _parseParams() {
    final params = <List<String>>[];
    while (!_check(TK.rparen)) {
      final t = _parseType();
      final n = _expect(TK.ident).value as String;
      params.add([t, n]);
      if (!_check(TK.rparen)) _expect(TK.comma);
    }
    return params;
  }

  /// Parses a Dart type: TypeName[<T, U>][?]
  String _parseType() {
    var name = _expect(TK.ident).value as String;
    // Generic type params: List<String>, Map<String, dynamic>
    if (_check(TK.lt)) {
      _advance();
      final inner = [_parseType()];
      while (_match(TK.comma)) inner.add(_parseType());
      _expect(TK.gt);
      name = '$name<${inner.join(', ')}>';
    }
    // Nullable
    if (_check(TK.question)) { _advance(); name = '$name?'; }
    return name;
  }

  // ─── Statements ──────────────────────────────────────────────────────────────

  List<Node> _blockStatements() {
    _expect(TK.lbrace);
    final stmts = <Node>[];
    while (!_check(TK.rbrace)) stmts.add(_statement());
    _expect(TK.rbrace);
    return stmts;
  }

  Node _blockAsNode() {
    final stmts = _blockStatements();
    return stmts.length == 1 ? stmts[0] : ['do', ...stmts];
  }

  Node _statement() {
    // return expr;
    if (_check(TK.ident, 'return')) {
      _advance();
      final val = _expr();
      _expect(TK.semi);
      return ['return', val];
    }
    // throw expr;
    if (_check(TK.ident, 'throw')) {
      _advance();
      final val = _expr();
      _expect(TK.semi);
      return ['throw', val];
    }
    // final [Type] name = expr;
    if (_check(TK.ident, 'final') || _check(TK.ident, 'var')) {
      final kw = _advance().value as String;
      final kind = kw == 'final' ? 'let' : 'var';
      var name = _expect(TK.ident).value as String;
      // If followed by another IDENT (or IDENT?), the first was the type
      if (_check(TK.ident) || _check(TK.question)) {
        if (_check(TK.question)) { _advance(); name = '$name?'; }
        final realName = _expect(TK.ident).value as String;
        _expect(TK.assign);
        final val = _expr();
        _expect(TK.semi);
        return [kind, realName, val];
      }
      _expect(TK.assign);
      final val = _expr();
      _expect(TK.semi);
      return [kind, name, val];
    }
    // if (cond) { then } [else { else }]
    if (_check(TK.ident, 'if')) {
      _advance();
      _expect(TK.lparen);
      final cond = _expr();
      _expect(TK.rparen);
      final then = _blockAsNode();
      if (_check(TK.ident, 'else')) {
        _advance();
        return ['if', cond, then, _blockAsNode()];
      }
      return ['if', cond, then];
    }
    // while (cond) { body }
    if (_check(TK.ident, 'while')) {
      _advance();
      _expect(TK.lparen);
      final cond = _expr();
      _expect(TK.rparen);
      return ['while', cond, _blockAsNode()];
    }
    // ident-led: assignment, macro call, function call
    if (_check(TK.ident)) {
      // assignment: ident = expr;
      if (_peek2().kind == TK.assign) {
        final name = _advance().value as String;
        _advance(); // consume =
        final val = _expr();
        _expect(TK.semi);
        return ['set!', name, val];
      }
      // expression (handles calls, chains, etc.)
      final expr = _expr();
      // control-flow style macro: macroName(args) { block }
      if (_check(TK.lbrace)) {
        final block = _blockAsNode();
        if (expr is List) return [expr[0], ...expr.sublist(1), block];
        return [expr, block];
      }
      _expect(TK.semi);
      return expr;
    }
    throw ParseException('Unexpected token: ${_peek()}');
  }

  // ─── Expressions (operator precedence) ───────────────────────────────────────

  Node _expr()    => _or();

  Node _or() {
    var left = _and();
    while (_check(TK.or)) { _advance(); left = ['||', left, _and()]; }
    return left;
  }

  Node _and() {
    var left = _equality();
    while (_check(TK.and)) { _advance(); left = ['&&', left, _equality()]; }
    return left;
  }

  Node _equality() {
    var left = _comparison();
    while (_peek().kind == TK.eq || _peek().kind == TK.neq) {
      left = [_advance().value, left, _comparison()];
    }
    return left;
  }

  Node _comparison() {
    var left = _addition();
    while (const {TK.lt, TK.gt, TK.lte, TK.gte}.contains(_peek().kind)) {
      left = [_advance().value, left, _addition()];
    }
    return left;
  }

  Node _addition() {
    var left = _multiplication();
    while (_peek().kind == TK.plus || _peek().kind == TK.minus) {
      left = [_advance().value, left, _multiplication()];
    }
    return left;
  }

  Node _multiplication() {
    var left = _unary();
    while (_peek().kind == TK.star || _peek().kind == TK.slash) {
      left = [_advance().value, left, _unary()];
    }
    return left;
  }

  Node _unary() {
    if (_check(TK.bang)) { _advance(); return ['!', _unary()]; }
    return _postfix();
  }

  Node _postfix() {
    var expr = _primary();
    while (true) {
      if (_check(TK.lparen)) {
        // function/macro call: expr(args)
        _advance();
        final args = _argList();
        _expect(TK.rparen);
        expr = [expr, ...args];
      } else if (_check(TK.dot)) {
        // member access or method call: expr.member or expr.method(args)
        _advance();
        final member = _expect(TK.ident).value as String;
        if (_check(TK.lparen)) {
          _advance();
          final args = _argList();
          _expect(TK.rparen);
          expr = ['.$member', expr, ...args];
        } else {
          expr = ['.-$member', expr];
        }
      } else {
        break;
      }
    }
    return expr;
  }

  Node _primary() {
    final t = _peek();
    if (t.kind == TK.lparen) {
      _advance();
      final e = _expr();
      _expect(TK.rparen);
      return e;
    }
    if (t.kind == TK.string ||
        t.kind == TK.integer ||
        t.kind == TK.float ||
        t.kind == TK.ident) {
      return _advance().value!;
    }
    throw ParseException('Unexpected token in expression: $t');
  }

  List<Node> _argList() {
    final args = <Node>[];
    while (!_check(TK.rparen)) {
      args.add(_expr());
      if (!_check(TK.rparen)) _expect(TK.comma);
    }
    return args;
  }

  // ─── Token helpers ────────────────────────────────────────────────────────────

  Token _peek()  => _tokens[_pos];
  Token _peek2() => _tokens[_pos + 1 < _tokens.length ? _pos + 1 : _pos];

  Token _advance() {
    final t = _tokens[_pos];
    if (_pos < _tokens.length - 1) _pos++;
    return t;
  }

  bool _check(TK kind, [Object? value]) {
    final t = _peek();
    return t.kind == kind && (value == null || t.value == value);
  }

  bool _match(TK kind, [Object? value]) {
    if (_check(kind, value)) { _advance(); return true; }
    return false;
  }

  Token _expect(TK kind, [Object? value]) {
    if (!_check(kind, value)) {
      throw ParseException(
        'Expected ${kind.name}${value != null ? "($value)" : ""}, '
        'got ${_peek()}',
      );
    }
    return _advance();
  }

  bool _atEnd() => _peek().kind == TK.eof;
}

// ─── Convenience function ────────────────────────────────────────────────────

/// Compiles Dart-like (.dmacro) source to Dart.
/// Full pipeline: tokenize → parse → expand macros → emit Dart.
/// Macros must be registered before calling this.
String compileDartLike(String source) {
  final tokens = Tokenizer(source).tokenize();
  final forms  = DartLikeParser(tokens).parseProgram();
  return forms.map((f) => emit(expand(f))).join('\n\n');
}
