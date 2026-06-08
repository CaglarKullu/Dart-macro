# Phase 1 — Correctness

**Goal:** close two real correctness gaps in the existing engine: hygiene (`gensym`) and
general unquote-splicing (`$splice`). Both are small, well-understood, and make existing
macros correct rather than merely impressive.

**Prerequisite:** the ported Dart engine (`core.dart`, `reader.dart`, `tokenizer.dart`,
`dart_parser.dart`, `nodes.dart`, `builtins.dart`) compiles and reproduces the output in
`docs/VALIDATED_LOGIC.md`.

---

## Task 1.1 — `gensym` (hygiene)

### Problem
Macros that introduce temporary variables currently hardcode names (`_tmp`, `_attempt`,
`_e`). If the calling code uses the same name, the macro silently breaks via variable
capture. Example failure: `swap!(a, _tmp)` — the macro's internal `_tmp` collides with
the user's `_tmp`.

### Solution
A counter-based unique-symbol generator, reset per compilation unit for deterministic
output.

```dart
// lib/src/gensym.dart
int _counter = 0;

/// Returns a unique identifier unlikely to collide with user code.
/// Format: __<prefix>_<n>  e.g. __swap_0
String gensym([String prefix = 'g']) => '__${prefix}_${_counter++}';

/// Resets the counter. MUST be called at the start of each compilation unit
/// so that output is deterministic (same input → same symbol names).
void resetGensym() => _counter = 0;
```

### Integration
- `compile()` and `compileDartLike()` call `resetGensym()` before expanding.
- Every builtin that introduces a temporary uses `gensym`:
  - `swap!` → `gensym('swap')`
  - `withRetry` → `gensym('attempt')`, `gensym('err')`

### Acceptance criteria
1. `swap!(a, __swap_0)` does not collide — the macro's temp is `__swap_1` or similar.
2. Compiling the same source twice produces byte-identical output (counter reset works).
3. Existing validated output still matches, except temp variable names are now
   `__swap_0` etc. Update the regression expectations accordingly.
4. Test: a `.dmacro` that deliberately names a variable `__swap_0`, then uses `swap!`,
   compiles to code where the two do not clash, and the emitted Dart passes `dart analyze`.

---

## Task 1.2 — `$splice` (unquote-splicing)

### Problem
A macro that needs to inject *multiple* statements into its parent currently only works
inside `defn` bodies, via a special-case flatten of `do` blocks. A macro used inside an
`if` branch, a `while` body, or another macro does not splice correctly.

### Solution
A `Splice` marker type that the expander recognizes and inlines into the parent list,
generalizing the `defn`-body flatten to every context.

```dart
// lib/src/splice.dart
class Splice {
  final List<Node> nodes;
  const Splice(this.nodes);
}

/// Marks a list of nodes to be spliced into the enclosing form.
Node $splice(List<Node> nodes) => Splice(nodes);
```

### Expander change (`core.dart`)
After expanding a list's children, flatten any `Splice` children into the parent:

```dart
Node expand(Node node) {
  if (node is! List || node.isEmpty) return node;
  final head = node[0];
  final args = (node as List).sublist(1);

  if (head is String && _macros.containsKey(head)) {
    return expand(_macros[head]!(args));
  }

  final expanded = args.map(expand).toList();
  final out = <Node>[head];
  for (final child in expanded) {
    if (child is Splice) {
      out.addAll(child.nodes);   // inline
    } else {
      out.add(child);
    }
  }
  return out;
}
```

### Emitter change (`core.dart`)
- `do`, `defn` body, `defclass` body, and block contexts must handle a `Splice` that
  reaches emit (it should not, if expand flattens correctly — but assert/guard).
- Remove the old `defn`-body special-case flatten once `$splice` covers it, OR keep `do`
  flattening as a convenience and additionally support `$splice` everywhere.

### Migration
Rewrite `swap!` to return a `$splice` of three statements instead of a `do` block, and
verify it now works inside an `if`/`when` branch (which is the case the old approach
already handled) **and** inside a `while` body and nested inside another macro (the cases
it did not).

### Acceptance criteria
1. `swap!` works inside `when (...) { swap!(a,b); }` — already worked, must still work.
2. `swap!` works inside `while (...) { swap!(a,b); }` — new, must now work.
3. A macro that `$splice`s statements works when nested inside another macro's output.
4. `expand(expand(x)) == expand(x)` still holds.
5. No `Splice` object ever reaches the final emitted string.
6. Emitted Dart passes `dart analyze`.

---

## Phase 1 definition of done

- `lib/src/gensym.dart` and `lib/src/splice.dart` exist and are exported from
  `lib/dmacro.dart`.
- All builtins that introduce temporaries use `gensym`.
- `swap!` uses `$splice` and works in all three contexts above.
- `test/gensym_test.dart` and `test/splice_test.dart` pass.
- `docs/VALIDATED_LOGIC.md` regression example still matches (with updated temp names).
- `backlog/BACKLOG.md` Phase 1 tasks marked done; any deviations noted in this file.
