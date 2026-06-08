/// dart_sexp — Lisp-style macros for Dart.
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

// ─── Registry ─────────────────────────────────────────────────────────────────

final _macros = <String, MacroFn>{};

/// Registers a macro. Like Lisp's `defmacro`.
void defmacro(String name, MacroFn fn) => _macros[name] = fn;

/// Returns true if [name] is a registered macro.
bool isMacro(String name) => _macros.containsKey(name);

// ─── Expander ─────────────────────────────────────────────────────────────────

/// Recursively expands all macros in [node].
///
/// Like Lisp's macroexpand — if the head of a list is a known macro,
/// the macro is called with the UNEVALUATED arguments, then the result
/// is expanded again (allowing macros to produce other macros).
Node expand(Node node) {
  if (node is! List || node.isEmpty) return node;

  final sym = node[0];
  final args = (node as List<Node>).sublist(1);

  if (sym is String && _macros.containsKey(sym)) {
    // Call macro with raw (unevaluated) args, then re-expand the result.
    // This is the key property: macros receive CODE, not VALUES.
    return expand(_macros[sym]!(args));
  }

  // Not a macro — expand subforms recursively.
  return [sym, ...args.map(expand)];
}

// ─── Emitter ──────────────────────────────────────────────────────────────────

/// Converts an expanded [Node] AST to a Dart source string.
String emit(Node node, [int indent = 0]) {
  final pad = '  ' * indent;

  if (node == null)          return 'null';
  if (node is bool)          return '$node';
  if (node is int || node is double) return '$node';
  if (node is String)        return node; // identifier or raw source

  if (node is! List || (node as List).isEmpty) return '';

  final sym  = node[0] as dynamic;
  final args = (node as List<Node>).sublist(1);

  switch (sym as String) {

    // ── Arithmetic & logic (variadic)
    case '+': case '-': case '*': case '/':
    case '==': case '!=': case '<': case '>': case '<=': case '>=':
    case '&&': case '||':
      return '(${args.map((a) => emit(a, indent)).join(' $sym ')})';

    case '!':
      return '!${emit(args[0], indent)}';

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
      final then = emit(args[1], indent + 1);
      if (args.length == 2) {
        return 'if ($cond) {\n$pad  $then\n$pad}';
      }
      final else_ = emit(args[2], indent + 1);
      return 'if ($cond) {\n$pad  $then\n$pad} else {\n$pad  $else_\n$pad}';

    case 'while':
      return 'while (${emit(args[0], indent)}) {\n$pad  ${emit(args[1], indent + 1)}\n$pad}';

    case 'for-in':
      return 'for (final ${args[0]} in ${emit(args[1], indent)}) '
             '{\n$pad  ${emit(args[2], indent + 1)}\n$pad}';

    case 'return': return 'return ${emit(args[0], indent)}';
    case 'throw':  return 'throw ${emit(args[0], indent)}';

    // ── Sequence of statements
    case 'do':
      return args.map((a) => '${emit(a, indent)};').join('\n$pad');

    // ── Try/catch
    case 'try':
      return 'try {\n$pad  ${emit(args[0], indent + 1)}\n$pad}'
             ' catch (${args[1]}) {\n$pad  ${emit(args[2], indent + 1)}\n$pad}';

    // ── Function definition
    case 'defn':
      final retType = args[0] as String;
      final name    = args[1] as String;
      final params  = (args[2] as List<dynamic>)
          .map((p) => '${(p as List)[0]} ${p[1]}')
          .join(', ');
      final body = (args.sublist(3) as List<Node>)
          .map((s) => '${emit(s, indent + 1)};')
          .join('\n  ');
      return '$retType $name($params) {\n  $body\n}';

    // ── Class definition
    case 'defclass':
      final name    = args[0] as String;
      final members = args.sublist(1);
      final body    = members.map((m) => emit(m, indent + 1)).join('\n  ');
      return 'class $name {\n  $body\n}';

    case 'field':
      return 'final ${args[0]} ${args[1]};';

    case 'ctor':
      final name   = args[0] as String;
      final params = (args[1] as List<dynamic>)
          .map((p) => 'required this.$p')
          .join(', ');
      return 'const $name({$params});';

    case 'copywith':
      final name   = args[0] as String;
      final fields = args[1] as List<dynamic>;
      final params = fields
          .map((f) => '${_nullableType((f as List)[0] as String)}? ${f[1]}')
          .join(', ');
      final fwds = fields
          .map((f) => '${(f as List)[1]}: ${f[1]} ?? this.${f[1]}')
          .join(', ');
      return '$name copyWith({$params}) => $name($fwds);';

    case 'equalop':
      final name   = args[0] as String;
      final fields = args[1] as List<dynamic>;
      final checks = fields
          .map((f) => 'other.${(f as List)[1]} == ${f[1]}')
          .join(' && ');
      return '@override\n  bool operator ==(Object other) => '
             'identical(this, other) || other is $name && $checks;';

    case 'hashop':
      final fields = args[1] as List<dynamic>;
      final names  = fields.map((f) => (f as List)[1]).join(', ');
      return '@override\n  int get hashCode => Object.hash($names);';

    case 'tostringop':
      final name   = args[0] as String;
      final fields = args[1] as List<dynamic>;
      final props  = fields
          .map((f) => '${(f as List)[1]}: \$${f[1]}')
          .join(', ');
      return "@override\n  String toString() => '$name($props)';";

    // ── Method call:  ['.method', receiver, arg1, ...]
    case String s when s.startsWith('.') && !s.startsWith('.-'):
      final recv    = emit(args[0], indent);
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

/// Strips a trailing `?` for use as param type in copyWith.
String _nullableType(String t) => t.endsWith('?') ? t.substring(0, t.length - 1) : t;
