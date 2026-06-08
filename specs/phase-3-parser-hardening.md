# Phase 3 — Parser Hardening

**Goal:** make the `.dmacro` parser handle the messy real-Dart constructs it currently
chokes on. The trust-killer is a developer writing ordinary Dart inside a `.dmacro` file
and hitting a parse error. This phase widens the supported subset toward real Dart.

**Prerequisite:** Phase 2 complete and the decision was "continue".

**Reality check:** the parser will never cover 100% of Dart, and that's acceptable. The
target is the **common 95%** that appears in everyday model/logic code. Where a construct
is out of scope, fail with a clear, located error (Phase 4) rather than mis-parsing.

---

## Task 3.1 — Named arguments

### Need
`Payment(amount: 100, currency: "EUR")` and `obj.copyWith(amount: 50)` are pervasive in
Dart and currently unsupported.

### Approach
Extend the argument-list parser to accept `identifier: expr` pairs. Represent a named arg
as a distinct node, e.g. `['named', 'amount', 100]`, and teach the call emitter to render
named args as `amount: 100`.

### Acceptance criteria
1. `Payment(amount: 100, currency: "EUR")` parses and emits identically.
2. Mixed positional + named (`foo(1, x: 2)`) works.
3. Named args in method calls (`o.copyWith(a: 1)`) work.
4. Emitted Dart passes `dart analyze`.

---

## Task 3.2 — Cascades

### Need
`builder..add(1)..add(2)..flush()` is idiomatic Dart.

### Approach
Add cascade parsing in the postfix layer: `..member` / `..method(args)` chains operating
on a single receiver. Represent as a cascade node; emit with `..`.

### Acceptance criteria
1. `list..add(1)..add(2)` parses and round-trips.
2. Cascade mixed with normal member access works.
3. Analyzer-clean output.

---

## Task 3.3 — `async` / `await` / `=>`

### Need
Real functions are often `async`, use `await`, or are expression-bodied (`=>`).

### Approach
- Function declarations: accept an optional `async` modifier before the body; emit it.
- Expression-bodied functions: `Type name(params) => expr;` → support arrow bodies in
  `_fnDecl`.
- `await expr` as a unary-level expression node; emit `await expr`.

### Acceptance criteria
1. `Future<void> f() async { await g(); }` parses and emits correctly.
2. `int double(int x) => x * 2;` (arrow body) works.
3. `await` inside expressions works.
4. Analyzer-clean output.

---

## Task 3.4 — Misc expression coverage

Prioritized by frequency; implement as far as time allows:

- Ternary `cond ? a : b`.
- List/map/set literals: `[1, 2]`, `{ 'k': v }`, `{1, 2}`.
- String interpolation passthrough: `"hello $name"` and `"${expr}"` (treat the whole
  string as a raw literal; do not try to parse the interpolation).
- Null-aware operators: `a?.b`, `a ?? b`, `a ??= b`.
- Spread: `[...xs]`.

### Acceptance criteria
- Each supported construct round-trips through compile and passes `dart analyze`.
- Unsupported constructs produce a located error (Phase 4), never silent mis-parse.

---

## Task 3.5 — Conformance corpus

Create `test/corpus/` containing real-world Dart snippets (model classes, small services,
the user's own typical code patterns). For each, assert it either:
(a) parses and emits analyzer-clean Dart, or
(b) fails with a clear, located error listing the unsupported construct.

This corpus is the regression guard for "does it handle real Dart" and should grow
whenever a new gap is found in practice.

---

## Phase 3 definition of done

- Named args, cascades, `async`/`await`/arrow bodies supported.
- As much of Task 3.4 as feasible, each with tests.
- `test/corpus/` established with at least 10 real snippets.
- Every snippet either compiles clean or errors clearly — never mis-parses silently.
- Backlog updated; remaining unsupported constructs explicitly listed as known limitations.
