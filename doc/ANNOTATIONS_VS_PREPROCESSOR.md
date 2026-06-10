# Annotations vs. the preprocessor — and why this project picked one

This repository briefly carried **two** code-generation systems. This document
records the comparison, the decision, and the reasoning, so the choice is not
re-litigated later.

- **The annotation system** (retired): `@DataClass` / `@Singleton` / `@Logged`
  on a hand-written class, transformed **in place** by `dart_macros build`.
- **The preprocessor** (kept): `defrecord` / `defunion` / `defFromJsonSchema`
  in a `.dmacro` / `.sexp` source file, compiled to a fresh `.dart` file by
  `dmacro compile`.

The two were never complementary — they solve the same problem two different
ways. Keeping both meant two parsers, two CLIs, two mental models, and a
headline ("**no annotations**") that contradicted half the codebase.

---

## How each one works

### Annotation system (the `build_runner` / `freezed` shape)

```dart
// You hand-write the class skeleton and tag it:
@DataClass()
class Payment {
  final double amount;
  final String currency;
  final String? reference;
  const Payment({required this.amount, required this.currency, this.reference});

  // ━━━ dart_macros generated ━━━
  //   copyWith / == / hashCode / toString are injected *inside* the class body
  // ━━━ end dart_macros ━━━
}
```

`dart_macros build` scans for annotated classes, strips any previous generated
block, and re-injects a fresh one between markers. Idempotent, in-place.

### Preprocessor (this project)

```dart
// You write a compact declaration; the whole .dart file is regenerated:
defrecord Payment {
  double  amount;
  String  currency;
  String? reference;
}
```

`dmacro compile` reads the source, expands macros (which may run arbitrary code,
including generation-time I/O), and emits a complete `.dart` file.

---

## Scored on the three criteria that mattered

### 1. Evolution / effectiveness — **preprocessor wins decisively**

| Capability                                   | Annotations | Preprocessor |
|----------------------------------------------|:-----------:|:------------:|
| `copyWith` / `==` / `hashCode` / `toString`  | ✅          | ✅           |
| `fromJson` / `toJson`                         | ❌          | ✅           |
| Deep (structural) value equality              | ❌          | ✅           |
| `copyWith` explicit-null (sentinel)           | ❌          | ✅           |
| Sealed union types (`defunion`)               | ❌          | ✅           |
| Generate a class from a **JSON Schema**       | ❌          | ✅           |
| Generate from an **OpenAPI** spec             | ❌          | ✅           |
| **Generation-time I/O** (read external files)  | ❌          | ✅           |
| Expression macros (`unless`, `swap!`, …)      | ❌          | ✅           |
| Two front-end syntaxes (`.dmacro` + `.sexp`)  | ❌          | ✅           |

The gap is structural, not incidental. The annotation transformer can only
**append members to a class that already exists** — it can never *create* a
type. So the project's keystone feature (read a JSON schema at generation time and
synthesize the Dart type) is impossible in the annotation model by construction.
The preprocessor regenerates whole files, so it has no such ceiling.

### 2. Usability for users — **preprocessor wins, with one honest caveat**

**Caveat in favour of annotations:** lower adoption friction. You keep writing
ordinary Dart classes and add a tag — nothing new to learn, and it drops into an
existing codebase file-by-file. That is a real advantage and the main reason the
annotation shape is popular (`freezed`, `json_serializable`).

**But, as shipped, annotations lose on usability anyway:**

- The package defined **no annotation classes**. `@DataClass()` / `@Logged()` /
  `@Singleton()` are undefined names, so every annotated file fails
  `dart analyze` with `undefined_annotation` — four errors on the sample input
  alone. (This is what broke CI.) A user would first have to hand-write marker
  classes the package never provided.
- Generated code lives **inside your source file**, so your hand-written code and
  machine-written code share one file — exactly the `*.g.dart` / merge-noise
  problem the project set out to avoid, just relocated.
- The preprocessor's output imports nothing, commits as an ordinary `.dart`
  file, and is analyzer-clean by construction (enforced in tests).

### 3. Complexity of the work — **preprocessor wins**

| | Annotations | Preprocessor |
|---|:--:|:--:|
| Exported from the package barrel | ❌ | ✅ |
| Test coverage | **0 tests** | **386 tests** |
| Documented in `CLAUDE.md` / `ARCHITECTURE.md` / specs | ❌ | ✅ |
| Lines of engine code to maintain | ~614 | the rest |

Keeping both is the most expensive option: it doubles the parser/CLI/doc surface
to maintain a strictly *less* capable second path that nobody tests. Removing the
annotation island collapses the project back to one coherent system.

---

## Decision

**Keep the preprocessor. Retire the annotation prototype.**

It wins on evolution/effectiveness (structurally more capable), on usability
(analyzer-clean, no annotation boilerplate, no in-file generated blocks), and on
complexity (one tested, documented system instead of two). The one genuine point
in the annotation column — drop-in adoption for existing classes — does not
outweigh losing the project's entire reason to exist (generation-time I/O), and is
undercut by the system shipping zero annotation classes.

### What was removed

- `bin/dart_macros.dart` (the `build` / `preview` / `clean` CLI)
- `lib/src/transformer.dart`
- `lib/src/generator.dart`
- `lib/src/models.dart`
- `lib/src/dart_source_parser.dart`

The annotation code samples above preserve what that approach looked like, so
nothing conceptual is lost.

### When would annotations have been the right call?

If the goal were *only* "add `copyWith`/`==` to my existing hand-written Dart
classes with the least disruption," the annotation shape is the better fit — that
is precisely the niche `freezed` and `json_serializable` own. This project aims
higher (types from external specs, generation-time I/O), and that aim is only
reachable with the preprocessor.
