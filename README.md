# dmacro

Compile-time macros for Dart. Write a short spec — get a complete, typed, immutable class back. Read your API schema at build time and generate Dart types automatically. No `build_runner`, no annotations, no extra packages.

> The Dart team [cancelled language-level macros in January 2025](https://dart.dev/language/macros).  
> dmacro ships today, built as a plain preprocessor — no compiler integration required.

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
6. [Why macros?](#why-macros)
7. [How it works](#how-it-works)
8. [Comparison](#comparison)
9. [Project structure](#project-structure)

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

### Generate types from a schema — one line

```dart
// models.dmacro
defFromJsonSchema("schemas/payment.json");
defFromOpenApi("api/openapi.yaml", "User");
defAllFromJsonSchema("schemas/");   // one class per .json file in the folder
```

Each line reads the spec **at compile time** and generates a complete immutable class with `fromJson`/`toJson`, `copyWith`, deep `==`/`hashCode`, and `toString`. Update the spec, recompile — done. No annotations. No `.g.dart` files.

→ See [`example/openapi_demo/`](example/openapi_demo/) and [`example/api_from_schema/`](example/api_from_schema/)

---

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

Same output. One fifth the lines. No `freezed`. No code generation packages.

→ See [`example/ecommerce/models.dmacro`](example/ecommerce/models.dmacro)

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

### Error messages that contain the source expression

```dart
assertThat(amount > 0);
// Throws: AssertionError("Expected: (amount > 0), got false")
//                                  ↑ actual source — not just "false"
```

A function only receives `false`. The macro receives the AST `['>', 'amount', 0]` and embeds the source expression in the error automatically.

---

### Retry logic that preserves control flow

```dart
withRetry(3, postJson(endpoint, payload));
```

Expands to an inline `for` loop with `try/catch`. Because the body is inlined (not wrapped in a callback), `return` exits the outer function and `break` exits an outer loop — exactly as you'd expect. A higher-order `withRetry(n, () { ... })` breaks both.

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

Define new macros directly in the `.dmacro` file you're working on. No separate Dart code, no package, no build step. Macros compose: `guard` calls `unless`, which calls `if`.

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

// @json_key overrides the JSON key for a single field,
// taking priority over both camelCase and snake_case defaults:
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

| Macro | What it generates | Why a function can't do this |
|---|---|---|
| `defrecord Name { ... }` | Immutable class with fields, constructor, `copyWith`, deep `==`/`hashCode`, `toString`, `fromJson`, `toJson` (camelCase keys) | Functions can't generate class declarations |
| `defrecord(snake_case) Name { ... }` | Same but JSON keys are snake_case (`orderId` → `"order_id"`) | Covers APIs that use snake_case while Dart uses camelCase |
| `@json_key("name") Type field;` | Overrides the JSON key for one field — wins over camelCase and snake_case | Field annotation inside `defrecord` or `defrecord(snake_case)` |
| `defenum Name { v1, v2 }` | Dart enum with `fromJson`/`toJson` via `.byName`/`.name` | — |
| `defunion Name { ... }` | Sealed class hierarchy | Same as defrecord |
| `defmacro name(params) { ... }` | User-defined template macro | Functions run at call time with values; macros run at expand time with code |
| `defFromJsonSchema("path")` | `defrecord` from a JSON Schema file; supports `$defs`, `definitions`, `oneOf` | Requires compile-time file I/O |
| `defFromOpenApi("path", "Name")` | `defrecord` or `defunion` from an OpenAPI `components/schemas` entry; `.json`, `.yaml`, `.yml` | Same |
| `defAllFromJsonSchema("dir/")` | One `defrecord` per `.json` file in a directory | Same |
| `unless (cond) { ... }` | `if (!(cond)) { ... }` | — |
| `when (cond) { ... }` | `if (cond) { ... }` | — |
| `assertThat(expr)` | `if (!expr) throw AssertionError("Expected: <source>")` | Functions receive `false`, not the expression that produced it |
| `swap!(a, b)` | `final _tmp = a; a = b; b = _tmp;` | Functions receive values, not variable names |
| `withRetry(n, expr)` | Inline `for` loop with `try/catch` | Inlined body — `return`/`break` work normally; a callback can't do this |

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

Generated files are plain Dart and work with `Provider`, `Riverpod`, `Bloc`, and any other state management — they're just immutable value classes.

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

## Why macros?

### Macros vs. code generation

If you've used `build_runner` or `freezed`, you've used **code generation** — a separate process that reads your files and writes new ones. Useful, but limited: it can only see what's already written.

A **macro** is different in one key way: it runs during the processing of the file itself. It doesn't just read the source — it receives the unevaluated code as a data structure and transforms it before the compiler sees anything.

```dart
// A function receives the result of evaluating the expression:
assert_that(amount > 0);   // receives `false` — no idea what was compared

// A macro receives the unevaluated expression as a data structure:
assertThat(amount > 0);    // receives ['>', 'amount', 0]
                           // → can generate: throw AssertionError("Expected: amount > 0")
```

The three things macros can do that code generation cannot:
1. **Inspect code structure** — not just values, but operators, operands, variable names.
2. **Generate declarations** — `json_serializable` adds methods to a class you wrote; `defrecord` creates the class from nothing.
3. **I/O at expand time** — `defFromJsonSchema` reads your API spec during compilation. Functions run at runtime; code generators don't run inside the compilation pass at all.

### Why Lisp macros, not C macros

C macros (`#define`) do text substitution — they never see the parsed structure. They break on commas in arguments, have no hygiene (name collisions are your problem), and can't loop or branch.

dmacro is a **Lisp macro system** for Dart. In Lisp, code and data share the same representation: nested lists. The expression `(if (> x 0) "positive")` *is* the list `['if', ['>', 'x', 0], '"positive"']`. A macro is a plain Dart function that receives that list and returns a transformed list.

```
source text  →  List<Node>  →  macro(List<Node>) → List<Node>  →  Dart source
                (code as data)    (transformation)
```

`Node` is `dynamic` — an atom (`String`, `int`, `double`, `bool`, `null`) or a `List<Node>`. A macro is `(List<Node>) → Node`. That's the entire model.

| | C `#define` | dmacro (Lisp-style) |
|---|---|---|
| Operates on | Raw tokens | Parsed AST |
| Inspect argument structure | No | Yes |
| Hygienic | No | Yes — `gensym` prevents name collisions |
| Loop / branch / recurse | No | Yes — it's Dart code |
| Compile-time I/O | No | Yes — `async` macros allowed |

---

## How it works

```
source (.dmacro)
    ↓  tokenizer + parser
List<Node>            ← code is data (nested lists)
    ↓  async expander    ← macros run here; await is allowed
List<Node>            ← fully expanded, no macros remain
    ↓  emitter
Dart source (.dart)
```

The **async expander** is why `defFromJsonSchema` works: macros can `await` file I/O, HTTP requests, or anything else at expansion time. The official Dart macro system [could not support this](https://dart.dev/language/macros) — async execution inside an incremental compiler makes millisecond hot reloads intractable, so the two couldn't be reconciled.

dmacro is not inside the compiler. It transforms `.dmacro` → `.dart` as a separate step, then steps aside. The compiler sees only plain `.dart` files. This costs one extra step (generated files are committed, just like `build_runner` output) but buys the full capability: arbitrary code — including I/O — at expansion time.

---

## Comparison

| | **dmacro** | freezed + build_runner | macro_kit | Official Dart macros |
|---|---|---|---|---|
| Ships today | ✅ | ✅ | ✅ | ❌ (cancelled Jan 2025) |
| Zero dependencies | ✅ | ❌ | ❌ | — |
| No build daemon | ✅ | ❌ (build_runner watch) | ❌ (WebSocket daemon) | — |
| Generate entire class | ✅ | ✅ | ❌ (appends only) | ✅ |
| `fromJson` / `toJson` built in | ✅ | ➖ (needs `json_serializable`) | ❌ | ✅ |
| Deep equality (List/Set/Map) | ✅ | ✅ | ❌ | ✅ |
| `copyWith` clears nullable fields | ✅ | ✅ | ❌ | ✅ |
| Read external files at build time | ✅ | ❌ | ❌ | ❌ |
| Expression-level transforms | ✅ | ❌ | ❌ | ✅ |
| Inject variables into caller scope | ✅ | ❌ | ❌ | ❌ |
| Dart-like syntax | ✅ (.dmacro) | ✅ | ✅ | ✅ |
| Works in Flutter projects | ✅ | ✅ | ✅ | — |

---

## Project structure

```
bin/
  dmacro.dart             CLI: compile / watch / repl / trace / --check
lib/src/
  core.dart               Node type, expand(), emit()
  async_expand.dart       Async macro expander (enables compile-time I/O)
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
