# Examples

Each directory is a self-contained use case that demonstrates what Lisp-style macros make possible in Dart. Compile any `.dmacro` file with:

```bash
dart run bin/dmacro.dart compile <path/to/file.dmacro>
```

---

## [`ecommerce/`](ecommerce/)

A realistic e-commerce domain model — products, orders, cart items, shipping addresses, and an order status state machine.

**What to notice:** `defrecord` generates a complete immutable class with `copyWith`, deep `==`/`hashCode`, `toString`, `fromJson`, and `toJson` from a 5-line spec. `defunion` generates a sealed class hierarchy from a compact variant list. Neither `freezed` nor any annotation-based tool creates the class from scratch — they annotate one you already wrote.

Demonstrates: `defrecord`, `defunion`, `unless`, `assertThat`

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

**What to notice:** Your OpenAPI spec is the source of truth. The Dart types don't exist until the macro runs — there's nothing to annotate, nothing to scaffold. Add this step to CI and your Dart types track your spec automatically.

Demonstrates: `defFromOpenApi`

```bash
dart run bin/dmacro.dart compile example/openapi_demo/models.dmacro
```

---

## [`schema_demo/`](schema_demo/)

Generate a single class from a JSON Schema file.

**What to notice:** One line of macro source generates ~40 lines of production-quality Dart — constructor, value equality, serialization, `copyWith`. The output imports nothing and has no runtime dependencies.

Demonstrates: `defFromJsonSchema`

```bash
dart run bin/dmacro.dart compile example/schema_demo/models.dmacro
```

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
