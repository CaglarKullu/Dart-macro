# Backlog

Task tracking for autonomous implementation. Mark `[x]` when an acceptance criterion is
met and proven by a test. Record deviations in the relevant phase spec, not here.

Legend: `[ ]` todo · `[~]` in progress · `[x]` done · `[!]` blocked/needs decision

---

## Phase 0 — Foundation (DONE)

- [x] `core.dart` — `Node`, `expand`, `emit`
- [x] `reader.dart` — S-expression reader
- [x] `tokenizer.dart` — `.dmacro` lexer
- [x] `dart_parser.dart` — `.dmacro` parser
- [x] `nodes.dart` — typed constructors (`$if`, `$not`, …)
- [x] `builtins.dart` — `unless`, `when`, `swap!`, `assertThat`, `withRetry`, `defrecord`, `defunion`
- [x] `bin/sexp.dart` — `compile` + `repl`
- [x] Validated end-to-end (see `docs/VALIDATED_LOGIC.md`)

> Port note: Phase 0 logic is validated. First implementation task is to ensure the Dart
> port reproduces `docs/VALIDATED_LOGIC.md` exactly, then write `test/` coverage for it
> before starting Phase 1.

- [ ] `test/core_test.dart` — expand/emit regression against VALIDATED_LOGIC
- [ ] `test/reader_test.dart` — S-expression parsing
- [ ] `test/dart_parser_test.dart` — `.dmacro` parsing
- [ ] `test/builtins_test.dart` — each builtin's documented output

---

## Phase 1 — Correctness

### 1.1 gensym
- [ ] `lib/src/gensym.dart` with `gensym([prefix])` and `resetGensym()`
- [ ] `compile`/`compileDartLike` call `resetGensym()` first
- [ ] `swap!`, `withRetry` use `gensym`
- [ ] Determinism: same input → byte-identical output
- [ ] `test/gensym_test.dart`: collision case `swap!(a, __swap_0)` is safe
- [ ] Update VALIDATED_LOGIC regression expectations for new temp names

### 1.2 $splice
- [ ] `lib/src/splice.dart` with `Splice` + `$splice`
- [ ] `expand` flattens `Splice` children in every context
- [ ] `swap!` rewritten to use `$splice`
- [ ] Works inside `when`, inside `while`, and nested in another macro
- [ ] No `Splice` ever reaches emitted output (guard/assert)
- [ ] `test/splice_test.dart`
- [ ] Exports added to `lib/dart_sexp.dart`

---

## Phase 2 — Async compile-time eval (KEYSTONE)

### 2.1 async expander
- [ ] `expand` returns `Future<Node>`; `MacroFn` is `FutureOr<Node> Function(...)`
- [ ] Sequential awaits (deterministic ordering preserved)
- [ ] `compile`/`compileDartLike` become async
- [ ] CLI threads the await through
- [ ] All Phase 0/1 macros still pass via async expander

### 2.2 defFromJsonSchema
- [ ] `lib/src/schema_macros.dart` with `registerSchemaMacros()`
- [ ] JSON Schema → Dart type mapping table implemented
- [ ] Returns a `['defrecord', …]` node (reuse validated class generation)
- [ ] Required vs optional → non-null vs nullable
- [ ] Array `items` → `List<T>`
- [ ] Missing file → clear located error, not a stack trace
- [ ] Zero non-SDK deps (`dart:io`, `dart:convert` only)
- [ ] `test/schema_macros_test.dart`: payment.json → matches hand-written `defrecord`

### 2.3 demo + decision
- [ ] `example/schema_demo/schemas/payment.json`
- [ ] `example/schema_demo/models.dmacro`
- [ ] `example/schema_demo/README.md` (command + generated output)
- [ ] Output passes `dart format` + `dart analyze`
- [ ] **[!] DECISION**: continue to Phase 3, or stop & document. Record outcome here:
      > Decision: __________________________________________________

### Stretch (only after 2.1–2.3 committed)
- [ ] `defFromOpenApi(path, "SchemaName")`
- [ ] `defAllFromJsonSchema("dir/")`

---

## Phase 3 — Parser hardening  (only if gate = continue)

- [ ] 3.1 Named arguments (`foo(a: 1)`, `o.copyWith(a: 1)`)
- [ ] 3.2 Cascades (`x..a()..b()`)
- [ ] 3.3 `async` / `await` / arrow bodies (`=>`)
- [ ] 3.4 Ternary, collection literals, interpolation passthrough, null-aware, spread
- [ ] 3.5 `test/corpus/` with ≥10 real snippets; each compiles clean or errors clearly
- [ ] Known unsupported constructs listed in the Phase 3 spec

---

## Phase 4 — Developer experience

- [ ] 4.1 `watch` with debounce; survives errors; initial full build
- [ ] 4.2a Located parse/tokenize errors (`file:line:col` + source line + caret)
- [ ] 4.2b Top-level form origin comments (`// from file:line`)
- [ ] 4.3 `compile <dir>`, `--check` (CI staleness), `--format` default on
- [ ] Tests for watch debounce + `--check` exit codes

---

## Phase 5 — IDE integration (stretch)

- [ ] 5.1 Compile-on-save extension shelling to `sexp`
- [ ] 5.2 `.dmacro` TextMate grammar + language registration
- [ ] 5.3 CLI errors → editor diagnostics at correct locations
- [ ] 5.4 Command palette / status bar (optional)
- [ ] Package with `vsce`; README with workflow GIF

---

## Cross-cutting (apply throughout)

- [ ] `dart analyze` clean across `lib/` and emitted output
- [ ] `dart format` applied to source and emitted output
- [ ] Public API surface documented in `lib/dart_sexp.dart`
- [ ] Each phase: invariants from `docs/ARCHITECTURE.md` still hold
  - [ ] two front-ends → one AST
  - [ ] emitted Dart analyzer-clean
  - [ ] `expand(expand(x)) == expand(x)`
  - [ ] deterministic output
  - [ ] core has no third-party deps
