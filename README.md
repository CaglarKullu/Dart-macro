# dmacro

**dmacro is a preprocessor for Dart.** You run `dmacro compile`, it reads `.dmacro` source files, expands macros, and writes plain `.dart` files. The Dart compiler then compiles those `.dart` files as normal — it never sees `.dmacro` files and never runs any macro code.

It is a **boilerplate reducer and code generator**, not a runtime system. Generated types are static Dart — they compile into your app binary and do not adapt to changes at runtime. If your API schema changes, you update the spec, re-run dmacro, and redeploy. Same cycle as any code generator.

The practical value: less ceremony than `build_runner` + `freezed` for common patterns, and the ability to generate types directly from an OpenAPI or JSON Schema file without writing an annotated class first.

---

## Table of contents

1. [Quick start](#quick-start)
2. [What you get](#what-you-get)
3. [Syntax reference](#syntax-reference)
4. [Built-in macros](#built-in-macros)
5. [Workflow](#workflow)
   - [Installation](#installation)
   - [Flutter integration](#flutter-project-integration)
   - [Watch mode](#watch-mode)
   - [CI staleness check](#ci-staleness-check)
   - [Trace expansions](#trace-macro-expansions)
   - [Field-level error attribution](#field-level-error-attribution)
   - [VS Code extension](#vs-code-extension)
6. [How it compares to build_runner](#how-it-compares-to-build_runner)
7. [How it works](#how-it-works)
8. [Project structure](#project-structure)

---

## Quick start

```bash
git clone https://github.com/caglarkullu/dart-macro && cd dart-macro
dart pub get
dart run bin/dmacro.dart compile example/ecommerce/models.dmacro
dart run bin/dmacro.dart repl    # interactive
```

No configuration files. No global installs. Any machine with the Dart SDK.

---

## What you get

### Replace 60 lines of boilerplate with 7

**Before** (hand-written Dart — every project has dozens of these):

```dart
class Product {
  final String id;
  final String name;
  final double price;
  final int stock;
  final String? imageUrl;

  const Product({
    required this.id, required this.name, required this.price,
    required this.stock, this.imageUrl,
  });

  Product copyWith({String? id, String? name, double? price,
      int? stock, String? imageUrl}) =>
      Product(id: id ?? this.id, name: name ?? this.name,
          price: price ?? this.price, stock: stock ?? this.stock,
          imageUrl: imageUrl ?? this.imageUrl);

  @override bool operator ==(Object other) => other is Product &&
      other.id == id && other.name == name && other.price == price &&
      other.stock == stock && other.imageUrl == imageUrl;

  @override int get hashCode => Object.hash(id, name, price, stock, imageUrl);

  @override String toString() =>
      'Product(id: $id, name: $name, price: $price, stock: $stock, imageUrl: $imageUrl)';
}
```

**After** (`.dmacro` file):

```dart
defrecord Product {
  String  id;
  String  name;
  double  price;
  int     stock;
  String? imageUrl;
}
```

Same output. One fifth the lines. No `freezed`. No annotation class to write first.

→ See [`example/ecommerce/models.dmacro`](example/ecommerce/models.dmacro)

---

### Generate types from a schema file — no annotation class needed

With `build_runner` + `json_serializable`, you write a Dart class, add annotations, then run the generator to fill in `fromJson`/`toJson`. The class must exist first.

With dmacro, the spec is the source — no Dart class required upfront:

```dart
// models.dmacro — read your spec at generation time, generate the class
defFromJsonSchema("schemas/payment.json");
defFromOpenApi("api/openapi.yaml", "User");
defAllFromJsonSchema("schemas/");   // one class per .json file in the folder
```

When you run `dmacro compile`, it reads the spec and writes a complete `.dart` class. The generated types are **static** — they compile into your app binary. If the API schema changes after deployment, the app uses the old types, exactly like any code generator. You update the spec, re-run dmacro, and redeploy.

The advantage over build_runner here is workflow: no annotation boilerplate, no class to scaffold first. The spec is the single source of truth during development.

→ See [`example/openapi_demo/`](example/openapi_demo/) and [`example/api_from_schema/`](example/api_from_schema/)

---

### Sealed class hierarchies from a compact spec

```dart
defunion OrderStatus {
  Pending    {}
  Processing { String trackingId; }
  Shipped    { String trackingId; String estimatedDelivery; }
  Delivered  {}
  Cancelled  { String reason; }
}
```

Generates a sealed abstract class with five concrete subtypes, each a full immutable record with `copyWith`, `==`, `hashCode`, and `toString`. Works with Dart pattern matching out of the box.

---

### Retry logic that preserves control flow

```dart
withRetry(3, postJson(endpoint, payload));
```

Expands to an inline `for` loop with `try/catch`. Because the body is inlined rather than wrapped in a callback, `return` exits the outer function and `break` exits an outer loop. A higher-order `withRetry(n, () { ... })` wraps the body in a closure — `return` and `break` no longer reach the outer scope. The macro avoids that problem by generating the loop inline.

---

### User-defined macros, no build tooling required

```dart
defmacro guard(cond, err) {
  unless (cond) { throw Exception(err); }
}

bool createUser(String email, int age) {
  guard(email.contains("@"), "Invalid email");
  guard(age >= 18, "Must be 18+");
}
```

Define new macros directly in the `.dmacro` file you're working on. No separate Dart package, no generator registration, no build step. Macros compose: `guard` calls `unless`, which calls `if`.

---

## Syntax reference

dmacro files look like Dart. The `.dmacro` extension signals the preprocessor.

```dart
// models.dmacro

defenum Status { active, inactive, suspended }

defrecord User {
  String   id;
  String   email;
  String?  displayName;
  Status   status;
}

// snake_case JSON keys (orderId → "order_id"):
defrecord(snake_case) Order {
  String id;
  String userId;
  double totalAmount;
}

// @json_key overrides the JSON key for a single field:
defrecord ExternalEvent {
  @json_key("evt_ts")
  int timestamp;
  String eventName;
}

defunion AuthState {
  Unauthenticated {}
  Authenticating  {}
  Authenticated   { User user; }
  Error           { String message; }
}

bool validateEmail(String email) {
  unless (email.contains("@")) {
    throw Exception("Invalid email: $email");
  }
  return true;
}
```

Compile:

```bash
dart run bin/dmacro.dart compile models.dmacro
# writes models.dart
```

There is also an S-expression syntax (`.sexp`) for the full Lisp experience — see [`example/payment.sexp`](example/payment.sexp).

---

## Built-in macros

| Macro | What it generates |
|---|---|
| `defrecord Name { ... }` | Immutable class with fields, constructor, `copyWith`, deep `==`/`hashCode`, `toString`, `fromJson`, `toJson` (camelCase keys) |
| `defrecord(snake_case) Name { ... }` | Same but JSON keys are snake_case (`orderId` → `"order_id"`) |
| `@json_key("name") Type field;` | Overrides the JSON key for one field — wins over camelCase and snake_case |
| `defenum Name { v1, v2 }` | Dart enum with `fromJson`/`toJson` via `.byName`/`.name` |
| `defunion Name { ... }` | Sealed class hierarchy |
| `defmacro name(params) { ... }` | User-defined template macro, usable anywhere below its definition |
| `defFromJsonSchema("path")` | `defrecord` from a JSON Schema file; supports `$defs`, `definitions`, `oneOf` |
| `defFromOpenApi("path", "Name")` | `defrecord` or `defunion` from an OpenAPI `components/schemas` entry; `.json`, `.yaml`, `.yml` |
| `defAllFromJsonSchema("dir/")` | One `defrecord` per `.json` file in a directory |
| `unless (cond) { ... }` | `if (!(cond)) { ... }` |
| `when (cond) { ... }` | `if (cond) { ... }` |
| `assertThat(expr)` | `if (!expr) throw AssertionError("Expected: <source-text>")` — message includes the source expression |
| `swap!(a, b)` | `final _tmp = a; a = b; b = _tmp;` |
| `withRetry(n, expr)` | Inline `for` loop with `try/catch` — `return`/`break` work normally because the body is inlined, not a callback |

---

## Workflow

```
you write           dmacro compiles           you commit
──────────          ──────────────            ──────────
models.dmacro  →    models.dart          →    models.dart
                    (full Dart class)          (not models.dmacro)
```

The `.dart` file is the output — your Flutter/Dart app imports it normally. Commit both the `.dmacro` source and the generated `.dart`.

### Installation

```bash
# From source (pub.dev publish is tracked in the backlog):
git clone https://github.com/caglarkullu/dart-macro
cd dart-macro && dart pub get
dart run bin/dmacro.dart compile <file>

# Or pin a git dependency in pubspec.yaml:
# dmacro:
#   git: https://github.com/caglarkullu/dart-macro
```

> **Note:** dmacro is not yet published to pub.dev. Install from source until then.

### Flutter project integration

Run `dmacro watch` alongside `flutter run`. The VS Code extension does this automatically. Manually:

```bash
# Terminal 1
flutter run

# Terminal 2
dart run bin/dmacro.dart watch lib/models/
```

Save a `.dmacro` file → dmacro regenerates the `.dart` → Flutter hot-reloads.

Generated files are plain Dart and work with `Provider`, `Riverpod`, `Bloc`, and any other state management.

**Merge conflicts in generated files:** resolve the conflict in the `.dmacro` source, then `dart run bin/dmacro.dart compile lib/models/` to regenerate.

### Watch mode

```bash
dart run bin/dmacro.dart watch lib/
```

### CI staleness check

```bash
dart run bin/dmacro.dart compile lib/ --check
# exits non-zero if any .dart is out of date
```

### Trace macro expansions

```bash
dart run bin/dmacro.dart trace models.dmacro
# prints each expansion step — useful for debugging
```

### Field-level error attribution

By default, `dart analyze` errors map to the `defrecord` declaration line. For per-field precision:

```bash
dart run bin/dmacro.dart compile models.dmacro --field-origins
# embeds // @dmacro-origin: models.dmacro:5 before each generated field
```

### VS Code extension

The `vscode-ext/` directory gives you:

- Syntax highlighting for `.dmacro` and `.sexp` files
- Compile on save
- Errors shown as red squiggles
- Commands: **dmacro: Compile File** and **dmacro: Compile Workspace**

**Install:**

```bash
cd vscode-ext && npm install && npm run package   # produces dmacro-0.1.0.vsix
```

Then in VS Code: Extensions panel → `···` → **Install from VSIX…** → select `dmacro-0.1.0.vsix`.

**Settings:**

| Setting | Default | Description |
|---|---|---|
| `dmacro.cliPath` | `""` | Path to the CLI. Empty = use `dart run bin/dmacro.dart` |
| `dmacro.formatOnCompile` | `true` | Run `dart format` after each compile |
| `dmacro.analyzeOnCompile` | `true` | Run `dart analyze` and surface errors as diagnostics |
| `dmacro.hotReloadOnCompile` | `true` | Trigger Flutter hot reload 500 ms after compile |

---

## How it compares to build_runner

Both dmacro and `build_runner` are code generators: they run on your development machine, produce `.dart` files, and those files compile into your app. Neither affects runtime behaviour.

The differences are in ceremony and workflow:

| | `build_runner` + `freezed` | dmacro |
|---|---|---|
| Write an annotated class first | Yes — class must exist | No — spec is the source |
| Run a background daemon | Yes (`build_runner watch`) | No |
| Extra packages required | Yes (`freezed`, `json_serializable`, etc.) | No |
| Generate entire class from scratch | Yes (freezed does this too) | Yes |
| Generate from external spec file | No — requires an annotated class | Yes — `defFromJsonSchema`, `defFromOpenApi` |
| Fetch schema from a URL | No | Yes (at generation time, on your machine) |
| User-defined transforms in-source | No — needs a new generator package | Yes — `defmacro` in the same file |
| `return`/`break` in retry bodies | No — callback wraps in closure | Yes — `withRetry` inlines the body |

**On schema fetching:** `defFromOpenApi("https://api.example.com/spec")` fetches the spec when you run `dmacro compile` on your machine. The generated class is static Dart — it compiles into the binary. If the API schema changes after you ship, the app uses the old types. You fetch again, regenerate, and redeploy. The advantage over build_runner is that you skip the manual annotation step, not that the app adapts at runtime.

---

## How it works

dmacro is a Lisp-style macro system. Code is represented as data (nested lists), macros are plain Dart functions that transform that data, and the emitter serialises the result to Dart source.

```
source (.dmacro)
    ↓  tokenizer + parser
List<Node>            ← code as data (nested lists)
    ↓  async expander    ← macros run here; await is allowed
List<Node>            ← fully expanded
    ↓  emitter
Dart source (.dart)
```

`Node` is `dynamic` — an atom (`String`, `int`, `double`, `bool`, `null`) or a `List<Node>`. A macro is `(List<Node>) → Node`. The expression `(if (> x 0) "pos")` is literally the list `['if', ['>', 'x', 0], '"pos"']` — code and data share the same representation.

The expander allows `await`, which is why `defFromJsonSchema` can read files and URLs during the generation step. `build_runner` builders can read declared asset inputs but cannot make arbitrary network calls.

---

## Project structure

```
bin/
  dmacro.dart             CLI: compile / watch / repl / trace / --check
lib/src/
  core.dart               Node type, expand(), emit()
  async_expand.dart       Async macro expander (I/O during generation)
  schema_macros.dart      defFromJsonSchema, defFromOpenApi, defAllFromJsonSchema
  yaml_parser.dart        Built-in YAML parser (no external deps)
  builtins.dart           unless, when, swap!, assertThat, withRetry, defrecord, defunion, defmacro
  dart_parser.dart        .dmacro parser
  tokenizer.dart          .dmacro tokenizer
  reader.dart             S-expression reader
example/
  ecommerce/              Domain models: Product, Order, Cart, OrderStatus
  api_from_schema/        Types from a directory of JSON Schemas
  openapi_demo/           Types from an OpenAPI spec (JSON + YAML)
  schema_demo/            Single defFromJsonSchema walkthrough
  payment.dmacro          Core syntax reference
  payment.sexp            S-expression syntax reference
vscode-ext/               VS Code extension source
doc/                      Architecture notes, validated logic, roadmap
```
