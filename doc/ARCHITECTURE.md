# Architecture

## Design philosophy

`dmacro` is a **preprocessor**, not a compiler integration. This single decision
shapes everything and is the source of the project's main advantage. Do not revisit it
without understanding why it was made (see "The preprocessor advantage" below).

## The pipeline

```
                    ┌─────────────┐
   .sexp source ───▶│   Reader    │──┐
                    └─────────────┘  │
                                     ├──▶ List<Node> ──▶ Expander ──▶ Emitter ──▶ Dart
                    ┌─────────────┐  │      (AST)        (macros)      (codegen)
 .dmacro source ──▶ │ Tokenizer + │──┘
                    │   Parser    │
                    └─────────────┘
```

Two front-ends, one back-end. Both the S-expression reader and the Dart-like parser
produce the **same** `List<Node>` representation, so the expander and emitter are shared.
A macro behaves identically regardless of which syntax produced it.

## The Node model

`Node` is the central abstraction. It is `dynamic` — deliberately untyped — and is one of:

- An **atom**: `String`, `int`, `double`, `bool`, or `null`
- A **list**: `List<Node>` (an S-expression)

```dart
typedef Node = dynamic;
```

This mirrors Lisp exactly: `(unless (> x 0) body)` is the list
`['unless', ['>', 'x', 0], 'body']`. The first element of a list is the operator or
macro name; the rest are operands.

String atoms are emitted verbatim (so identifiers, operators, and raw Dart fragments
pass through). String *literals* from source are stored **with their quotes** (`'"hi"'`)
so the emitter outputs them as Dart string literals rather than identifiers.

## Component responsibilities

### `core.dart` — engine

- `expand(Node) → Node`: recursively expands macros. If a list's head is a registered
  macro, call it with the **unevaluated** operands, then expand the result again
  (so macros can produce macros). Otherwise recurse into the operands.
- `emit(Node, [indent]) → String`: converts an expanded AST into Dart source text.
  Handles operators, bindings, control flow, function/class declarations, method calls,
  and property access.
- `defmacro(name, fn)`: registers a macro.

### `reader.dart` — S-expression front-end

Hand-rolled recursive reader. Handles `(...)` lists, `"..."` strings (with escapes),
numbers, `true`/`false`/`null`, symbols, and `;` line comments. `compile(source)` runs
the full read → expand → emit pipeline.

### `tokenizer.dart` — .dmacro lexer

Converts Dart-like text into `List<Token>`. Notable rules: two-char operators (`==`,
`!=`, `<=`, `>=`, `&&`, `||`) are matched before single-char; an identifier may carry a
trailing `!` (so `swap!` is one token) unless followed by `=`; `//` line comments are
skipped.

### `dart_parser.dart` — .dmacro parser

Recursive-descent parser with standard operator-precedence climbing
(`or → and → equality → comparison → addition → multiplication → unary → postfix → primary`).
Produces the same `List<Node>` as the reader. Recognizes:

- Declarations: `defrecord`, `defunion`, function declarations.
- Statements: `return`, `throw`, `final`/`var`, `if`/`else`, `while`, assignment,
  expression statements, and **control-flow-style macro calls** (`macroName(args) { block }`).
- Standard Dart control flow (`if`, `while`) is parsed natively and emitted unchanged;
  macros slot in alongside it.

### `nodes.dart` — typed constructor API

Dart-friendly wrappers over raw list construction, by convention prefixed `$`:
`$if`, `$not`, `$let`, `$do`, `$call`, `$class`, `$field`, etc. This is how macro
**authors** build ASTs without writing raw lists. Same output, but it reads like Dart.

### `builtins.dart` — standard macros

`unless`, `when`, `swap!`, `assertThat`, `withRetry`, `andLet`, `defrecord`, `defunion`.
Each demonstrates a capability; collectively they are the standard library.

## The preprocessor advantage

The official Dart macro effort died on this collision:

```
powerful compile-time execution  ⨯  fast incremental rebuild + hot reload
```

Macros that run arbitrary code make incremental compilation intractable, and hot reload
needs millisecond incremental recompiles. The two could not be reconciled inside the
compiler.

`dmacro` is not inside the compiler. It transforms `.dmacro`/`.sexp` files into
`.dart` files as a separate step. It therefore has **no incrementality obligation** — it
just regenerates output. This is why it can offer the one thing the official system could
not: **arbitrary code execution at expansion time, including I/O** (Phase 2).

The cost of this choice is the two-step build (source → `.dart` → compiled), which means
generated `.dart` files are committed to the repo, exactly as with `build_runner`. The
Dart ecosystem already accepts this tradeoff. It is the price of the capability, and it
is worth it.

## Async expansion (Phase 2 — the keystone)

Phase 2 changes `expand` to return `Future<Node>`, allowing macros to be async and
perform I/O during expansion:

```dart
Future<Node> expand(Node node) async {
  if (node is! List || node.isEmpty) return node;
  final head = node[0];
  if (head is String && _macros.containsKey(head)) {
    final result = _macros[head]!(node.sublist(1));
    final resolved = result is Future ? await result : result;
    return expand(resolved);                       // re-expand
  }
  final expanded = await Future.wait(
    node.sublist(1).map((n) async => await expand(n)));
  return _flattenSplices([head, ...expanded]);     // see Phase 1: $splice
}
```

This is the architectural seam that enables `defFromJsonSchema`, `defFromOpenApi`, and
similar — generating Dart types from external sources of truth at build time.

## Invariants the implementation must preserve

1. **Two front-ends, one AST.** Reader and parser output must be interchangeable.
2. **Emitted Dart is analyzer-clean.** Format + analyze emitted output in tests.
3. **Idempotent expansion.** `expand(expand(x)) == expand(x)`.
4. **Deterministic output.** Same input → byte-identical output (after `gensym` is
   seeded deterministically per compilation unit — see Phase 1).
5. **Core has no third-party dependencies.** SDK only.
6. **Per-file macro isolation.** A source file's macro registrations
   (`defmacro`, `importMacros`, `useMacros`) must not leak into the next file in
   a directory or watch build. The CLI snapshots and restores both macro
   registries around each file (`snapshotMacros` / `restoreMacros`); builtins
   and any macros registered through `runDmacro`'s `registerMacros` callback are
   the baseline and survive the rollback.

## Design decision: global registry, not a threaded `CompileContext`

The macro registries (`_macros`, `_asyncMacros`), the gensym counter, and the
enum registry are module-level state, mutated by `defmacro` / `defAsyncMacro`.
The textbook alternative is a `CompileContext` object threaded explicitly
through `expand` and every macro.

We deliberately keep the global registry. The headline of the whole project is
that a macro is *one function* registered with a one-liner:

```dart
defmacro('name', (args) => ...);
```

Threading a context would force that signature to become
`defmacro(ctx, 'name', (ctx, args) => ...)` — every macro, including every line
of the cookbook and every user macro, would carry plumbing that exists only to
serve testability. That trade makes the product worse at the exact thing it
sells.

The real risk a context would have mitigated — state leaking between files — is
instead handled at the one boundary where it matters: the CLI snapshots and
restores the registries per file (invariant 6 above). The cost of the global
approach is that the engine is not reentrant within a single process (you cannot
run two independent compiles concurrently in one isolate). For a preprocessor
invoked per process — and for `useMacros`, which already runs each loaded
library in its own isolate — that limitation is acceptable. If concurrent
in-process compilation ever becomes a requirement, revisit this; until then the
simpler API wins.
