# dmacro

Lisp-style macros for Dart, built on the oldest idea in programming: **code is data**.

Write a short declaration — get a complete, typed, immutable class back. Read your API spec at generation time and generate Dart types automatically. No `build_runner`, no annotations, no extra packages.

> The Dart team [cancelled language-level macros in January 2025](https://dart.dev/language/macros).  
> dmacro ships today, built as a plain preprocessor — no compiler integration required.

---

## The Lisp idea

dmacro is a **Lisp macro system** for Dart. That single sentence is the whole design.

In Lisp, code and data share the same representation: nested lists. The expression `(if (> x 0) "positive")` is literally the list `['if', ['>', 'x', 0], '"positive"']`. A macro is just a Dart function that receives that list and returns a transformed list. No special syntax. No compiler hooks. Just functions operating on data.

```
source text  →  List<Node>  →  macro(List<Node>) → List<Node>  →  Dart source
                 (code as data)    (transformation)
```

`Node` is `dynamic` — an atom (`String`, `int`, `double`, `bool`, `null`) or a `List<Node>`. A macro is `(List<Node>) → Node`. That's the entire model.

This matters because a macro sees the **structure** of the code, not just its value. When `assertThat(amount > 0)` expands, the macro receives the list `['>', 'amount', 0]` — it can read the operator, the operands, everything. A function would only receive `false`.

---

## Why Lisp macros, not C macros

C macros (`#define`) work on raw text: they do token substitution before the compiler sees anything. This sounds powerful but is fundamentally limited:

| | **C-style `#define`** | **Lisp-style (dmacro)** |
|---|---|---|
| Operates on | Raw tokens / text | Parsed AST (nested lists) |
| Can inspect argument structure | No | Yes |
| Hygienic (no name collisions) | No — name collisions are your problem | Yes — `gensym` generates unique names |
| Can loop, branch, recurse | No | Yes — it's just Dart code |
| Can call I/O at expand time | No | Yes — `async` macros allowed |
| Error messages point to source | No | Yes — origin tracking built in |

A C macro for `unless` looks like:

```c
#define unless(cond, body) if (!(cond)) { body }
```

It works for the happy path and silently breaks the moment `body` contains a comma or a variable named `cond`. There's no hygiene, no structure, no safety.

A Lisp macro for `unless` is:

```dart
defmacro('unless', (args) => $if($not(args[0]), args[1]));
```

It receives the actual AST nodes for the condition and body, can inspect them, transform them, wrap them — and `gensym` ensures any generated variable names never collide with the caller's scope.

The real power gap opens with macros that **generate code from external data** — something text substitution cannot do at all. `defFromJsonSchema` reads a JSON file at generation time and emits a complete Dart class. No `#define` can do that. No function can do that. A Lisp macro can.

---

## The wow factor — what only dmacro can do

These are capabilities that exist nowhere else in the Dart ecosystem.

### 1. Generation-time I/O — generate types from live data sources

```dart
// models.dmacro — this line runs when you run `dmacro compile`, not at runtime
defFromJsonSchema("schemas/payment.json");
defFromOpenApi("api/openapi.yaml", "User");
defAllFromJsonSchema("schemas/");
```

dmacro reads the file, parses it, and **generates the Dart class** during the preprocessing step. Your schema is the single source of truth. Update the spec, re-run dmacro, done.

No other Dart tool does this. `build_runner` + `json_serializable` requires annotations on an existing class — you still write the class. `freezed` generates from a class you wrote. The [cancelled official Dart macros](https://dart.dev/language/macros) could not do I/O: async execution inside an incremental compiler breaks hot reload and millisecond rebuilds — the two couldn't be reconciled. dmacro sidesteps the entire problem by being a preprocessor: it has no incrementality obligation, so macros are free to `await` anything.

### 2. Error messages that contain the source expression

```dart
assertThat(amount > 0);
// Throws: AssertionError("Expected: (amount > 0), got false")
//                                  ^^^^^^^^^^^^^^
//                        the actual source code, not just "false"
```

A function receives the **value** `false`. It can never know what expression produced it. The macro receives the **AST** `['>', 'amount', 0]` and can embed a string representation in the error. The expression in the error message is not a convention or a string you type — it's derived automatically from the code you wrote.

### 3. Inject variables into the caller's scope

```dart
withRetry(3, postJson(endpoint, payload));
```

Expands to an inline `for` loop with `try/catch` — the body is not wrapped in a callback. This matters: a `return` inside the body exits the **outer** function, and a `break` exits an outer loop. A higher-order `withRetry(n, () { ... })` wraps your code in a closure, breaking both. The macro inlines the code directly, so normal Dart control flow works exactly as you'd expect.

```dart
swap!(a, b);
```

Expands to three statements using a generated temp variable. A function would need `(a, b) => (b, a)` and a destructuring assignment — and Dart doesn't have that. The macro injects the temp into scope directly.

### 4. Generate entire classes from a one-line spec

```dart
defrecord Product {
  String  id;
  String  name;
  double  price;
  int     stock;
  String? imageUrl;
}
```

Generates a complete, immutable, JSON-serializable value class — constructor, `copyWith`, deep `==`/`hashCode`, `toString`, `fromJson`, `toJson` — ~60 lines of Dart from 7. This is not annotation-driven. There is no existing class to annotate. The macro **creates the class**. `macro_kit` and annotation-based tools can only append to a class you already wrote; dmacro produces the whole thing.

### 5. User-extensible macros, in-source, no build tooling

```dart
// Define once, anywhere in your .dmacro file
defmacro log(msg) {
  print("[LOG] " + msg);
}

defmacro guard(cond, err) {
  unless (cond) {
    throw Exception(err);
  }
}

// Use below the definition
bool createUser(String email, int age) {
  guard(email.contains("@"), "Invalid email");
  guard(age >= 18, "Must be 18+");
  log("Creating user: " + email);
  return true;
}
```

You define new macros in the same file you use them. No Dart code, no package, no separate build step. `defmacro` is itself a macro — the system is self-describing. Macros compose: `guard` uses `unless`, which uses `if`.

---

## The 30-second pitch

You have an API. It has a schema. You want Dart types.

```
defFromJsonSchema("schemas/payment.json");
```

That one line reads your JSON Schema **when you run `dmacro compile`** and generates:

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

A complete, **JSON-serializable, value-equal** model. No annotations. No `*.g.dart` files. No `build_runner watch`. No `package:json_serializable` or `package:freezed` — the output imports nothing. The schema is the single source of truth — update it, recompile, done.

---

## Quick start

### In your own project (the normal way)

```yaml
# pubspec.yaml
dev_dependencies:
  dmacro:
    git: https://github.com/caglarkullu/dart-macro
```

```bash
dart pub get

# Compile a .dmacro file → generates a sibling .dart file
dart run dmacro compile lib/models.dmacro

# Expand inline @@dmacro blocks inside a regular .dart file
dart run dmacro compile lib/models.dart

# Watch mode / CI staleness check / expansion tracing
dart run dmacro watch lib/
dart run dmacro compile lib/ --check
dart run dmacro trace lib/models.dmacro
```

### Write your own macro (the point of the package)

One file in your project gives you the full CLI with your macros loaded:

```dart
// tool/dmacro.dart
import 'package:dmacro/dmacro.dart';

void main(List<String> args) => runDmacro(args, registerMacros: () {
      defAsyncMacro('defwidget', (args) async {
        final name = unquote(args[0] as String);
        return 'class $name extends StatelessWidget { /* ... */ }';
      });
    });
```

```bash
dart run tool/dmacro.dart compile lib/widgets.dmacro
```

Your macros run with the same API the built-ins use — including async I/O at
generation time. See [`doc/WRITING_MACROS.md`](doc/WRITING_MACROS.md) for the
full guide.

### Hacking on dmacro itself

```bash
git clone https://github.com/caglarkullu/dart-macro && cd dart-macro
dart pub get
dart run bin/dmacro.dart compile example/ecommerce/models.dmacro
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

Expands to an inline `for` loop with `try/catch` — the body is not wrapped in a callback. This matters for control flow: a `return` statement inside the body exits the enclosing function, and `break` exits an enclosing loop. A higher-order function wrapping a closure can't do either.

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

**Typed output annotations** — declare what your macro is supposed to produce:

```dart
defmacro(declaration) makeConfig(name) {
  unless(false) { throw Exception("internal"); }
}

defmacro(expression) doubled(x) {
  return x;
}

defmacro(statement) log(msg) {
  print(msg);
}
```

`defmacro(declaration)` validates at call time that the output starts with a class, enum, typedef, or function declaration. If it doesn't — say, a refactor accidentally made the body return a statement instead — you get a clear error pointing to the macro name, not a cryptic Dart parse error downstream. `defmacro(expression)` and `defmacro(statement)` apply analogous checks.

---

### 8. Macros embedded in regular `.dart` files

No `.dmacro` file required. Put macro declarations directly inside an existing `.dart` file using a comment block:

```dart
// lib/models.dart — a regular Dart file

// @@dmacro
defrecord Product {
  String id;
  String name;
  double price;
}
// @@end

void printProduct(Product p) => print(p);
```

Run:

```bash
dart run bin/dmacro.dart compile lib/models.dart
```

The block is expanded in-place. After the first run, the macro source is preserved as comments so the file stays analyzer-clean and subsequent runs are idempotent:

```dart
// @@dmacro
// defrecord Product {
//   String id;
//   String name;
//   double price;
// }
// @@generated
class Product {
  final String id;
  final String name;
  final double price;
  // ... full generated class
}
// @@end
```

Edit the commented-out source and re-run to regenerate. Multiple `// @@dmacro` / `// @@end` blocks per file are supported. Watch mode and directory compile both discover `.dart` files with inline blocks automatically.

---

### 9. Share macros across files with `importMacros`

Factor out common macro definitions into a library file and import them:

```dart
// lib/macros/validators.dmacro
defmacro requireNonEmpty(val, msg) {
  unless (val.isNotEmpty) { throw Exception(msg); }
}

defmacro requirePositive(val, msg) {
  unless (val > 0) { throw Exception(msg); }
}
```

```dart
// lib/models.dmacro
importMacros("lib/macros/validators.dmacro");

bool createOrder(String customerId, double amount) {
  requireNonEmpty(customerId, "Customer ID required");
  requirePositive(amount, "Amount must be positive");
  return true;
}
```

`importMacros` reads the specified `.dmacro` (or `.sexp`) file, runs it through the expander, and registers any `defmacro` calls as a side effect. No Dart output is produced from the import statement itself.

For pub packages, use the `package:` URI form:

```dart
importMacros("package:myteam_macros/validators.dmacro");
```

dmacro resolves the path via `.dart_tool/package_config.json` (written by `dart pub get`).

---

### 10. OpenAPI `oneOf` → sealed class hierarchy

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

### 11. YAML OpenAPI specs

`defFromOpenApi` accepts `.yaml` and `.yml` files in addition to `.json` — no external dependencies:

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
| `defrecord Name { ... }` | Immutable class: fields, constructor, `copyWith`, deep `==`/`hashCode`, `toString`, **`fromJson`/`toJson`** with camelCase JSON keys | Functions can't generate class declarations |
| `defrecord(snake_case) Name { ... }` | Same as `defrecord` but JSON keys are converted to snake_case (`orderId` → `"order_id"`) | Covers the common case where the API uses snake_case and Dart uses camelCase |
| `@json_key("name") Type field;` | Per-field JSON key override — wins over camelCase and snake_case | N/A — field annotation |
| `defunion Name { ... }` | Sealed class hierarchy | Same |
| `defmacro name(params) { ... }` | User-defined template macro, registered for use in the same file | Functions run at call time with values; macros run at expand time with code |
| `defmacro(declaration) name(params) { ... }` | User macro with output-type validation — errors at call time if output isn't a declaration | Functions have no way to validate the shape of their return value as code |
| `defmacro(expression) name(params) { ... }` | User macro validated to produce an expression | Same |
| `defmacro(statement) name(params) { ... }` | User macro validated to produce a statement | Same |
| `importMacros("path")` | Load macro definitions from another `.dmacro` / `.sexp` file; supports `package:` URIs | Functions can't register macros at generation time |
| `defFromJsonSchema("path")` | `defrecord` from a JSON Schema file; `$defs`/`definitions` blocks and `oneOf` are supported | Functions run at runtime; I/O during generation requires a macro |
| `defFromOpenApi("path", "Name")` | `defrecord` (or `defunion` for `oneOf`) from an OpenAPI `components/schemas` entry; accepts `.json`, `.yaml`, or `.yml` | Same |
| `defAllFromJsonSchema("dir/")` | One `defrecord` per `.json` file in a directory | Same |
| `unless (cond) { ... }` | `if (!(cond)) { ... }` | Convenience only — could be a function but this reads better |
| `when (cond) { ... }` | `if (cond) { ... }` | Same |
| `assertThat(expr)` | `if (!expr) throw AssertionError("Expected: <source>")` | Functions receive `false`, not the expression that produced it |
| `swap!(a, b)` | `final _tmp = a; a = b; b = _tmp;` | Functions receive values, not variable names |
| `withRetry(n, expr)` | Inline `for` loop with `try/catch` | Body is inlined, not a callback — `return`/`break` work normally; a higher-order function can't do this |

---

## Workflow

There are two ways to use dmacro — pick whichever fits your file:

**Separate file** — clean source/output split:
```
you write           dmacro compiles           you commit
──────────          ──────────────            ──────────
models.dmacro  →    models.dart          →    both files
                    (full Dart class)
```
The `.dmacro` file is the source. The `.dart` file is the output. Commit both; never hand-edit the `.dart`.

**Inline block** — macros inside an existing `.dart` file:
```dart
// lib/models.dart  (before)
// @@dmacro
defrecord Point { double x; double y; }
// @@end
```
```bash
dart run bin/dmacro.dart compile lib/models.dart
```
```dart
// lib/models.dart  (after — macro source kept as comments, output injected below)
// @@dmacro
// defrecord Point { double x; double y; }
// @@generated
class Point { ... }
// @@end
```
One file. Edit the `//`-prefixed source lines and re-run to regenerate. See [`example/inline_demo.dart`](example/inline_demo.dart) for a working example.

### Flutter project integration

In a Flutter project, run `dmacro watch` alongside `flutter run`. The VS Code extension does this automatically — it recompiles `.dmacro` files on save and triggers hot reload 500 ms later. Manually:

```bash
# Terminal 1 — Flutter dev server
flutter run

# Terminal 2 — dmacro watcher
dart run bin/dmacro.dart watch lib/models/
```

Save a `.dmacro` file → dmacro regenerates the `.dart` → Flutter hot-reloads.

The generated `.dart` files are plain Dart — they work with `Provider`, `Riverpod`, `Bloc`, and any other state management. No special integration required; they're just immutable value classes.

**Merge conflicts in generated files:** treat them the same as `build_runner` output. Resolve the conflict in the `.dmacro` source file, run `dart run bin/dmacro.dart compile lib/models/` to regenerate, then commit the fresh output.

### Installation

```yaml
# pubspec.yaml — git dependency (pub.dev publish is tracked in the backlog)
dev_dependencies:
  dmacro:
    git: https://github.com/caglarkullu/dart-macro
```

```bash
dart pub get
dart run dmacro compile <file>     # the executable comes with the dependency
```

To register your own macros, add a `tool/dmacro.dart` entry point calling
`runDmacro` — see [Quick start](#quick-start) above and
[`doc/WRITING_MACROS.md`](doc/WRITING_MACROS.md).

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

### Field-level error attribution

By default, `dart analyze` errors on generated code map to the `defrecord` declaration line. Add `--field-origins` to get per-field precision:

```bash
dart run bin/dmacro.dart compile models.dmacro --field-origins
# embeds // @dmacro-origin: models.dmacro:5 before each generated field
```

This adds one comment per field in the generated file. Useful when you have type errors on specific fields; unnecessary noise otherwise.

### VS Code extension

The `vscode-ext/` directory contains a VS Code extension that gives you:

- Syntax highlighting for `.dmacro` and `.sexp` files
- Compile on save (runs `dmacro compile` automatically)
- Errors shown as red squiggles in the editor
- Commands:
  - **dmacro: Compile File** — compile the active `.dmacro` or `.sexp` file
  - **dmacro: Compile Workspace** — compile all sources in the workspace
  - **dmacro: Expand Macro at Cursor** — run `dmacro trace` on the active file and show the full expansion tree in a side panel; useful for understanding what a macro generates without opening the `.dart` output file

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
List<Node>            ← code is data (nested lists, the Lisp model)
    ↓  async expander    ← macros run here; I/O is allowed; macros can be async
List<Node>            ← fully expanded, no macros remain
    ↓  emitter
Dart source (.dart)
```

A `Node` is `dynamic` — either an atom (`String`, `int`, `double`, `bool`, `null`) or a `List<Node>`. A macro is `(List<Node>) → Node`. The Lisp notation `(unless (> x 0) body)` is the Dart value `['unless', ['>', 'x', 0], 'body']` — identical structure, both are just nested lists. Macros receive that structure, inspect it, transform it, and return new structure. The emitter then serializes the final AST to Dart source text.

The **async expander** is why `defFromJsonSchema` works: macros run at generation time and can `await` file I/O, HTTP requests, or anything else. No other Dart code-generation tool allows this without a persistent build daemon. The official Dart macros [explicitly ruled it out](https://dart.dev/language/macros) because async execution inside an incremental compiler is intractable. A preprocessor has no such constraint.

### Why a preprocessor and not a compiler plugin

The Dart team's macro effort died on this collision:

```
powerful compile-time execution  ⨯  fast incremental rebuild + hot reload
```

Macros that run arbitrary code make incremental compilation intractable, and hot reload needs millisecond recompiles. The two could not be reconciled inside the compiler.

dmacro is not inside the compiler. It transforms `.dmacro` files into `.dart` files as a separate step, then steps aside. The compiler sees only plain `.dart` files. This costs one extra step (the generated `.dart` files are committed, just like with `build_runner`) but buys the entire capability: arbitrary code at expansion time, including I/O. That trade is worth it.

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
| Read external files at generation time | ✅ | ❌ | ❌ | ❌ |
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
                          Also handles inline @@dmacro blocks in .dart files
lib/src/
  core.dart               Node type, expand(), emit()
  async_expand.dart       Async macro expander (enables generation-time I/O)
  schema_macros.dart      defFromJsonSchema, defFromOpenApi, defAllFromJsonSchema,
                          importMacros, defmacro_typed
  yaml_parser.dart        Built-in YAML parser (no external deps)
  builtins.dart           unless, when, swap!, assertThat, withRetry, defrecord, defunion, defmacro
  dart_parser.dart        .dmacro parser (defmacro declarations, typed macros)
  tokenizer.dart          .dmacro tokenizer
  reader.dart             S-expression reader
example/
  ecommerce/              Domain models: Product, Order, Cart, OrderStatus
  api_from_schema/        Types from a directory of JSON Schemas
  openapi_demo/           Types from an OpenAPI spec (JSON + YAML)
  schema_demo/            Single defFromJsonSchema walkthrough
  inline_demo.dart        Inline @@dmacro blocks inside a regular .dart file
  payment.dmacro          Core syntax reference (.dmacro style)
  payment.sexp            Core syntax reference (S-expression style)
vscode-ext/               VS Code extension source
```
