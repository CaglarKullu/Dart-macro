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
  final args = (node as List<Node>).sublist(1);

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

  if (node == null)          return 'null';
  if (node is bool)          return '$node';
  if (node is int || node is double) return '$node';
  if (node is String)        return node; // identifier or raw source

  if (node is! List || (node as List).isEmpty) return '';

  final sym  = node[0] as dynamic;
  final args = (node as List<Node>).sublist(1);

  switch (sym as String) {

    // ── Unary operators (must precede binary to catch single-arg -)
    case '!' when args.length == 1:
      return '!${emit(args[0], indent)}';
    case '-' when args.length == 1:
      return '-${emit(args[0], indent)}';

    // ── Arithmetic & logic (variadic / binary)
    case '+': case '-': case '*': case '/':
    case '==': case '!=': case '<': case '>': case '<=': case '>=':
    case '&&': case '||': case '??':
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
      final ops  = args.sublist(1).map((op) {
        final opList = op as List;
        final opSym  = opList[0] as String;
        if (opSym.startsWith('..=')) {
          // Cascade assignment: ..prop = val
          return '..${opSym.substring(3)} = ${emit(opList[1], indent)}';
        } else {
          // Cascade call or bare access: ..method(args)
          final method   = opSym.substring(2);
          final callArgs = opList.sublist(1).map((a) => emit(a, indent)).join(', ');
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
        final then = emit(args[1], indent + 1);
        return 'if ($cond) {\n$pad  $then\n$pad}';
      }
      if (args.length == 3) {
        // Could be [if, cond, then, else] — the standard form
        final then  = emit(args[1], indent + 1);
        final else_ = emit(args[2], indent + 1);
        return 'if ($cond) {\n$pad  $then\n$pad} else {\n$pad  $else_\n$pad}';
      }
      // More than 3 args: splice injected multiple then-statements.
      // Emit all as block statements.
      {
        final stmts = args.sublist(1)
            .map((s) => '$pad  ${emit(s, indent + 1)};')
            .join('\n');
        return 'if ($cond) {\n$stmts\n$pad}';
      }

    case 'while':
      if (args.length > 2) {
        // Splice injected multiple body statements
        final stmts = args.sublist(1)
            .map((s) => '$pad  ${emit(s, indent + 1)};')
            .join('\n');
        return 'while (${emit(args[0], indent)}) {\n$stmts\n$pad}';
      }
      return 'while (${emit(args[0], indent)}) {\n$pad  ${emit(args[1], indent + 1)}\n$pad}';

    case 'for-in':
      if (args.length > 3) {
        // Splice injected multiple body statements
        final stmts = args.sublist(2)
            .map((s) => '$pad  ${emit(s, indent + 1)};')
            .join('\n');
        return 'for (final ${args[0]} in ${emit(args[1], indent)}) {\n$stmts\n$pad}';
      }
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
      var retType = args[0] as String;
      final name    = args[1] as String;
      final params  = (args[2] as List<dynamic>)
          .map((p) => '${(p as List)[0]} ${p[1]}')
          .join(', ');
      // async modifier stored as 'async ReturnType'
      final isAsync = retType.startsWith('async ');
      if (isAsync) retType = retType.substring(6);
      final asyncKw = isAsync ? ' async' : '';
      final rest = args.sublist(3) as List<Node>;
      // Arrow body: ['defn', type, name, params, '__arrow__', expr]
      if (rest.isNotEmpty && rest[0] == '__arrow__') {
        return '$retType $name($params)$asyncKw => ${emit(rest[1], indent)};';
      }
      final body = rest
          .map((s) => '${emit(s, indent + 1)};')
          .join('\n  ');
      return '$retType $name($params)$asyncKw {\n  $body\n}';

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

    // ── Null-aware method call: ['?.method', receiver, arg1, ...]
    case String s when s.startsWith('?.') && !s.startsWith('?.-'):
      final recv     = emit(args[0], indent);
      final method   = s.substring(1); // keep the leading ?
      final callArgs = args.sublist(1).map((a) => emit(a, indent)).join(', ');
      return '$recv$method($callArgs)';

    // ── Null-aware property access: ['?.-prop', receiver]
    case String s when s.startsWith('?.-'):
      return '${emit(args[0], indent)}?.${s.substring(3)}';

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
