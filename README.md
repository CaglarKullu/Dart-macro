# dmacro

Compile-time macros for Dart. Write a short declaration — get a complete, typed, immutable class back. Read your API spec at build time and generate Dart types automatically. No `build_runner`, no annotations, no extra packages.

> The Dart team [cancelled language-level macros in January 2025](https://dart.dev/language/macros).  
> dmacro ships today, built as a plain preprocessor — no compiler integration required.

---

## The 30-second pitch

You have an API. It has a schema. You want Dart types.

```
defFromJsonSchema("schemas/payment.json");
```

That one line reads your JSON Schema **at compile time** and generates:

```dart
class Payment {
  final double amount;
  final String currency;
  final String? reference;
  final List<String>? tags;

  const Payment({required this.amount, required this.currency, ...});

  Payment copyWith({...}) => ...;              // clears nullable fields too

  factory Payment.fromJson(Map<String, dynamic> json) => ...;   // ← real (de)serialization
  Map<String, dynamic> toJson() => ...;

  @override bool operator ==(Object other) => ...;   // ← deep equality on List/Set/Map
  @override int get hashCode => ...;
  @override String toString() => 'Payment(amount: $amount, ...)';
}
```

A complete, **JSON-serializable, value-equal** model. No annotations. No generated `*.g.dart` files to commit. No `build_runner watch` process. No `package:json_serializable` or `package:freezed` — the output imports nothing. The schema is the single source of truth — update it, recompile, done.

---

## Quick start

```bash
# 1. Clone
git clone https://github.com/caglarkullu/dart-macro && cd dart-macro

# 2. Install deps
dart pub get

# 3. Compile an example
dart run bin/dmacro.dart compile example/ecommerce/models.dmacro

# 4. Or try the REPL
dart run bin/dmacro.dart repl
```

No configuration files. No global installs. Works on any machine with the Dart SDK.

---

## Real-world use cases

### 1. Generate types from your OpenAPI spec

You already have an OpenAPI spec for your backend. Stop maintaining Dart types by hand.

```dart
// models.dmacro
defFromOpenApi("api/openapi.json", "User");
defFromOpenApi("api/openapi.json", "Order");
defFromOpenApi("api/openapi.json", "Product");
```

```bash
dart run bin/dmacro.dart compile models.dmacro
```

Each macro call reads `openapi.json`, finds the named schema under `components/schemas`, maps the fields to Dart types, and generates a complete immutable class. Add this to your CI pipeline — if the spec changes, the Dart types change automatically.

→ See [`example/openapi_demo/`](example/openapi_demo/)

---

### 2. Generate an entire directory of types at once

One line processes every JSON Schema file in a folder:

```dart
// models.dmacro
defAllFromJsonSchema("schemas/");
```

```
schemas/
  user.json      → class User { ... }
  address.json   → class Address { ... }
  product.json   → class Product { ... }
```

→ See [`example/api_from_schema/`](example/api_from_schema/)

---

### 3. Domain models — one line replaces 60 lines

**Before** (hand-written Dart — every project has dozens of these):

```dart
class Product {
  final String id;
  final String name;
  final double price;
  final int stock;
  final String? imageUrl;

  const Product({
    required this.id,
    required this.name,
    required this.price,
    required this.stock,
    this.imageUrl,
  });

  Product copyWith({
    String? id,
    String? name,
    double? price,
    int? stock,
    String? imageUrl,
  }) =>
      Product(
        id: id ?? this.id,
        name: name ?? this.name,
        price: price ?? this.price,
        stock: stock ?? this.stock,
        imageUrl: imageUrl ?? this.imageUrl,
      );

  @override
  bool operator ==(Object other) =>
      other is Product &&
      other.id == id &&
      other.name == name &&
      other.price == price &&
      other.stock == stock &&
      other.imageUrl == imageUrl;

  @override
  int get hashCode => Object.hash(id, name, price, stock, imageUrl);

  @override
  String toString() =>
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

Same output. One fifth the lines. No `freezed`, no code generation packages.

→ See [`example/ecommerce/models.dmacro`](example/ecommerce/models.dmacro)

---

### 4. State machines — sealed class hierarchy from a compact spec

```dart
defunion OrderStatus {
  Pending    {}
  Processing { String trackingId; }
  Shipped    { String trackingId; String estimatedDelivery; }
  Delivered  {}
  Cancelled  { String reason; }
}
```

Generates a sealed abstract class `OrderStatus` with five concrete subtypes,
each a full immutable record with `copyWith`, `==`, `hashCode`, and `toString`.

Use with pattern matching:

```dart
switch (order.status) {
  case Shipped(:final trackingId): print('Tracking: $trackingId');
  case Cancelled(:final reason):   print('Cancelled: $reason');
  default: ...
}
```

---

### 5. Validation without boilerplate

```dart
// These are macros — they expand to plain Dart, zero runtime overhead.

bool createOrder(String customerId, double amount, int itemCount) {
  unless (customerId.isNotEmpty) {
    throw Exception("Customer ID required");
  }
  unless (amount > 0) {
    throw Exception("Amount must be positive");
  }
  assertThat(itemCount > 0);   // error message: "Expected: (itemCount > 0)"
  assertThat(amount < 50000);  // error message: "Expected: (amount < 50000)"
  return true;
}
```

`unless` is the inverse of `if`. `assertThat` embeds the **source expression** in the error — a regular function can't do this because it only receives the boolean result, not the code that produced it.

---

### 6. Retry logic with injected state

```dart
void syncWithServer(String endpoint, Payload payload) {
  withRetry(3, postJson(endpoint, payload));
}
```

Expands to a `for` loop with a `try/catch` and an `_attempt` counter injected directly into scope — something a higher-order function can never do, because functions receive *values*, not variable names.

---

### 7. User-defined macros in `.dmacro` files

You can define your own macros directly in `.dmacro` source — no Dart code required:

```dart
// Define once
defmacro log(msg) {
  print("[LOG] " + msg);
}

defmacro guard(cond, err) {
  if (!cond) {
    throw Exception(err);
  }
}

// Use anywhere below the definition
bool createUser(String email, int age) {
  guard(email.contains("@"), "Invalid email");
  guard(age >= 18, "Must be 18 or older");
  log("Creating user: " + email);
  return true;
}
```

Each `defmacro` registers a template macro: call-site arguments are substituted for parameter names throughout the body. Definitions must appear before the first call, just like `defenum`.

---

### 8. OpenAPI `oneOf` → sealed class hierarchy

OpenAPI specs that use `oneOf` for polymorphic types are automatically mapped to a Dart sealed class:

```json
{
  "title": "Shape",
  "oneOf": [
    { "title": "Circle",    "type": "object", "required": ["radius"],       "properties": { "radius": { "type": "number" } } },
    { "title": "Rectangle", "type": "object", "required": ["width","height"],"properties": { "width":  { "type": "number" }, "height": { "type": "number" } } }
  ]
}
```

```dart
defFromJsonSchema("schemas/shape.json");
```

Generates:

```dart
sealed class Shape { const Shape(); }
class Circle    extends Shape { final double radius; ... }
class Rectangle extends Shape { final double width; final double height; ... }
```

---

### 9. YAML OpenAPI specs

`defFromOpenApi` now accepts `.yaml` and `.yml` files in addition to `.json` — no external dependencies:

```dart
defFromOpenApi("api/openapi.yaml", "User");
defFromOpenApi("api/openapi.yaml", "Order");
```

The built-in YAML parser handles block and flow mappings/sequences, quoted scalars, block scalars (`|`/`>`), and `#` comments — the full subset needed for real-world OpenAPI specs.

---

## Syntax

dmacro files look like Dart. The `.dmacro` extension signals the preprocessor.

```dart
// models.dmacro

defrecord User {
  String  id;
  String  email;
  String? displayName;
  bool    isVerified;
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

Compile it:

```bash
dart run bin/dmacro.dart compile models.dmacro
# writes models.dart
```

There is also an S-expression syntax (`.sexp`) for the full Lisp experience — see [`example/payment.sexp`](example/payment.sexp).

---

## Built-in macros

| Macro | What it generates | Why a function can't do this |
|---|---|---|
| `defrecord Name { ... }` | Immutable class: fields, constructor, `copyWith`, deep `==`/`hashCode`, `toString`, **`fromJson`/`toJson`** | Functions can't generate class declarations |
| `defunion Name { ... }` | Sealed class hierarchy | Same |
| `defmacro name(params) { ... }` | User-defined template macro, registered for use in the same file | Functions run at call time with values; macros run at expand time with code |
| `defFromJsonSchema("path")` | `defrecord` from a JSON Schema file; `$defs`/`definitions` blocks and `oneOf` are supported | Functions run at runtime; I/O at build time requires a macro |
| `defFromOpenApi("path", "Name")` | `defrecord` (or `defunion` for `oneOf`) from an OpenAPI `components/schemas` entry; accepts `.json`, `.yaml`, or `.yml` | Same |
| `defAllFromJsonSchema("dir/")` | One `defrecord` per `.json` file in a directory | Same |
| `unless (cond) { ... }` | `if (!(cond)) { ... }` | Convenience only — could be a function but this reads better |
| `when (cond) { ... }` | `if (cond) { ... }` | Same |
| `assertThat(expr)` | `if (!expr) throw AssertionError("Expected: <source>")` | Functions receive `false`, not the expression that produced it |
| `swap!(a, b)` | `final _tmp = a; a = b; b = _tmp;` | Functions receive values, not variable names |
| `withRetry(n, expr)` | `for` loop with `try/catch` and an `_attempt` counter | The counter must live in the caller's scope |

---

## Workflow

```
you write           dmacro compiles           you commit
──────────          ──────────────            ──────────
models.dmacro  →    models.dart          →    models.dart
                    (full Dart class)          (not models.dmacro)
```

The `.dart` file is the output — your Flutter/Dart app imports it as normal. The `.dmacro` file is the source. Commit both.

### Watch mode (recompiles on every save)

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
# prints each macro expansion step — useful for debugging generated code
```

### VS Code extension

The `vscode-ext/` directory contains a VS Code extension that gives you:

- Syntax highlighting for `.dmacro` and `.sexp` files
- Compile on save (runs `dmacro compile` automatically)
- Errors shown as red squiggles in the editor
- Commands: **dmacro: Compile File** and **dmacro: Compile Workspace**

**Install steps:**

1. Install [Node.js](https://nodejs.org) if you don't have it.

2. Build the `.vsix` package:

   ```bash
   cd vscode-ext
   npm install
   npm run package        # produces dmacro-0.1.0.vsix
   ```

3. Install in VS Code:
   - Open the Extensions panel (`Ctrl+Shift+X` / `Cmd+Shift+X`)
   - Click the `···` menu at the top-right of the panel
   - Choose **Install from VSIX…**
   - Select `vscode-ext/dmacro-0.1.0.vsix`

4. Reload VS Code when prompted.

**Settings** (VS Code `settings.json`):

| Setting | Default | Description |
|---|---|---|
| `dmacro.cliPath` | `""` | Absolute path to the `dmacro` CLI binary. Leave empty to use `dart run bin/dmacro.dart` |
| `dmacro.formatOnCompile` | `true` | Run `dart format` on the generated `.dart` file after each compile |
| `dmacro.analyzeOnCompile` | `true` | Run `dart analyze` after compile and surface errors as VS Code diagnostics |
| `dmacro.hotReloadOnCompile` | `true` | Trigger Flutter hot reload 500 ms after a successful compile (requires an active debug session) |

**Try it in development** (no build needed):

```bash
cd vscode-ext && npm install
# open vscode-ext/ in VS Code, then press F5 — launches an Extension Development Host
```

---

## How it works

```
source (.dmacro)
    ↓  tokenizer + parser
List<Node>            ← code is data (nested lists, same as Lisp)
    ↓  async expander    ← macros run here; I/O is allowed
List<Node>            ← fully expanded, no macros remain
    ↓  emitter
Dart source (.dart)
```

A `Node` is `dynamic` — either an atom (`String`, `int`, `double`, `bool`, `null`) or a `List<Node>`. A macro is a Dart function `(List<Node>) → Node`. This mirrors Lisp exactly.

The **async expander** is why `defFromJsonSchema` works: macros run at compile time and can do file I/O. No other Dart code-generation tool allows this without a build daemon.

---

## Comparison

| | **dmacro** | freezed + build_runner | macro_kit | Official Dart macros |
|---|---|---|---|---|
| Ships today | ✅ | ✅ | ✅ | ❌ (cancelled Jan 2025) |
| Zero dependencies | ✅ | ❌ | ❌ | — |
| No build daemon | ✅ | ❌ (build_runner watch) | ❌ (WebSocket daemon) | — |
| Generate entire class | ✅ | ✅ | ❌ (appends only) | ✅ |
| `fromJson` / `toJson` | ✅ (built in) | ➖ (needs `json_serializable`) | ❌ | ✅ |
| Deep value equality (List/Set/Map) | ✅ | ✅ | ❌ | ✅ |
| `copyWith` can clear nullable fields | ✅ | ✅ | ❌ | ✅ |
| Read external files at build time | ✅ | ❌ | ❌ | ❌ |
| Expression-level transforms | ✅ | ❌ | ❌ | ✅ |
| Inject variables into caller scope | ✅ | ❌ | ❌ | ❌ |
| Dart-like syntax | ✅ (.dmacro) | ✅ | ✅ | ✅ |
| Works in Flutter projects | ✅ | ✅ | ✅ | — |
| Handles nullability | ✅ | ✅ | ✅ | ✅ |

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
  dart_parser.dart        .dmacro parser (including defmacro declarations)
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
```
