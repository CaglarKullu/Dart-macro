/// Dart-like parser for .dmacro source files.
///
/// Parses syntax that looks almost exactly like Dart, producing the same
/// [Node] (List<dynamic>) representation as the S-expression reader.
///
/// This means macros work identically regardless of whether you write them
/// in S-expression syntax or Dart-like syntax — the expander sees the same AST.
library;

import 'core.dart';
import 'gensym.dart';
import 'tokenizer.dart';

class ParseException implements Exception {
  final String message;
  final int line;
  final int col;
  const ParseException(this.message, {this.line = 0, this.col = 0});

  @override
  String toString() {
    final loc = line > 0 ? '$line:$col: ' : '';
    return 'ParseException: $loc$message';
  }
}

class DartLikeParser {
  final List<Token> _tokens;
  int _pos = 0;

  DartLikeParser(this._tokens);

  // ─── Entry point ────────────────────────────────────────────────────────────

  List<Node> parseProgram() {
    final nodes = <Node>[];
    while (!_atEnd()) {
      nodes.add(_declaration());
    }
    return nodes;
  }

  /// Like [parseProgram] but also returns the 1-based source line of each form.
  /// Used by origin-tracking compile functions to embed `@dmacro-origin` comments.
  List<(Node node, int line)> parseProgramSpanned() {
    final result = <(Node, int)>[];
    while (!_atEnd()) {
      final startLine = _peek().line;
      result.add((_declaration(), startLine));
    }
    return result;
  }

  // ─── Declarations ────────────────────────────────────────────────────────────

  Node _declaration() {
    if (_check(TK.ident, 'defenum')) return _defenum();
    if (_check(TK.ident, 'defrecord')) return _defrecord();
    if (_check(TK.ident, 'defunion')) return _defunion();
    // defmacro name(params) { ... }         — untyped macro
    // defmacro(declaration) name(params)    — validates output is a declaration
    // defmacro(expression) name(params)     — validates output is an expression
    // defmacro(statement) name(params)      — validates output is a statement
    if (_check(TK.ident, 'defmacro')) {
      if (_peek2().kind == TK.ident) return _defmacroDecl();
      if (_peek2().kind == TK.lparen) return _defmacroDecl();
    }
    // Generic block macro: ident TypeName { field; ... }
    // Any unrecognised identifier followed by a capitalised name and `{` is
    // desugared into a macro call with structured field args, e.g.
    //   defwidget MyButton { String label; Color? color; }
    // → ['defwidget', 'MyButton', ['String', 'label'], ['Color?', 'color']]
    // This lets user macros use the same ergonomic block syntax as defrecord.
    if (_check(TK.ident) && _peek2().kind == TK.ident && _peek3().kind == TK.lbrace) {
      return _userBlockMacro();
    }
    // Top-level macro call: ident ( args... ) ;
    // Distinguished from a function declaration (type name ( ) { }) by looking
    // ahead: ident immediately followed by lparen → call, not declaration.
    if (_check(TK.ident) && _peek2().kind == TK.lparen) {
      return _topLevelCall();
    }
    // Try to parse as a structured Dart declaration (function, class, etc.).
    // If the body contains syntax the parser doesn't model (switch expressions,
    // record patterns, extension types…), fall back to opaque pass-through so
    // the user's code is emitted verbatim rather than erroring.
    final savedPos = _pos;
    try {
      return _fnDecl();
    } on ParseException {
      _pos = savedPos;
      return _opaqueDeclaration();
    }
  }

  Node _topLevelCall() {
    final name = _advance().value as String;
    _expect(TK.lparen);
    final args = _argList();
    _expect(TK.rparen);
    _expect(TK.semi);
    return [name, ...args];
  }

  /// Generic block-syntax macro: `macroName TypeName { Type field; ... }`
  ///
  /// Produces `[macroName, TypeName, [type, name], ...]`.
  /// Each field is a two-element list `[typeString, nameString]` so macro
  /// authors receive structured data instead of raw string tokens.
  Node _userBlockMacro() {
    final macroName = _advance().value as String;
    final typeName = _advance().value as String;
    _expect(TK.lbrace);
    final fields = <List<String>>[];
    while (!_check(TK.rbrace)) {
      final t = _parseType();
      final n = _expect(TK.ident).value as String;
      _expect(TK.semi);
      fields.add([t, n]);
    }
    _expect(TK.rbrace);
    return [macroName, typeName, ...fields];
  }

  Node _defenum() {
    _expect(TK.ident, 'defenum');
    final name = _expect(TK.ident).value as String;
    _expect(TK.lbrace);
    final values = <String>[];
    while (!_check(TK.rbrace)) {
      values.add(_expect(TK.ident).value as String);
      if (!_check(TK.rbrace)) _match(TK.comma);
    }
    _expect(TK.rbrace);
    // Flat form: ['defenum', name, val1, val2, ...] — consumed by the defenum macro.
    return ['defenum', name, ...values];
  }

  Node _defrecord() {
    _expect(TK.ident, 'defrecord');
    // Optional modifier: defrecord(snake_case) Name { ... }
    var macroName = 'defrecord';
    if (_check(TK.lparen)) {
      _advance();
      final modifier = _expect(TK.ident).value as String;
      if (modifier == 'snake_case') macroName = 'defrecord_snake';
      _expect(TK.rparen);
    }
    final name = _expect(TK.ident).value as String;
    _expect(TK.lbrace);
    final fields = <List<dynamic>>[];
    while (!_check(TK.rbrace)) {
      final fieldLine =
          _peek().line; // capture source line before consuming type
      String? jsonKey;
      if (_check(TK.at)) {
        _advance(); // consume @
        _expect(TK.ident, 'json_key');
        _expect(TK.lparen);
        final keyToken = _expect(TK.string);
        jsonKey = (keyToken.value as String).replaceAll('"', '');
        _expect(TK.rparen);
      }
      final t = _parseType();
      final n = _expect(TK.ident).value as String;
      _expect(TK.semi);
      fields.add([t, n, fieldLine, jsonKey]);
    }
    _expect(TK.rbrace);
    return [macroName, name, ...fields];
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

  Node _defmacroDecl() {
    _expect(TK.ident, 'defmacro');
    // Optional output-type qualifier: defmacro(declaration), defmacro(expression),
    // defmacro(statement). Parsed as an extra arg so builtins.dart can validate.
    String? outputType;
    if (_check(TK.lparen)) {
      _advance(); // consume (
      outputType = _expect(TK.ident).value as String;
      _expect(TK.rparen);
    }
    final name = _expect(TK.ident).value as String;
    _expect(TK.lparen);
    final params = <String>[];
    while (!_check(TK.rparen)) {
      // Rest param: ...rest — must be last. Captures all remaining call
      // arguments as a single list, for iteration with $map.
      // (`...` arrives as TK.cascade `..` followed by TK.dot `.`.)
      if (_check(TK.cascade) && _peek2().kind == TK.dot) {
        _advance(); // consume ..
        _advance(); // consume .
        final restName = _expect(TK.ident).value as String;
        params.add('...$restName');
        break;
      }
      params.add(_expect(TK.ident).value as String);
      if (!_check(TK.rparen)) _match(TK.comma);
    }
    _expect(TK.rparen);
    final body = _blockAsNode();
    if (outputType != null) {
      return ['defmacro_typed', outputType, name, params, body];
    }
    return ['defmacro', name, params, body];
  }

  Node _fnDecl() {
    // Optional 'async' return-type prefix: "async Future<T> f() async { }"
    // The 'async' keyword appears BEFORE the body open-brace (after the params).
    final returnType = _parseType();
    final name = _expect(TK.ident).value as String;
    _expect(TK.lparen);
    final params = _parseParams();
    _expect(TK.rparen);
    // async modifier comes between ) and { (or =>)
    final isAsync = _match(TK.ident, 'async');
    // Arrow body: Type name(params) => expr;
    if (_check(TK.arrow)) {
      _advance();
      final expr = _expr();
      _expect(TK.semi);
      final tag = isAsync ? 'async $returnType' : returnType;
      return ['defn', tag, name, params, '__arrow__', expr];
    }
    final body = _blockStatements();
    final tag = isAsync ? 'async $returnType' : returnType;
    return ['defn', tag, name, params, ...body];
  }

  List<List<String>> _parseParams() {
    final params = <List<String>>[];
    while (!_check(TK.rparen)) {
      // Named/optional params: { String? host, int port = 8080 }
      // For simplicity, skip '{' / '}' wrappers and treat as regular params.
      if (_check(TK.lbrace)) {
        _advance();
        continue;
      }
      if (_check(TK.rbrace)) {
        _advance();
        continue;
      }
      final t = _parseType();
      final n = _expect(TK.ident).value as String;
      // Skip default value if present
      if (_match(TK.assign)) _expr();
      params.add([t, n]);
      if (!_check(TK.rparen)) _match(TK.comma);
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
      while (_match(TK.comma)) {
        inner.add(_parseType());
      }
      _expect(TK.gt);
      name = '$name<${inner.join(', ')}>';
    }
    // Nullable
    if (_check(TK.question)) {
      _advance();
      name = '$name?';
    }
    return name;
  }

  // ─── Statements ──────────────────────────────────────────────────────────────

  List<Node> _blockStatements() {
    _expect(TK.lbrace);
    final stmts = <Node>[];
    while (!_check(TK.rbrace)) {
      if (_atEnd()) {
        throw ParseException('Unexpected end of file — missing "}"');
      }
      stmts.add(_statement());
    }
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
        if (_check(TK.question)) {
          _advance();
          name = '$name?';
        }
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
    // for (final x in iterable) { body }
    if (_check(TK.ident, 'for')) {
      _advance();
      _expect(TK.lparen);
      _match(TK.ident, 'final'); // consume optional 'final'
      final varName = _expect(TK.ident).value as String;
      _expect(TK.ident, 'in');
      final iter = _expr();
      _expect(TK.rparen);
      final body = _blockAsNode();
      return ['for-in', varName, iter, body];
    }
    // await expr; (as a statement)
    if (_check(TK.ident, 'await')) {
      _advance();
      final val = _expr();
      _expect(TK.semi);
      return ['await', val];
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
    // Statement type not modelled by the parser — emit verbatim rather than error.
    return _opaqueStatement();
  }

  // ─── Expressions (operator precedence) ───────────────────────────────────────

  Node _expr() => _ternary();

  // cond ? then : else
  Node _ternary() {
    final cond = _nullCoalesce();
    if (_check(TK.question) && _peek2().kind != TK.question) {
      _advance(); // consume ?
      final then = _ternary();
      _expect(TK.colon);
      final els = _ternary();
      return ['?:', cond, then, els];
    }
    return cond;
  }

  // a ?? b
  Node _nullCoalesce() {
    var left = _or();
    while (_check(TK.nullCoalesce)) {
      _advance();
      left = ['??', left, _or()];
    }
    return left;
  }

  Node _or() {
    var left = _and();
    while (_check(TK.or)) {
      _advance();
      left = ['||', left, _and()];
    }
    return left;
  }

  Node _and() {
    var left = _equality();
    while (_check(TK.and)) {
      _advance();
      left = ['&&', left, _equality()];
    }
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
    if (_check(TK.bang)) {
      _advance();
      return ['!', _unary()];
    }
    if (_check(TK.minus)) {
      _advance();
      return ['-', _unary()];
    }
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
      } else if (_check(TK.cascade)) {
        // Cascade chain: recv..method(args)..prop
        _advance();
        final ops = <Node>[];
        final member = _expect(TK.ident).value as String;
        if (_check(TK.lparen)) {
          _advance();
          final args = _argList();
          _expect(TK.rparen);
          ops.add(['..$member', ...args]);
        } else if (_check(TK.assign)) {
          _advance();
          ops.add(['..=$member', _expr()]);
        } else {
          ops.add(['..$member']);
        }
        // Continue consuming cascade ops
        while (_check(TK.cascade)) {
          _advance();
          final m2 = _expect(TK.ident).value as String;
          if (_check(TK.lparen)) {
            _advance();
            final args2 = _argList();
            _expect(TK.rparen);
            ops.add(['..$m2', ...args2]);
          } else if (_check(TK.assign)) {
            _advance();
            ops.add(['..=$m2', _expr()]);
          } else {
            ops.add(['..$m2']);
          }
        }
        expr = ['cascade', expr, ...ops];
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
      } else if (_check(TK.question) && _peek2().kind == TK.dot) {
        // Null-aware member access: expr?.member
        _advance(); // consume ?
        _advance(); // consume .
        final member = _expect(TK.ident).value as String;
        if (_check(TK.lparen)) {
          _advance();
          final args = _argList();
          _expect(TK.rparen);
          expr = ['?.$member', expr, ...args];
        } else {
          expr = ['?.-$member', expr];
        }
      } else {
        break;
      }
    }
    return expr;
  }

  Node _primary() {
    final t = _peek();
    // Parenthesised expression
    if (t.kind == TK.lparen) {
      _advance();
      final e = _expr();
      _expect(TK.rparen);
      return e;
    }
    // List literal: [item, item, ...]
    if (t.kind == TK.lbracket) {
      _advance();
      final items = <Node>[];
      while (!_check(TK.rbracket)) {
        // spread: ...expr  (tokenizer emits ".." as TK.cascade then "." as TK.dot)
        if (_check(TK.cascade) && _peek2().kind == TK.dot) {
          _advance(); // consume ".." cascade
          _advance(); // consume "." dot
          items.add(['...', _expr()]);
        } else {
          items.add(_expr());
        }
        if (!_check(TK.rbracket)) _match(TK.comma);
      }
      _expect(TK.rbracket);
      return ['list', ...items];
    }
    // await expr
    if (t.kind == TK.ident && t.value == 'await') {
      _advance();
      return ['await', _expr()];
    }
    if (t.kind == TK.string ||
        t.kind == TK.integer ||
        t.kind == TK.float ||
        t.kind == TK.ident) {
      return _advance().value!;
    }
    throw ParseException('Unexpected token in expression: $t',
        line: t.line, col: t.col);
  }

  // ─── Opaque pass-through ─────────────────────────────────────────────────────

  /// Converts a single [Token] to its string representation.
  String _tokenText(Token t) {
    if (t.kind == TK.eof) return '';
    return (t.value ?? '').toString();
  }

  /// Scans tokens to the end of a top-level declaration, emitting them as an
  /// [OpaqueNode]. Used when the parser encounters Dart syntax it doesn't model.
  ///
  /// A top-level form ends when a `}` closes the outermost open brace (for
  /// class/function bodies) or when a `;` is seen at brace depth 0.
  OpaqueNode _opaqueDeclaration() {
    final buf = StringBuffer();
    var depth = 0;
    var terminated = false;
    while (!_atEnd()) {
      final t = _peek();
      buf.write(_tokenText(t));
      _advance();
      if (t.kind == TK.lbrace) {
        depth++;
      } else if (t.kind == TK.rbrace) {
        depth--;
        if (depth <= 0) {
          terminated = true;
          break;
        }
      } else if (t.kind == TK.semi && depth == 0) {
        terminated = true;
        break;
      }
      buf.write(' ');
    }
    // Hit EOF with an unclosed brace — that's malformed input, not just syntax
    // we don't model. Report the error clearly.
    if (!terminated && depth > 0) {
      throw ParseException('Unexpected end of file — missing closing "}"');
    }
    return OpaqueNode(buf.toString().trimRight());
  }

  /// Scans tokens to the end of a statement, emitting them as an [OpaqueNode].
  ///
  /// A statement ends at `;` at depth 0, or at a `}` that closes the last
  /// open `{` (for block-style constructs like `switch { ... }`).
  OpaqueNode _opaqueStatement() {
    final buf = StringBuffer();
    var depth = 0;
    while (!_atEnd()) {
      final t = _peek();
      if (t.kind == TK.rbrace && depth == 0) break; // end of enclosing block
      buf.write(_tokenText(t));
      _advance();
      if (t.kind == TK.lbrace || t.kind == TK.lbracket || t.kind == TK.lparen) {
        depth++;
      } else if (t.kind == TK.rbrace ||
          t.kind == TK.rbracket ||
          t.kind == TK.rparen) {
        depth--;
        if (depth < 0) { depth = 0; break; }
        if (t.kind == TK.rbrace && depth == 0) break;
      } else if (t.kind == TK.semi && depth == 0) {
        break;
      }
      buf.write(' ');
    }
    return OpaqueNode(buf.toString().trimRight());
  }

  List<Node> _argList() {
    final args = <Node>[];
    while (!_check(TK.rparen)) {
      // Named arg: ident: expr
      if (_check(TK.ident) && _peek2().kind == TK.colon) {
        final key = _advance().value as String;
        _advance(); // consume ':'
        args.add(['named', key, _expr()]);
      } else {
        args.add(_expr());
      }
      if (!_check(TK.rparen)) _match(TK.comma);
    }
    return args;
  }

  // ─── Token helpers ────────────────────────────────────────────────────────────

  Token _peek() => _tokens[_pos];
  Token _peek2() => _tokens[_pos + 1 < _tokens.length ? _pos + 1 : _pos];
  Token _peek3() => _tokens[_pos + 2 < _tokens.length ? _pos + 2 : _pos];

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
    if (_check(kind, value)) {
      _advance();
      return true;
    }
    return false;
  }

  Token _expect(TK kind, [Object? value]) {
    if (!_check(kind, value)) {
      final t = _peek();
      throw ParseException(
        'Expected ${kind.name}${value != null ? "($value)" : ""}, '
        'got $t',
        line: t.line,
        col: t.col,
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
/// Calls [resetGensym] first for deterministic output.
String compileDartLike(String source) {
  resetGensym();
  resetEnumRegistry();
  final tokens = Tokenizer(source).tokenize();
  final forms = DartLikeParser(tokens).parseProgram();
  return assembleOutput(forms.map((f) => emitForm(expand(f))));
}
