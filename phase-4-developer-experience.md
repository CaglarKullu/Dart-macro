# Phase 4 — Developer Experience

**Goal:** make the tool usable for daily development. Two things matter most: automatic
recompilation on save (watch mode) and error messages that point at the `.dmacro` source,
not the generated `.dart` (source-mapped diagnostics).

**Prerequisite:** Phase 3 complete (parser handles real-enough Dart).

**Why now:** without watch mode the workflow is a manual two-step that recreates the exact
`build_runner` friction this project set out to avoid. Without source-mapped errors, a
compile failure sends the developer hunting through generated code. These two items are
the difference between "a demo" and "something I'd keep installed".

---

## Task 4.1 — Watch mode

### Behaviour
`dart run bin/sexp.dart watch <path>` watches `.dmacro` and `.sexp` files under `<path>`
and recompiles each on change, writing the sibling `.dart` file.

### Implementation
Use `dart:io` `Directory.watch(recursive: true)` — no external dependency.

```dart
Future<void> watch(String path) async {
  print('Watching $path … (Ctrl+C to stop)');
  // Initial full build so outputs exist immediately.
  await _compileAll(path);

  Directory(path).watch(recursive: true).listen((event) async {
    final p = event.path;
    if (!(p.endsWith('.dmacro') || p.endsWith('.sexp'))) return;
    if (event.type == FileSystemEvent.delete) return;
    try {
      final out = p.replaceFirst(RegExp(r'\.(dmacro|sexp)$'), '.dart');
      await _compileFile(p, out);
      print('✓ ${_rel(p)} → ${_rel(out)}');
    } catch (e) {
      stderr.writeln('✗ ${_rel(p)}: $e');   // keep watching; don't crash
    }
  });
}
```

### Details
- **Debounce** rapid duplicate events (editors often fire modify twice). A 50–100ms
  debounce per path is enough.
- A failed compile prints the error and keeps watching — never exits the watch loop.
- On startup, do one full build so `.dart` outputs exist before the first edit.

### Acceptance criteria
1. Editing a `.dmacro` and saving regenerates its `.dart` within ~100ms.
2. A syntax error prints a clear message and watch continues; fixing it recompiles.
3. Duplicate save events do not double-compile (debounce works).
4. Deleting a source file does not crash the watcher.

---

## Task 4.2 — Source-mapped errors

### Problem
Tokenizer/parser errors currently lack a line:column in the `.dmacro` source, and runtime
analyzer errors in the generated `.dart` have no path back to the source line that produced
them.

### Part A — Located parse/tokenize errors
- Tokenizer already tracks `_pos`; convert offset → line:column and attach to
  `TokenizerException` / `ParseException`.
- Error format: `payment.dmacro:12:5: Expected ';' but found '}'`.
- Include the offending source line and a caret under the column:

```
payment.dmacro:12:5: Expected ';' but found '}'
    return true
            ^
```

### Part B — Origin tracking through expansion (best-effort)
- Each `Node` produced by the parser may carry an optional source span. Since `Node` is
  `dynamic`, track spans in a side-table keyed by object identity (an `Expando<Span>`),
  not by mutating the list shape.
- The emitter, when it writes a top-level form, prepends a comment:
  `// from payment.dmacro:34` so a developer hitting an analyzer error in `.dart` can find
  the source form. Full per-line source maps are out of scope; form-level origin comments
  are the pragmatic 80%.

### Acceptance criteria
1. Every tokenizer/parser error reports `file:line:column` plus the source line and caret.
2. Each top-level emitted form carries a `// from <file>:<line>` origin comment.
3. A deliberately broken `.dmacro` yields an error a human can act on without opening the
   generated file.

---

## Task 4.3 — CLI ergonomics

- `sexp compile <dir>` (not just a file) compiles every source file under the dir.
- `--check` mode: compile in memory and report whether outputs are up to date, exit
  non-zero if stale (useful for CI to verify committed `.dart` matches `.dmacro`).
- `--format` flag (default on): run the result through `dart format` before writing.
- Clear, friendly `--help`.

### Acceptance criteria
1. `sexp compile lib/` compiles all sources under `lib/`.
2. `sexp compile lib/ --check` exits non-zero when a `.dart` is out of date.
3. Output is `dart format`-clean by default.

---

## Phase 4 definition of done

- `watch` works with debounce and survives errors.
- All parse/tokenize errors are located with source line + caret.
- Top-level forms carry origin comments.
- `--check` enables CI verification of committed output.
- Backlog updated.
