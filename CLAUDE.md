# CLAUDE.md

Guidance for Claude Code working on the `dmacro` project.

## What this is

`dmacro` is a Lisp-style macro system for Dart. Code is represented as data
(nested lists), macros are pure Dart functions that transform that data, and the
final output is plain Dart source. It is a **preprocessor**, not a compiler plugin
— this is a deliberate architectural choice (see `doc/ARCHITECTURE.md`).

The pipeline is:

```
source → Reader/Parser → List<Node> → Expander → Emitter → Dart source
```

## The core insight (do not lose this)

The Dart team cancelled language-level macros in Jan 2025 because compile-time code
execution collided with their incremental-compilation and hot-reload guarantees.
**We sidestep that wall by being a preprocessor** — we regenerate files, so we never
need to be incremental. This is why we can do things the official macro system could
not, including the headline feature: **async compile-time evaluation** (compile-time
I/O — generating Dart types from JSON schemas, OpenAPI specs, etc.).

Do not try to integrate into the Dart compiler. The whole advantage is being outside it.

## Ground truth

The core engine logic (`expand`, `emit`, reader, tokenizer, parser) has already been
**validated in Python** and ported to Dart. The reference logic lives in
`doc/VALIDATED_LOGIC.md`. When in doubt about expected behaviour, that document is
authoritative — match its output exactly.

## Working rules

1. **Validate before claiming done.** Every phase has acceptance criteria with concrete
   input → output pairs. A task is not complete until the actual output matches.
   Write a test that proves it.

2. **No external dependencies in the core.** The engine (`lib/src/core.dart`,
   `reader.dart`, `tokenizer.dart`, `dart_parser.dart`, `nodes.dart`, `builtins.dart`)
   must depend only on the Dart SDK. Dev dependencies (`test`, `lints`) are fine.
   Async macros may use `dart:io` and `dart:convert` — both are SDK, so that is allowed.

3. **The emitter output must be valid, analyzer-clean Dart.** Run `dart format` and
   `dart analyze` on emitted output as part of testing. Generated code with analyzer
   warnings is a bug.

4. **Idempotency where it applies.** `expand(expand(x))` must equal `expand(x)`.
   Re-compiling an unchanged source file must produce byte-identical output.

5. **Update the spec as you go.** When a phase is complete, mark its tasks done in
   `backlog/BACKLOG.md` and note any deviations from the spec in that phase's file.
   If you discover the spec was wrong, fix the spec — do not silently diverge.

6. **Prefer honesty over impressiveness.** If something doesn't work, say so in the
   backlog. A known limitation documented is worth more than a hidden one.

## Project layout

```
lib/
  dmacro.dart            Public API barrel file
  src/
    core.dart               Node typedef, expand(), emit()  [DONE]
    reader.dart             S-expression reader             [DONE]
    tokenizer.dart          .dmacro tokenizer               [DONE]
    dart_parser.dart        .dmacro parser                  [DONE]
    nodes.dart              Typed node constructors ($if…)  [DONE]
    builtins.dart           Built-in macros                 [DONE]
    gensym.dart             Hygiene — unique symbols        [PHASE 1]
    splice.dart             Unquote-splicing                [PHASE 1]
    async_expand.dart       Async expander                  [PHASE 2]
    schema_macros.dart      defFromJsonSchema etc.          [PHASE 2]
bin/
  sexp.dart                 CLI: compile / repl / watch
test/
  *_test.dart               One test file per source file
example/
  *.dmacro / *.sexp         Example sources
doc/                        Architecture, validated logic, roadmap
specs/                      Per-phase specifications
backlog/                    Task tracking
```

## Implementation order

Follow the phases in order. Each builds on the last:

- **Phase 1 — Correctness:** `gensym`, `$splice`. Small, closes real bugs. Do first.
- **Phase 2 — Async eval:** the differentiator. The keystone experiment.
- **Phase 3 — Parser hardening:** named params, cascades, async/await.
- **Phase 4 — Developer experience:** watch mode, source-mapped errors.
- **Phase 5 — IDE integration:** VS Code extension. The long game.

Stop after Phase 2 and assess. If the schema-to-types demo is compelling, continue.
If not, the project is still a strong learning artifact — document and stop.

## Testing command reference

```bash
dart test                                    # run all tests
dart run bin/dmacro.dart compile <file>        # compile a source file
dart run bin/dmacro.dart repl                  # interactive
dart format lib/ test/                       # format
dart analyze                                 # static analysis
```
