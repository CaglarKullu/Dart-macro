# Phase 10 — Macro authoring as the product

> **Status:** the pivot. See `doc/VISION.md`. This phase reframes the built-ins as a
> standard library and closes the one gap that makes "write your own generator" true:
> **user-authored Dart-function macros, loadable from a user's own project.**

## Goal

A Dart developer with no knowledge of this repository can:

1. Write a macro that runs arbitrary Dart logic over code-as-data.
2. Register it from their own project (no fork, no published package required).
3. Use it in a `.dmacro` / `.sexp` / inline-`.dart` source the same way they use
   `defrecord`.
4. Get an error that points at *their macro* when it produces bad output — not a
   cryptic Dart parse error 200 lines downstream.

When all four hold, the built-ins are no longer special. They are just the first
entries in a standard library the user can extend.

---

## The authoring model (make the two paths explicit and connected)

dmacro will document **three tiers**, weakest-but-easiest to strongest:

### Tier 1 — Template macros (exists today, keep)

```dart
defmacro guard(cond, err) {
  unless (cond) { throw Exception(err); }
}
```

Pure substitution: call-site args replace parameter names in the body. No logic.
Written inline in any `.dmacro` source. This is the on-ramp — most users start
here and never need more. **Already implemented.** Phase 10 only documents it as
"tier 1" and ensures the error story (below) covers it.

### Tier 2 — Computed template macros (NEW, small)

Template macros that can branch and iterate over their arguments without dropping
to Dart. A minimal, *safe* expansion-time vocabulary operating on nodes:

- `$map(list, x => template)` — repeat a template per element
- `$if`/`$cond` at expansion time (distinct from emitted runtime `if`)
- `$field`, `$type`, `$name` accessors over a record-field node

This is the 15% that template macros can't reach today (e.g. "emit one line per
field") but that does not need full Dart. Scope deliberately small; it is sugar
over what the expander already does, not a new language.

> **Open question for this phase:** is Tier 2 worth building, or do we send anyone
> who needs iteration straight to Tier 3? Decision gate at 10.3.

### Tier 3 — Dart-function macros (exists for built-ins; make loadable — THE GAP)

```dart
// my_macros.dart — in the USER's project
import 'package:dmacro/dmacro.dart';

void register() {
  defMacro('defwidget', (args) {
    // arbitrary Dart: inspect args, loop over fields, build a Node
    return [ /* ...generated class node... */ ];
  });
}
```

Today `defMacro` / `defAsyncMacro` are public, but only `registerBuiltins()` and
`registerSchemaMacros()` call them, both inside this repo. The gap: **a user's
`register()` must be discoverable and run before compilation.** This phase makes
that real. See 10.2 for the mechanism.

---

## Tasks

### 10.1 Reframe built-ins as a standard library (docs + structure, no behavior change)

- [ ] `lib/src/builtins.dart` and `schema_macros.dart` gain a header comment:
      "This is the dmacro standard library. Every macro here is written with the
      public `defMacro` / `defAsyncMacro` API. You can write your own the same way
      — see `doc/WRITING_MACROS.md`."
- [ ] New `doc/WRITING_MACROS.md`: the authoring guide. Walks tier 1 → 3 with one
      worked example per tier. The tier-3 example reimplements a *tiny* `defpair`
      so the reader sees the whole `(args) → Node` loop end to end.
- [ ] README headline rewritten around "write your own generator"; schema/OpenAPI
      demoted to "flagship standard-library macros."
- [ ] No engine code changes. Acceptance: all existing tests still pass unchanged.

### 10.2 Loadable user macros (the keystone of the pivot)

The mechanism. Recommended design (decide explicitly before building):

- [ ] `dmacro.yaml` (or a `macros:` key in `pubspec.yaml`) in the user's project
      lists Dart files that register macros:
      ```yaml
      macros:
        - tool/my_macros.dart
      ```
- [ ] Each listed file exposes a top-level `void registerMacros()` that calls
      `defMacro` / `defAsyncMacro`.
- [ ] The CLI, before compiling, loads and runs each `registerMacros()`.
      **Loading-arbitrary-Dart constraint:** the CLI cannot `import` an arbitrary
      user path at its own compile time. Options:
      - (a) **Spawned isolate + generated bootstrap**: CLI writes a tiny
        `.dart_tool/dmacro/bootstrap.dart` that imports the user files and the
        engine, then `dart run`s it to do the actual compile. Reuses the whole
        engine; the user's macros are real Dart with full power.
      - (b) **`Isolate.spawnUri`** on each macro file. Lighter, but passing the
        macro registry across the isolate boundary is awkward (functions aren't
        sendable).
      - (c) Require the user to depend on `dmacro` and run *their own* entry point
        that calls `registerMacros()` then `asyncCompileDartLike()`. Most honest,
        least magic, no isolate plumbing — but the entry point is the user's file,
        not the `dmacro` binary.

      > **DECISION (validated end-to-end):** **Ship (c) now, build (a) later as UX
      > sugar over it.** Option (c) was proven working with zero engine changes: a
      > fresh project with a path dependency on `dmacro` registered a custom
      > `defwidget` macro via the public `defAsyncMacro` API from its own
      > `tool/generate.dart` and compiled a `.dmacro` source using it, producing a
      > complete `StatelessWidget`. The public API already supports the whole
      > contract. (a) remains desirable so users get the single `dmacro compile`
      > command + `dmacro.yaml` instead of owning an entry point — it is now a
      > pure-UX layer, not a blocker for the pivot.
      >
      > **Findings from the validation run:**
      > 1. **Block-declaration syntax is hardcoded.** `dart_parser.dart` only gives
      >    `Name { fields }` syntax to `defrecord`/`defunion` (lines ~58–59). User
      >    macros must be called with function syntax:
      >    `defwidget("MyButton", "String label", …)`. New task 10.2b below.
      > 2. **`build.dart` at package root is a trap.** Dart treats a root
      >    `build.dart` as a native-assets build hook and refuses to run the
      >    project without `--enable-experiment=native-assets`. The documented
      >    pattern must place the entry point at `tool/generate.dart`.
      > 3. **String args arrive with embedded quotes** (`'"MyButton"'`). Every
      >    macro author will write the same `_unquote` helper; export one from the
      >    public API. New task 10.2c below.
- [ ] **10.2b — generic block syntax for user macros:** when the parser sees
      `ident Ident {` and `ident` is not a known declaration keyword, parse the
      block record-style and desugar to a macro call with field nodes — so user
      macros get `defwidget MyButton { String label; }` just like `defrecord`.
      (Today this only works for the hardcoded built-ins.)
- [ ] **10.2c — export an `unquote` helper** (and document arg shapes) so macro
      authors don't each rediscover that string literals keep their quotes.
- [ ] `importMacros("package:foo/bar.dart")` extended to load **Dart** macro files
      (currently only `.dmacro`/`.sexp` template files), reusing the same loader.
- [ ] Acceptance: a fixture project under `test/fixtures/user_macros/` defines a
      `defpair` Dart macro in its own file, lists it, and compiles a source that
      uses `defpair` — with zero edits to `lib/`.

### 10.3 Tier-2 decision gate

- [ ] Spike `$map` over record fields in one template macro.
- [ ] **DECISION:** ship Tier 2, or document "need iteration → use Tier 3" and skip.
      Record the call here. Do not build Tier 2 on momentum if Tier 3 covers it.

### 10.4 Macro-author error messages (what makes authoring tolerable)

The current failure mode: a macro emits malformed Dart, and the user sees a parse
error in *generated output* with no link to the macro that produced it. Fix the
attribution so the error names the macro.

- [ ] When emitting a node produced by macro `M`, tag the subtree with `M`'s name
      (reuse the existing origin-tracking plumbing used for `@dmacro-origin`).
- [ ] On emit/parse failure of generated Dart, the error reads:
      `macro "defwidget" produced invalid Dart at field 2: <snippet>` — name first.
- [ ] `defMacro` wrapper catches exceptions thrown *inside* a user macro and
      reattributes: `macro "defwidget" threw: <message>` with the call-site origin.
- [ ] `dmacro trace <file>` output reworked for macro authors: show, per expansion
      step, the macro name, its input args, and its output node — indented tree.
- [ ] Acceptance: a deliberately-broken fixture macro yields an error whose first
      line contains the macro name and the call-site `file:line`.

### 10.5 Distribution (share macro libraries)

- [ ] Document the "macro library package" pattern: a normal pub package that
      depends on `dmacro` and exports a `registerMacros()`; consumers list it in
      `dmacro.yaml`.
- [ ] `importMacros("package:teammacros/widgets.dart")` resolves via
      `.dart_tool/package_config.json` (the resolver already exists for the
      `.dmacro` case — extend, don't rewrite).
- [ ] Acceptance: a second fixture package provides a macro consumed by the first.

---

## Acceptance for the phase

The pivot is real when this end-to-end works **without touching `lib/`**:

```
# in a fresh user project that depends on dmacro
$ cat tool/widget_macros.dart
import 'package:dmacro/dmacro.dart';
void registerMacros() {
  defMacro('defwidget', (args) { /* ...returns a StatelessWidget node... */ });
}

$ cat dmacro.yaml
macros:
  - tool/widget_macros.dart

$ cat lib/buttons.dmacro
defwidget MyButton { String label; VoidCallback onPressed; }

$ dart run dmacro compile lib/buttons.dmacro
✓ lib/buttons.dart   # contains a complete StatelessWidget the user's macro generated
```

A user wrote a generator. We shipped none of it. That is the product.

---

## Non-goals for Phase 10

- Real-time IDE type resolution for generated types (unchanged constraint; that
  remains impossible for a preprocessor — see `doc/ARCHITECTURE.md`).
- A sandbox/security model for untrusted macros. Macros are arbitrary Dart by
  design; loading one is as trusted as adding a dev-dependency. Document that
  honestly; do not pretend to sandbox.
- Turning Tier 1 template macros into a full language. If you need a language,
  that is Tier 3 (real Dart).
