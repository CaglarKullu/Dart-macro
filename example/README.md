# Examples

Each directory is a self-contained use case that demonstrates what Lisp-style macros make possible in Dart. Compile any `.dmacro` file with:

```bash
dart run bin/dmacro.dart compile <path/to/file.dmacro>
```

You can also embed macros directly in regular `.dart` files using `// @@dmacro` / `// @@end` blocks — no separate file needed. And you can import macro definitions from other files with `importMacros()`.

---

## [`ecommerce/`](ecommerce/)

A realistic e-commerce domain model — products, orders, cart items, shipping addresses, and an order status state machine.

**What to notice:** `defrecord` generates a complete immutable class with `copyWith`, deep `==`/`hashCode`, `toString`, `fromJson`, and `toJson` from a 5-line spec. `defunion` generates a sealed class hierarchy from a compact variant list. Neither `freezed` nor any annotation-based tool creates the class from scratch — they annotate one you already wrote. The generated code is zero-dependency and analyzer-clean.

Demonstrates: `defrecord`, `defunion`, `unless`, `assertThat`, typed `defmacro`

```bash
dart run bin/dmacro.dart compile example/ecommerce/models.dmacro
```

---

## [`api_from_schema/`](api_from_schema/)

Generate a Dart class for every JSON Schema in a directory — one macro call.

**What to notice:** When you run `dmacro compile`, the macro scans the directory and generates one class per `.json` file — no annotation class to write first. The generated types are **static Dart** that compile into your binary. If a schema file changes, you re-run dmacro and redeploy — same as any code generator. The advantage over `build_runner` is that no annotated source file needs to exist upfront; the spec is the source.

Demonstrates: `defAllFromJsonSchema`

```bash
dart run bin/dmacro.dart compile example/api_from_schema/models.dmacro
```

---

## [`openapi_demo/`](openapi_demo/)

Generate types directly from an OpenAPI 3.0 spec by schema name. Accepts both `.json` and `.yaml` / `.yml` specs — no external YAML library required. `oneOf` schemas are automatically mapped to sealed `defunion` hierarchies.

**What to notice:** Your OpenAPI spec is the source of truth. The Dart types don't exist until the macro runs — there's nothing to annotate, nothing to scaffold. Add this step to CI and your Dart types track your spec automatically. Demonstrates that you can fetch and process specs at generation time, with zero runtime I/O or adaptation.

Demonstrates: `defFromOpenApi`, async generation, YAML parsing

```bash
dart run bin/dmacro.dart compile example/openapi_demo/models.dmacro
```

---

## [`schema_demo/`](schema_demo/)

Generate a single class from a JSON Schema file.

**What to notice:** One line of macro source generates ~40 lines of production-quality Dart — constructor, value equality, serialization, `copyWith`. The output imports nothing and has no runtime dependencies. Perfect for showing how much boilerplate a single macro call eliminates.

Demonstrates: `defFromJsonSchema`, `@json_key` per-field key override

```bash
dart run bin/dmacro.dart compile example/schema_demo/models.dmacro
```

---

## [`input/`](input/)

Side-by-side comparison of two approaches to the same model: hand-written with annotations (the old `freezed` approach, frozen as an illustration) and via the preprocessor using `defrecord`. Shows that the preprocessor approach generates identical or superior output with less ceremony.

Demonstrates: the difference between generating types from scratch vs annotating existing classes

---

## [`payment.dmacro`](payment.dmacro) / [`payment.sexp`](payment.sexp)

The same payment domain model written in both syntaxes — Dart-like (`.dmacro`) and S-expression (`.sexp`). Good for comparing the two styles and seeing that both produce identical output.

The `.sexp` file is raw Lisp syntax: `(defrecord Payment ...)`. The `.dmacro` file is the same semantics in Dart clothing. Under the hood, both produce identical `List<Node>` ASTs — the expander and emitter are shared.

---

## [`main.dart`](main.dart)

A runnable Dart program that exercises all built-in macros and prints the emitted output.

```bash
dart run example/main.dart
```

---

## Four recent improvements (Phase 9)

### Inline `.dart` blocks

No `.dmacro` file needed — embed macros directly in existing Dart code:

```dart
// lib/models.dart
// @@dmacro
defrecord Product { String id; double price; }
// @@end
```

Run `dart run bin/dmacro.dart compile lib/models.dart` and the block expands in-place. The macro source is preserved as comments so the file stays analyzer-clean and re-runs are idempotent.

### Share macros across files

Import macro definitions from other files or pub packages:

```dart
importMacros("lib/macros/validators.dmacro");
importMacros("package:team_macros/common.dmacro");
```

### VS Code "Expand Macro" command

Open any `.dmacro` or `.sexp` file in VS Code and run **dmacro: Expand Macro at Cursor** — see the full expansion tree in a side panel without opening the generated `.dart` file.

### Typed macros with output validation

Declare what your custom macro is supposed to produce:

```dart
defmacro(declaration) makeModel(name) { ... }  // must produce a class/enum/typedef
defmacro(expression) doubled(x) { ... }        // must produce an expression
defmacro(statement) logIt(x) { ... }           // must produce a statement
```

If the macro doesn't match its declaration, you get a clear error at call time — not a cryptic Dart parse error downstream.
