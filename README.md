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

  Payment copyWith({double? amount, String? currency, ...}) => ...;

  @override bool operator ==(Object other) => ...;
  @override int get hashCode => ...;
  @override String toString() => 'Payment(amount: $amount, ...)';
}
```

No annotations. No generated `*.g.dart` files to commit. No `build_runner watch` process to keep running. The schema is the single source of truth — update it, recompile, done.

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
| `defrecord Name { ... }` | Immutable class: fields, constructor, `copyWith`, `==`, `hashCode`, `toString` | Functions can't generate class declarations |
| `defunion Name { ... }` | Sealed class hierarchy | Same |
| `defFromJsonSchema("path")` | `defrecord` from a JSON Schema file | Functions run at runtime; I/O at build time requires a macro |
| `defFromOpenApi("path", "Name")` | `defrecord` from an OpenAPI `components/schemas` entry | Same |
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

### VS Code

Install the `dmacro` extension from `vscode-ext/` — it compiles on save and shows errors as squiggles.

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
  dmacro.dart             CLI: compile / watch / repl / --check
  dart_macros.dart        Annotation-based preprocessor CLI
lib/src/
  core.dart               Node type, expand(), emit()
  async_expand.dart       Async macro expander (enables compile-time I/O)
  schema_macros.dart      defFromJsonSchema, defFromOpenApi, defAllFromJsonSchema
  builtins.dart           unless, when, swap!, assertThat, withRetry, defrecord, defunion
  dart_parser.dart        .dmacro parser
  tokenizer.dart          .dmacro tokenizer
  reader.dart             S-expression reader
example/
  ecommerce/              Domain models: Product, Order, Cart, OrderStatus
  api_from_schema/        Types from a directory of JSON Schemas
  openapi_demo/           Types from an OpenAPI spec
  schema_demo/            Single defFromJsonSchema walkthrough
  payment.dmacro          Core syntax reference
  payment.sexp            S-expression syntax reference
vscode-ext/               VS Code extension source
```
