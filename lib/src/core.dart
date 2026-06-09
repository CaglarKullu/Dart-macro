/// dmacro — Lisp-style macros for Dart.
///
/// Code is represented as [Node] — either an atom (String, int, double, bool,
/// null) or a [List<Node>]. This mirrors Lisp's S-expressions exactly.
///
/// A macro is a plain Dart function [List<Node>] → [Node].
/// The expander is recursive. No process boundary. No WebSocket. No files.
library;

/// A node in the AST.
/// Either a primitive atom or a List<Node> (S-expression).
typedef Node = dynamic;

/// A macro function: receives unevaluated argument nodes, returns a new node.
typedef MacroFn = Node Function(List<Node> args);

/// Marks a sequence of nodes to be spliced (inlined) into the parent list.
///
/// Produced by [$splice] and consumed by [expand], which flattens any [Splice]
/// children into the parent list. No [Splice] should ever reach [emit].
class Splice {
  final List<Node> nodes;
  const Splice(this.nodes);
}

// ─── Registry ─────────────────────────────────────────────────────────────────

final _macros = <String, MacroFn>{};

/// Registers a macro. Like Lisp's `defmacro`.
void defmacro(String name, MacroFn fn) => _macros[name] = fn;

/// Returns true if [name] is a registered macro.
bool isMacro(String name) => _macros.containsKey(name);

/// Returns the macro function registered under [name], or null.
MacroFn? getMacro(String name) => _macros[name];

// ─── Expander ─────────────────────────────────────────────────────────────────

/// Recursively expands all macros in [node].
///
/// Like Lisp's macroexpand — if the head of a list is a known macro,
/// the macro is called with the UNEVALUATED arguments, then the result
/// is expanded again (allowing macros to produce other macros).
///
/// After expanding children, any [Splice] children are flattened (inlined)
/// into the parent list. This allows macros to inject multiple statements.
Node expand(Node node) {
  if (node is! List || node.isEmpty) return node;

  final sym = node[0];
  final args = node.sublist(1);

  if (sym is String && _macros.containsKey(sym)) {
    // Call macro with raw (unevaluated) args, then re-expand the result.
    // This is the key property: macros receive CODE, not VALUES.
    return expand(_macros[sym]!(args));
  }

  // Not a macro — expand subforms recursively, then flatten any Splice.
  final out = <Node>[sym];
  for (final child in args.map(expand)) {
    if (child is Splice) {
      out.addAll(child.nodes);
    } else {
      out.add(child);
    }
  }
  return out;
}

// ─── Emitter ──────────────────────────────────────────────────────────────────

/// Converts an expanded [Node] AST to a Dart source string.
String emit(Node node, [int indent = 0]) {
  final pad = '  ' * indent;

  // Splice must be flattened by expand() — it must never reach emit().
  if (node is Splice) {
    throw StateError(
      'Splice reached emit() — expand() did not flatten it. '
      'Ensure expand() is called before emit().',
    );
  }

  if (node == null) return 'null';
  if (node is bool) return '$node';
  if (node is int || node is double) return '$node';
  if (node is String) return node; // identifier or raw source

  if (node is! List || node.isEmpty) return '';

  final sym = node[0];
  final args = node.sublist(1);

  switch (sym as String) {
    // ── Unary operators (must precede binary to catch single-arg -)
    case '!' when args.length == 1:
      return '!${emit(args[0], indent)}';
    case '-' when args.length == 1:
      return '-${emit(args[0], indent)}';

    // ── Arithmetic & logic (variadic / binary)
    case '+':
    case '-':
    case '*':
    case '/':
    case '==':
    case '!=':
    case '<':
    case '>':
    case '<=':
    case '>=':
    case '&&':
    case '||':
    case '??':
      return '(${args.map((a) => emit(a, indent)).join(' $sym ')})';

    case 'await':
      return 'await ${emit(args[0], indent)}';

    case '?:':
      return '(${emit(args[0], indent)} ? ${emit(args[1], indent)} : ${emit(args[2], indent)})';

    // Named argument: amount: 100
    case 'named':
      return '${args[0]}: ${emit(args[1], indent)}';

    // List literal: [a, b, c]
    case 'list':
      return '[${args.map((a) => emit(a, indent)).join(', ')}]';

    // Cascade: recv..method(args)..method2()
    case 'cascade':
      final recv = emit(args[0], indent);
      final ops = args.sublist(1).map((op) {
        final opList = op as List;
        final opSym = opList[0] as String;
        if (opSym.startsWith('..=')) {
          // Cascade assignment: ..prop = val
          return '..${opSym.substring(3)} = ${emit(opList[1], indent)}';
        } else {
          // Cascade call or bare access: ..method(args)
          final method = opSym.substring(2);
          final callArgs =
              opList.sublist(1).map((a) => emit(a, indent)).join(', ');
          return method.isEmpty ? '..' : '..$method($callArgs)';
        }
      }).join('');
      return '$recv$ops';

    // ── Bindings
    case 'let':
      return 'final ${args[0]} = ${emit(args[1], indent)}';
    case 'var':
      return 'var ${args[0]} = ${emit(args[1], indent)}';
    case 'set!':
      return '${args[0]} = ${emit(args[1], indent)}';

    // ── Control flow
    case 'if':
      final cond = emit(args[0], indent);
      // args[1..] are the body statements (Splice may have added more than one).
      // Distinguish: if there is NO else, all remaining args are the then-body.
      // If there IS an else, it's the last arg when arg count would be ambiguous.
      // By convention: if the last arg is a list starting with 'if' or 'do' or
      // any non-statement, it could be an else. But we can't distinguish reliably
      // after splicing. Instead, use a simpler heuristic: if args.length > 2 AND
      // the last arg LOOKS like an else (is a list that could be a statement block),
      // we can't tell. The safe approach for Splice: treat args[1..] as then-stmts,
      // no else. Else is not commonly combined with spliced bodies. If an explicit
      // else was passed (args.length == 3, single then + single else), use normal path.
      if (args.length <= 2) {
        // Normal path: [if, cond] or [if, cond, then]
        if (args.length < 2) return 'if ($cond) {}';
        final then = _emitStmt(args[1], indent + 1);
        return 'if ($cond) {\n$pad  $then\n$pad}';
      }
      if (args.length == 3) {
        // Could be [if, cond, then, else] — the standard form
        final then = _emitStmt(args[1], indent + 1);
        final else_ = _emitStmt(args[2], indent + 1);
        return 'if ($cond) {\n$pad  $then\n$pad} else {\n$pad  $else_\n$pad}';
      }
      // More than 3 args: splice injected multiple then-statements.
      // Emit all as block statements.
      {
        final stmts = args
            .sublist(1)
            .map((s) => '$pad  ${_emitStmt(s, indent + 1)}')
            .join('\n');
        return 'if ($cond) {\n$stmts\n$pad}';
      }

    case 'while':
      if (args.length > 2) {
        // Splice injected multiple body statements
        final stmts = args
            .sublist(1)
            .map((s) => '$pad  ${_emitStmt(s, indent + 1)}')
            .join('\n');
        return 'while (${emit(args[0], indent)}) {\n$stmts\n$pad}';
      }
      return 'while (${emit(args[0], indent)}) '
          '{\n$pad  ${_emitStmt(args[1], indent + 1)}\n$pad}';

    case 'for-in':
      if (args.length > 3) {
        // Splice injected multiple body statements
        final stmts = args
            .sublist(2)
            .map((s) => '$pad  ${_emitStmt(s, indent + 1)}')
            .join('\n');
        return 'for (final ${args[0]} in ${emit(args[1], indent)}) {\n$stmts\n$pad}';
      }
      return 'for (final ${args[0]} in ${emit(args[1], indent)}) '
          '{\n$pad  ${_emitStmt(args[2], indent + 1)}\n$pad}';

    case 'return':
      return 'return ${emit(args[0], indent)}';
    case 'throw':
      return 'throw ${emit(args[0], indent)}';

    // ── Sequence of statements
    case 'do':
      return args.map((a) => _emitStmt(a, indent)).join('\n$pad');

    // ── Try/catch
    case 'try':
      return 'try {\n$pad  ${_emitStmt(args[0], indent + 1)}\n$pad}'
          ' catch (${args[1]}) {\n$pad  ${_emitStmt(args[2], indent + 1)}\n$pad}';

    // ── Function definition
    case 'defn':
      var retType = args[0] as String;
      final name = args[1] as String;
      final params = (args[2] as List<dynamic>)
          .map((p) => '${(p as List)[0]} ${p[1]}')
          .join(', ');
      // async modifier stored as 'async ReturnType'
      final isAsync = retType.startsWith('async ');
      if (isAsync) retType = retType.substring(6);
      final asyncKw = isAsync ? ' async' : '';
      final rest = args.sublist(3);
      // Arrow body: ['defn', type, name, params, '__arrow__', expr]
      if (rest.isNotEmpty && rest[0] == '__arrow__') {
        return '$retType $name($params)$asyncKw => ${emit(rest[1], indent)};';
      }
      final body = rest.map((s) => _emitStmt(s, indent + 1)).join('\n  ');
      return '$retType $name($params)$asyncKw {\n  $body\n}';

    // ── Class definition
    case 'defclass':
      final name = args[0] as String;
      final members = args.sublist(1);
      final body = members.map((m) => emit(m, indent + 1)).join('\n  ');
      return 'class $name {\n  $body\n}';

    case 'field':
      return 'final ${args[0]} ${args[1]};';

    case 'ctor':
      final name = args[0] as String;
      final fields = args[1] as List<dynamic>;
      if (fields.isEmpty) return 'const $name();';
      final params = fields.map((p) {
        final type = (p as List)[0] as String;
        final pname = p[1] as String;
        return type.endsWith('?') ? 'this.$pname' : 'required this.$pname';
      }).join(', ');
      return 'const $name({$params});';

    case 'copywith':
      final name = args[0] as String;
      final fields = args[1] as List<dynamic>;
      // Nullable fields use a sentinel default so `copyWith(field: null)` can
      // clear them; non-nullable fields keep the simple `?? this.field` form.
      final params = fields.map((f) {
        final type = (f as List)[0] as String;
        return type.endsWith('?')
            ? 'Object? ${f[1]} = _dmUndefined'
            : '$type? ${f[1]}';
      }).join(', ');
      final fwds = fields.map((f) {
        final type = (f as List)[0] as String;
        final fname = f[1] as String;
        return type.endsWith('?')
            ? '$fname: identical($fname, _dmUndefined) ? this.$fname : $fname as $type'
            : '$fname: $fname ?? this.$fname';
      }).join(', ');
      return '$name copyWith({$params}) => $name($fwds);';

    case 'equalop':
      final name = args[0] as String;
      final fields = args[1] as List<dynamic>;
      final checks = fields.map((f) {
        final type = (f as List)[0] as String;
        final fname = f[1] as String;
        return _isCollection(type)
            ? '_dmEq(other.$fname, $fname)'
            : 'other.$fname == $fname';
      }).join(' && ');
      return '@override\n  bool operator ==(Object other) => '
          'identical(this, other) || other is $name && $checks;';

    case 'hashop':
      final fields = args[1] as List<dynamic>;
      final names = fields.map((f) {
        final type = (f as List)[0] as String;
        final fname = f[1] as String;
        return _isCollection(type) ? '_dmHash($fname)' : fname;
      }).join(', ');
      return '@override\n  int get hashCode => Object.hash($names);';

    // ── JSON serialization ──────────────────────────────────────────────────
    case 'fromjson':
      final name = args[0] as String;
      final fields = args[1] as List<dynamic>;
      final assigns = fields.map((f) {
        final type = (f as List)[0] as String;
        final fname = f[1] as String;
        return '$fname: ${_fromJsonExpr(type, "json['$fname']")}';
      }).join(', ');
      return 'factory $name.fromJson(Map<String, dynamic> json) => '
          '$name($assigns);';

    case 'tojson':
      final fields = args[1] as List<dynamic>;
      final entries = fields.map((f) {
        final type = (f as List)[0] as String;
        final fname = f[1] as String;
        return "'$fname': ${_toJsonExpr(type, fname)}";
      }).join(', ');
      return 'Map<String, dynamic> toJson() => {$entries};';

    case 'tostringop':
      final name = args[0] as String;
      final fields = args[1] as List<dynamic>;
      final props =
          fields.map((f) => '${(f as List)[1]}: \$${f[1]}').join(', ');
      return "@override\n  String toString() => '$name($props)';";

    // ── Null-aware method call: ['?.method', receiver, arg1, ...]
    case String s when s.startsWith('?.') && !s.startsWith('?.-'):
      final recv = emit(args[0], indent);
      final method = s.substring(1); // keep the leading ?
      final callArgs = args.sublist(1).map((a) => emit(a, indent)).join(', ');
      return '$recv$method($callArgs)';

    // ── Null-aware property access: ['?.-prop', receiver]
    case String s when s.startsWith('?.-'):
      return '${emit(args[0], indent)}?.${s.substring(3)}';

    // ── Method call:  ['.method', receiver, arg1, ...]
    case String s when s.startsWith('.') && !s.startsWith('.-'):
      final recv = emit(args[0], indent);
      final callArgs = args.sublist(1).map((a) => emit(a, indent)).join(', ');
      return '$recv$s($callArgs)';

    // ── Property access:  ['.-prop', receiver]
    case String s when s.startsWith('.-'):
      return '${emit(args[0], indent)}.${s.substring(2)}';

    // ── Regular function call
    default:
      final callArgs = args.map((a) => emit(a, indent)).join(', ');
      return '$sym($callArgs)';
  }
}

/// Heads whose emitted form is a block or declaration. As a statement they
/// carry their own braces and must NOT receive a trailing `;`.
const _blockHeads = <String>{
  'if',
  'while',
  'for-in',
  'try',
  'defn',
  'defclass',
  'do',
};

/// True if [node] emits a block or declaration (so it should not be terminated
/// with a trailing `;` when used as a statement).
bool _isBlock(Node node) {
  if (node is List && node.isNotEmpty && node[0] is String) {
    return _blockHeads.contains(node[0]);
  }
  // Raw source fragment that is itself a declaration/block — e.g. the
  // `sealed class X { ... }` parent emitted by defunion.
  if (node is String) return node.trimRight().endsWith('}');
  return false;
}

/// Emits [node] as a complete statement: terminated with `;` unless it is a
/// block or declaration (which already carries its own braces).
String _emitStmt(Node node, int indent) {
  final code = emit(node, indent);
  return _isBlock(node) ? code : '$code;';
}

// ─── JSON / value-semantics support ─────────────────────────────────────────

/// Scalar types that pass through JSON unchanged.
const _jsonScalars = {'String', 'int', 'num', 'bool', 'dynamic', 'Object'};

/// True if [type] (with any trailing `?`) is a `List`/`Set`/`Map`.
bool _isCollection(String type) {
  final base = type.endsWith('?') ? type.substring(0, type.length - 1) : type;
  return base.startsWith('List<') ||
      base.startsWith('Set<') ||
      base.startsWith('Map<');
}

/// The single generic argument of a `List<...>` / `Set<...>` type.
String _elementType(String collection) =>
    collection.substring(collection.indexOf('<') + 1, collection.length - 1);

/// Builds the expression that decodes [access] (a `json[...]` lookup) into a
/// value of [type]. Handles nullability, `double`/`DateTime`, nested records,
/// and `List`/`Set` of any of those.
String _fromJsonExpr(String type, String access) {
  final nullable = type.endsWith('?');
  final base = nullable ? type.substring(0, type.length - 1) : type;
  String guard(String expr) =>
      nullable ? '$access == null ? null : $expr' : expr;

  if (base.startsWith('List<') || base.startsWith('Set<')) {
    final elem = _elementType(base);
    final to = base.startsWith('Set<') ? 'toSet' : 'toList';
    return guard(
        '($access as List).map((e) => ${_fromJsonExpr(elem, 'e')}).$to()');
  }
  if (base.startsWith('Map<')) {
    // A JSON object — cast to the declared key/value types. Map values are
    // assumed JSON-native (the schema mapper only ever produces dynamic values).
    return guard('($access as Map).cast<${_elementType(base)}>()');
  }
  if (base == 'double') return guard('($access as num).toDouble()');
  if (base == 'DateTime') return guard('DateTime.parse($access as String)');
  if (_jsonScalars.contains(base)) return '$access as $type';
  // Nested record type.
  return guard('$base.fromJson($access as Map<String, dynamic>)');
}

/// Builds the expression that encodes the field named [fname] of [type] into a
/// JSON-safe value.
String _toJsonExpr(String type, String fname) {
  final nullable = type.endsWith('?');
  final base = nullable ? type.substring(0, type.length - 1) : type;
  final q = nullable ? '?' : '';

  if (base.startsWith('List<') || base.startsWith('Set<')) {
    final elem = _elementType(base);
    if (_jsonScalars.contains(elem) || elem == 'double') {
      // Primitive elements are already JSON-safe; Set must become a List.
      return base.startsWith('Set<') ? '$fname$q.toList()' : fname;
    }
    final enc = elem == 'DateTime' ? 'e.toIso8601String()' : 'e.toJson()';
    return '$fname$q.map((e) => $enc).toList()';
  }
  // A JSON object with JSON-native values is already serializable.
  if (base.startsWith('Map<')) return fname;
  if (base == 'DateTime') return '$fname$q.toIso8601String()';
  if (_jsonScalars.contains(base) || base == 'double') return fname;
  // Nested record type.
  return '$fname$q.toJson()';
}

/// Sentinel marking an omitted `copyWith` argument (distinct from `null`).
const _dmUndefinedSrc = 'const Object? _dmUndefined = Object();';

/// Self-contained structural equality used by generated `==`. Zero non-SDK deps.
const _dmEqSrc = '''
/// Structural equality for List/Set/Map fields (generated by dmacro).
bool _dmEq(Object? a, Object? b) {
  if (identical(a, b)) return true;
  if (a is List && b is List) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (!_dmEq(a[i], b[i])) return false;
    }
    return true;
  }
  if (a is Set && b is Set) {
    if (a.length != b.length) return false;
    for (final e in a) {
      if (!b.any((o) => _dmEq(e, o))) return false;
    }
    return true;
  }
  if (a is Map && b is Map) {
    if (a.length != b.length) return false;
    for (final k in a.keys) {
      if (!b.containsKey(k) || !_dmEq(a[k], b[k])) return false;
    }
    return true;
  }
  return a == b;
}''';

/// Structural hash matching [_dmEq] (generated by dmacro).
const _dmHashSrc = '''
/// Structural hash for List/Set/Map fields (generated by dmacro).
int _dmHash(Object? v) {
  if (v is List) return Object.hashAll(v.map(_dmHash));
  if (v is Set) return Object.hashAllUnordered(v.map(_dmHash));
  if (v is Map) {
    return Object.hashAllUnordered(
        v.entries.map((e) => Object.hash(_dmHash(e.key), _dmHash(e.value))));
  }
  return v.hashCode;
}''';

/// Joins emitted top-level [forms] and appends any runtime helpers the body
/// actually references (sentinel, `_dmEq`, `_dmHash`) — emitted at most once,
/// only when used, so output stays self-contained and dependency-free.
String assembleOutput(Iterable<String> forms) {
  final body = forms.join('\n\n');
  final helpers = <String>[
    if (body.contains('_dmUndefined')) _dmUndefinedSrc,
    if (body.contains('_dmEq(')) _dmEqSrc,
    if (body.contains('_dmHash(')) _dmHashSrc,
  ];
  return helpers.isEmpty ? body : '$body\n\n${helpers.join('\n\n')}';
}
