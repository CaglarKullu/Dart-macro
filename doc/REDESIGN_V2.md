# dmacro v2 — Architecture Redesign

Grounded in the code as of June 2026. This document fixes three real problems
identified by honest review: no dependency graph in watch mode, no
reproducibility for generation-time I/O, and a 683-line parser that chases the
full Dart grammar. The core engine (Node, expand, emit, builtins) is sound and
stays.

---

## What we keep (do not rewrite)

| Component | Why it's fine |
|---|---|
| `Node = dynamic` + `Splice` | Validated against Python reference. Simple and correct. |
| `expand()` + `emit()` in `core.dart` | 710 lines, well-tested, matches spec. |
| `builtins.dart` | All builtins work. Idempotency holds. |
| `schema_macros.dart` | `defFromJsonSchema`, `defrecord`, `defunion`, `defenum` all work. |
| `useMacros` isolate machine | The worker/proxy design is correct and necessary. Keep it. |
| `MacroSnapshot` / isolation | Fixed correctly. Keep snapshot/restore around each file. |
| `async_expand.dart` | Async expander is correct. `asyncMacroNames()` etc. are clean. |
| `gensym.dart` / `splice.dart` | Small, correct. |

---

## What we fix

### Fix 1 — Dependency graph in watch mode  *(highest priority)*

**Problem**: `importMacros("templates.dmacro")` in `app.dmacro` means app.dmacro
depends on templates.dmacro. If templates.dmacro changes during `dmacro watch`,
app.dmacro is silently stale. The current watch only recompiles the file that
directly changed.

**Fix**: Build a reverse-dependency map during compilation.

```
depGraph: Map<String absolutePath, Set<String dependentPaths>>
```

Populated by intercepting `importMacros` and `useMacros` directives during each
file's compilation. These directives fire before any other expansion, so we can
record them in `_compileSingle`.

In watch mode, when file F changes:
1. Recompile F (already done).
2. Look up `depGraph[F]` → set of files that depend on F.
3. Recompile each dependent file (recursively, topologically).

Implementation: add `DependencyGraph` class in `lib/src/dep_graph.dart`.
Update `_compileSingle` to call `depGraph.record(source, imported)` for each
`importMacros`/`useMacros` directive it processes.
Update `_watchCmd` to use the graph for cascading recompiles.

This is ~80 lines of new code, no rewrites.

---

### Fix 2 — Reproducibility (content-hash cache)  *(second priority)*

**Problem**: `defFromJsonSchema("user.json")` reads `user.json` at generation
time. If `user.json` changes but `app.dmacro` does not, the output is stale
and watch mode won't notice. (The converse: if nothing changed, we regenerate
anyway — slow for large projects.)

**Fix**: A content-addressed output cache.

```
.dart_tool/dmacro/cache.json:
{
  "example/showcase/app.dmacro": {
    "fingerprint": "<sha256 of inputs>",
    "outputHash": "<sha256 of output>"
  }
}
```

**Fingerprint** = sha256 of:
- source file content
- content of every `importMacros` file
- content of every file read by `defFromJsonSchema` (recorded via a
  `generationInputs` accumulator that macros append to during expansion)

**Behaviour**:
- Before generating: compute fingerprint. If it matches cache → skip, output
  is already current.
- After generating: store fingerprint + output hash.
- Cache is invalidated when ANY input changes (source OR schema file).
- `dmacro compile --force` bypasses cache.

Implementation:
- `lib/src/gen_cache.dart` — 100 lines.
- `schema_macros.dart` `defFromJsonSchema` appends the schema path to a
  thread-local `generationInputs` list that `_compileSingle` reads back.
- `_compileSingle` computes fingerprint from those inputs + source, checks
  cache before expanding, writes cache after.

This also answers the "reproducibility" question: two developers with the same
inputs always get the same output, because the cache key IS the full input set.

---

### Fix 3 — Parser redesign: macro sites + opaque pass-through  *(third priority)*

**Problem**: `dart_parser.dart` is 683 lines trying to parse all Dart syntax.
Every new Dart language feature (patterns, switch expressions, extension types,
macros from the official team, etc.) potentially requires parser changes. This
is an unbounded maintenance burden.

**Root cause**: The parser tries to emit structured Nodes for non-macro Dart
(function bodies, class declarations, etc.). It should not. Those never go
through the expander.

**Fix**: Draw a hard boundary. The parser has two modes:

```
Mode A — MACRO SITE: parse as S-expression call (current behaviour)
Mode B — OPAQUE DART: copy token text verbatim, never structurally parse
```

**Rules for mode selection**:

At top level:
- If the first token is a recognised macro name → Mode A (parse macro call).
- If the token sequence matches user-block-macro heuristic
  (`ident CapitalisedIdent {`) → Mode A.
- Otherwise → Mode B: consume until the end of the top-level declaration
  (balanced braces + `;` or just `;`).

Inside a function body (already in Mode B):
- Scan for known macro names followed by `(` or `{`.
- When found, switch to Mode A for just that statement, then return to Mode B.
- Everything else in the body emits verbatim.

**What this removes from `dart_parser.dart`**:
- `_functionDeclaration` (the big recursive one — 120+ lines)
- `_classBody`, `_methodDeclaration`, `_constructorDeclaration`
- `_variableDeclaration`, `_forStatement`, `_whileStatement`, `_switchStatement`
- Most of `_statement` (only need to recognise macro calls in statement position)

**What stays**:
- `_defrecord`, `_defunion`, `_defenum`, `_defmacroDecl` — these ARE structured
  and need proper parsing.
- `_userBlockMacro` — same.
- `_expr` and `_argList` — macro arguments need to be parsed as expressions.
- `_blockBody` used inside `defmacro` template bodies.

**Expected result**: `dart_parser.dart` shrinks from 683 → ~350 lines. The
remaining 350 lines are ALL macro-specific, not general Dart. Every future Dart
language feature that's not a macro argument or a block macro field just passes
through as opaque bytes.

**Migration note**: Files that currently expand correctly will continue to
expand correctly — their macro calls are parsed identically. Non-macro Dart
that the current parser silently miscompiles (switch expressions, extension
types, etc.) will now pass through correctly instead of erroring.

**NEW PARSER DESIGN** (pseudocode):

```
parseProgram():
  while not EOF:
    if peek is known macro name:
      yield parseMacroForm()     ← Mode A
    elif peek matches block-macro heuristic:
      yield parseMacroForm()     ← Mode A
    else:
      yield parseOpaqueDecl()    ← Mode B

parseOpaqueDecl():
  // Collect tokens verbatim until end of top-level form.
  // End = balanced braces terminate a class/function, OR ';' at depth 0.
  buf = StringBuilder
  depth = 0
  loop:
    t = advance()
    buf.write(t.rawText)
    if t == '{': depth++
    if t == '}': depth--; if depth == 0: break
    if t == ';' and depth == 0: break
  return OpaqueNode(buf.toString())

parseMacroForm():
  // Existing logic — unchanged.

// In the expander, OpaqueNode emits verbatim:
emit(OpaqueNode n):
  return n.text
```

---

## What we do NOT do

| Rejected option | Reason |
|---|---|
| Use `dart:analyzer` as the front-end | Correct but expensive: analyzer pulls 40+ transitive deps, has a complex API surface, and is versioned separately from the Dart SDK. The pass-through model achieves the same goal (support all Dart syntax) without the dependency. |
| Replace global registry with threaded CompileContext | Already justified in `doc/ARCHITECTURE.md`. The ergonomic cost is too high. The snapshot/restore fix is sufficient. |
| Full rewrite of core/expander | Working, tested, validated. Rewriting validated logic is waste. |
| Replace `useMacros` isolate with subprocess | The isolate design is correct. The complexity is in macro_loader.dart, not architecturally wrong. Keep it. |

---

## Implementation order

**Phase A (1–2 days)**: Dependency graph  
`lib/src/dep_graph.dart` + wire into `_compileSingle` + `_watchCmd`.  
Test: change `templates.dmacro`, verify `app.dmacro` recompiles in watch mode.

**Phase B (1–2 days)**: Reproducibility cache  
`lib/src/gen_cache.dart` + `generationInputs` accumulator in schema_macros +  
fingerprint check in `_compileSingle`.  
Test: change `user.json`, verify output regenerates. Change nothing, verify skip.

**Phase C (2–3 days)**: Parser redesign  
Introduce `OpaqueNode`, rewrite `_declaration` to default to opaque pass-through,  
delete the non-macro statement/declaration parsing methods.  
Test: every existing test still passes (macro sites unchanged) + new tests for  
switch expressions, extension types, etc. passing through verbatim.

---

## After Phase C: what the architecture looks like

```
source (.dmacro)
  │
  ├── DmacroParser v2 (350 lines)
  │     ├── macro sites → List<Node>   ← structured, expandable
  │     └── opaque Dart → OpaqueNode   ← verbatim strings, never parsed
  │
  ├── DepGraph records importMacros / useMacros targets
  │
  ├── GenCache checks fingerprint (source + imports + schema files)
  │
  ├── Expander (unchanged)
  │     macro nodes → expanded nodes
  │     opaque nodes → pass-through
  │
  └── Emitter (unchanged)
        expanded nodes → Dart source
        opaque nodes → emit verbatim
```

This eliminates the parser maintenance burden, makes watch mode correct for
shared macro files, and makes generation-time I/O reproducible.

---

## Success criteria

After all three phases:

1. `dart test` passes with no regressions.
2. Edit `templates.dmacro`, run `dmacro watch .` → `app.dmacro` recompiles
   automatically within 500 ms.
3. Edit `user.json`, compile `app.dmacro` → new output. Compile again without
   changes → "skipped (fingerprint match)".
4. Add a switch expression to a `.dmacro` file → passes through verbatim, no
   ParseException.
5. `dart analyze` on all generated outputs: zero issues.
