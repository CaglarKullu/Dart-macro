# Phase 5 — IDE Integration (VS Code Extension)

**Goal:** close the "two-compilation" gap from the developer's point of view. With the
extension installed, the workflow becomes: write `.dmacro`, save, generated `.dart`
appears automatically, and the IDE treats the `.dart` as the analyzed source of truth —
exactly how TypeScript hides `tsc`.

**Prerequisite:** Phases 1–4 complete. Do not start this until the engine is correct
(1–2), handles real Dart (3), and has watch + located errors (4). The extension is a thin
shell over a solid CLI; build the CLI first.

**Status caveat:** this is the largest, least-Dart phase (it's TypeScript/VS Code API
work). It is the difference between "interesting tool" and "adoptable tool", but it is
explicitly the long game. Treat it as optional/stretch relative to 1–4.

---

## Task 5.1 — Compile-on-save

### Behaviour
The extension watches `.dmacro`/`.sexp` files in the workspace and invokes the `sexp`
CLI (`compile <file>`) on save, writing the sibling `.dart`.

### Approach
- VS Code extension (TypeScript) using the `onDidSaveTextDocument` event.
- Shell out to the project's `sexp` CLI (resolve via `dart run bin/dmacro.dart` or a
  compiled `sexp` executable on PATH).
- Surface CLI stderr as VS Code diagnostics (see 5.3).

### Acceptance criteria
1. Saving a `.dmacro` regenerates its `.dart` with no manual command.
2. Works on a fresh clone after a one-time "select Dart SDK / sexp path" setup.

---

## Task 5.2 — Syntax highlighting

### Behaviour
A TextMate grammar for `.dmacro` (and optionally `.sexp`) so macro keywords, types,
strings, and comments are coloured.

### Approach
- `syntaxes/dmacro.tmLanguage.json` — grammar covering: `defrecord`/`defunion`/macro
  keywords, Dart control-flow keywords, types, string literals, numbers, comments,
  operators.
- Register the `dmacro` language in `package.json` with file extension `.dmacro`.

### Acceptance criteria
1. `.dmacro` files are syntax-highlighted on open.
2. Macro keywords are visually distinct from regular identifiers.

---

## Task 5.3 — Diagnostics in the editor

### Behaviour
Parse/compile errors from the CLI appear as red squiggles on the correct `.dmacro` line,
using the located errors from Phase 4.

### Approach
- Parse the CLI's `file:line:column: message` error format.
- Populate a `vscode.DiagnosticCollection` mapped to the source document.
- Clear diagnostics on successful compile.

### Acceptance criteria
1. A syntax error shows a squiggle at the right line:column in the `.dmacro`.
2. Fixing the error and saving clears the squiggle.

---

## Task 5.4 — Niceties (stretch within stretch)

- Command palette: "dmacro: Compile File", "dmacro: Compile Workspace".
- Status-bar item showing last compile result.
- Go-to-definition from a macro use to its `defmacro` (requires a macro index; nontrivial
  — defer unless clearly valuable).
- Optionally fold generated `.dart` files in the explorer / mark them read-only.

---

## Distribution

- Package with `vsce`; publish to the VS Code Marketplace (and Open VSX for non-MS editors).
- README with an animated GIF of the save → generate loop — this is the single most
  persuasive asset for adoption.

---

## Phase 5 definition of done

- Extension compiles `.dmacro` on save and writes `.dart`.
- `.dmacro` syntax highlighting works.
- CLI errors surface as editor diagnostics at correct locations.
- Packaged and installable; README shows the workflow.
