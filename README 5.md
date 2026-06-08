# dart_sexp

A Lisp-style macro system for Dart. Code is data, macros are pure Dart functions,
output is plain Dart. Zero runtime dependencies. No build_runner. No compiler plugin.

## Why this exists

Dart cancelled language-level macros in January 2025 — compile-time code execution
collided with the compiler's incremental-build and hot-reload guarantees. Every
existing code-generation tool in the ecosystem (`freezed`, `json_serializable`,
`built_value`, `dart_mappable`, `macro_kit`) works *around* that limitation by
transforming code that already exists, via `build_runner` or an analyzer daemon.

`dart_sexp` takes a different position: it is an honest **preprocessor**. Because it
regenerates files rather than integrating into the compiler, it is free of the
incrementality constraint that blocked the official macro system — and that freedom
unlocks a capability nothing else in the ecosystem has.

## The headline capability: async compile-time evaluation

Existing tools can read a Dart *class* and generate code from it. None can read the
*source of truth* — a JSON schema, an OpenAPI spec, a database table — and materialize
Dart types from it, because their execution environments forbid I/O.

A preprocessor with async macros has no such restriction:

```dart
// payment.dmacro
defFromJsonSchema("schemas/payment.json");
```

compiles, at build time, to a complete, fully-typed, immutable Dart class with
`copyWith`, `==`, `hashCode`, and `toString` — generated directly from the schema file,
with no build_runner, no daemon, and no pub dependency.

That is the thing the ecosystem has not done. It is the reason this project is worth
building beyond the learning value.

## What already works (validated)

The core engine is built and validated end-to-end:

- **Code as data** — `Node` = `dynamic` (atom or `List<Node>`), structurally identical
  to Lisp S-expressions.
- **Macros as Dart functions** — `defmacro('unless', (args) => $if($not(args[0]), args[1]))`.
- **Two front-ends** — S-expression syntax (`.sexp`) and Dart-like syntax (`.dmacro`),
  both producing the same AST.
- **Expression-level transforms** — `swap!` (variable injection), `assertThat` (reads its
  own source expression), `defrecord` (generates a whole class), `defunion` (sealed
  hierarchy). None of these are possible in macro_kit or build_runner.
- **A working CLI** — `compile` and `repl`.

## What's next (this spec package)

| Phase | Goal | Effort | Status |
|-------|------|--------|--------|
| 1 | Correctness: `gensym`, `$splice` | Small | Planned |
| 2 | **Async compile-time eval** (the differentiator) | Medium | Planned |
| 3 | Parser hardening (named params, cascades, async) | Medium | Planned |
| 4 | Developer experience (watch mode, source maps) | Medium | Planned |
| 5 | VS Code extension | Large | Planned |

Detailed specs in `specs/`. Implementation guidance in `CLAUDE.md`.

## The honest assessment

**Technical feasibility:** proven. The engine works; remaining items are well-scoped
engineering, not research.

**Product feasibility:** contingent. The "no build_runner" wedge must be sharp enough to
overcome ecosystem inertia, and the parser must eventually handle real Dart, not a clean
subset. The decision gate is after Phase 2: if generating types from a real schema is
compelling, continue; if not, this stands as a strong exploration and stops there.

Both outcomes are acceptable. The exploration has already produced a working artifact
and a clear understanding of why this problem defeated others.
