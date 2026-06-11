# dmacro

**Write your own Dart code generators. One function. No build daemon. No compiler plugins.**

```dart
// tool/dmacro.dart — your entry point, your project
import 'package:dmacro/dmacro.dart';

void main(List<String> args) => runDmacro(args, registerMacros: () {

  defAsyncMacro('defwidget', (args) async {
    final name = unquote(args[0] as String);
    final fields = args.skip(1).cast<List>().toList();
    // ... build whatever your team actually needs
    return 'class $name extends StatelessWidget { ... }';
  });

});
```

```bash
dart run tool/dmacro.dart compile lib/widgets.dmacro
```

That's the whole model. A macro is a Dart function. You register it, use it, and the engine calls it at generation time — before the compiler sees anything.

---

## The shift

Every other code-generation tool ships a **fixed menu**: `freezed` gives you immutable classes; `build_runner` + `json_serializable` gives you serialization. You pick from what they built.

dmacro ships the **means to build whatever you need**.

The built-ins — `defrecord`, `defFromJsonSchema`, `defunion` — are not the product. They are the **standard library**: working examples of what any developer can write with the same public API. `defrecord` is just the first page of a cookbook. You can re-create freezed in an afternoon. You can generate from your own schemas, your own conventions, your own data sources.

The Dart team [cancelled language-level macros](https://dart.dev/language/macros) in January 2025 because async execution inside an incremental compiler breaks hot reload. dmacro sidesteps the problem entirely: it runs as a plain preprocessor, before the compiler, so macros can `await` anything — files, HTTP, databases. That trade (one extra commit step) buys full generative power.

---

## Write a macro in 5 minutes

### Step 1 — add the dependency

```yaml
# pubspec.yaml
dev_dependencies:
  dmacro:
    git: https://github.com/caglarkullu/dart-macro
```

### Step 2 — create your entry point

```dart
// tool/dmacro.dart  ← NOT a root build.dart (Dart treats that as a native-assets hook)
import 'package:dmacro/dmacro.dart';

void main(List<String> args) => runDmacro(args, registerMacros: () {

  defAsyncMacro('defapi', (args) async {
    final endpoint = unquote(args[0] as String);
    // Read your OpenAPI spec, hit your API, parse your custom schema —
    // anything you can await works here.
    return 'class ${endpoint}Client { /* generated */ }';
  });

});
```

### Step 3 — use it

```dart
// lib/api_clients.dmacro
defapi("users");
defapi("orders");
defapi("products");
```

```bash
dart run tool/dmacro.dart compile lib/api_clients.dmacro
# → lib/api_clients.dart  (three generated client classes)
```

The full CLI — `compile`, `watch`, `trace`, `--check` — is available through your entry point with your macros loaded. `runDmacro` calls the standard library first, then yours.

---

## How a macro works

In dmacro, code is data. Your source file parses to nested lists:

```
defwidget MyButton { String label; }
```
becomes
```dart
['defwidget', 'MyButton', ['String', 'label']]
```

Your macro function receives that list, transforms it, returns new structure (or a Dart source string). The engine writes it out.

```dart
defAsyncMacro('defwidget', (args) async {
  final name = args[0] as String;          // 'MyButton'
  final fields = args.skip(1).cast<List>().toList(); // [['String','label'], ...]

  return 'class $name extends StatelessWidget { ... }';
});
```

A macro sees the **structure** of the code, not just values. That's why `assertThat(amount > 0)` can put `"(amount > 0)"` in the error message — the macro receives `['>', 'amount', 0]`, not `false`. A function can never do that.

---

## Three tiers — pick your power level

### Tier 1 — template macros (no Dart needed)

Define macros inline in your `.dmacro` file. Pure substitution, no code:

```dart
defmacro guard(cond, err) {
  unless (cond) { throw Exception(err); }
}

bool createUser(String email) {
  guard(email.contains("@"), "Invalid email");
  return true;
}
```

### Tier 2 — `$map`: templates that iterate

A trailing `...rest` parameter collects variadic arguments. `$map` repeats a template over them:

```dart
defmacro requireAll(...conds) {
  $map(conds, c) { unless(c) { throw ArgumentError("requirement failed"); } }
}

void transfer(int amount, int balance) {
  requireAll(amount > 0, amount <= balance);
  // → two if-throw guard clauses, inlined
}
```

### Tier 3 — Dart-function macros (full power)

Registered in `tool/dmacro.dart`. Full Dart — loops, I/O, string building, anything:

```dart
defAsyncMacro('defFromMySchema', (args) async {
  final path = unquote(args[0] as String);
  final schema = jsonDecode(await File(path).readAsString());

  final fields = (schema['fields'] as List).map((f) =>
    '  final ${f['type']} ${f['name']};'
  ).join('\n');

  return 'class ${schema['name']} {\n$fields\n  // ...constructor, ==, toJson\n}';
});
```

The built-ins are Tier-3 macros. They are not privileged in any way — they use the same `defAsyncMacro` you do.

---

## What the standard library gives you free

You don't have to build everything from scratch. These ship with dmacro:

### Immutable value classes

```dart
defrecord Product {
  String  id;
  String  name;
  double  price;
  String? imageUrl;
}
```

Generates: constructor, `copyWith`, deep `==`/`hashCode`, `toString`, `fromJson`, `toJson`. ~60 lines of Dart from 7. No annotations, no existing class to annotate — the macro **creates** the class.

### Types from your API spec — at generation time

```dart
defFromJsonSchema("schemas/payment.json");
defFromOpenApi("api/openapi.yaml", "User");
defAllFromJsonSchema("schemas/");      // entire directory, one line
```

Reads the file **when you run `dmacro compile`**, not at runtime. Update the spec, recompile, done. No `*.g.dart` files. No `build_runner watch`. The output imports nothing.

This is what the cancelled official Dart macros could not offer: async execution at generation time. dmacro runs before the compiler, so macros can `await` anything.

### Control flow

```dart
unless (amount > 0) { throw Exception("must be positive"); }
assertThat(email.contains("@"));   // error: "Expected: (email.contains("@"))"
withRetry(3, postJson(endpoint, payload));  // inlined loop, not a callback
swap!(a, b);                        // injects temp variable into caller's scope
```

These macros do things functions cannot: inject variables into the caller's scope, embed the source expression in an error message, inline a loop body so `return`/`break` work as expected.

### Sealed unions

```dart
defunion AuthState {
  Unauthenticated {}
  Authenticating  {}
  Authenticated   { String userId; }
  Error           { String message; }
}
```

Generates a sealed class hierarchy. Use directly with Dart pattern matching.

---

## Real-world scenarios

### Your team's boilerplate — not ours

Every Dart codebase has its own patterns. `defrecord` generates our version of an immutable class. Yours might need different conventions — snake_case constructors, custom `copyWith` behaviour, a specific `toString` format, extra interfaces. Write the macro once:

```dart
defAsyncMacro('defmodel', (args) async {
  // your conventions, your output
});
```

And every model in your project follows it consistently. When the convention changes, you change one function — not fifty classes.

### Generate from your actual data

The async superpower: your macros can read anything at generation time.

```dart
defAsyncMacro('defFromInternalApi', (args) async {
  final endpoint = unquote(args[0] as String);
  final spec = jsonDecode(await http.get(Uri.parse(endpoint)));
  // generate Dart types from live API spec
});
```

```dart
// models.dmacro
defFromInternalApi("https://api.internal/schema/v2");
```

CI runs `dart run tool/dmacro.dart compile lib/models.dmacro` — the types are always current.

### Share macros across a project

Factor out common template macros into a shared file:

```dart
// lib/macros/validators.dmacro
defmacro requireNonEmpty(val, msg) {
  unless (val.isNotEmpty) { throw Exception(msg); }
}
```

```dart
// lib/models.dmacro
importMacros("lib/macros/validators.dmacro");

bool createOrder(String customerId, double amount) {
  requireNonEmpty(customerId, "Customer ID required");
  return true;
}
```

`importMacros` supports `package:` URIs too — resolves via `.dart_tool/package_config.json`.

---

## Quick reference

### CLI

```bash
dart run tool/dmacro.dart compile lib/models.dmacro    # compile one file
dart run tool/dmacro.dart compile lib/                 # compile a directory
dart run tool/dmacro.dart compile lib/ --check         # CI: exit non-zero if stale
dart run tool/dmacro.dart watch lib/                   # recompile on save
dart run tool/dmacro.dart trace lib/models.dmacro      # print each expansion step
```

Or use the built-in executable (no custom entry point needed for standard library macros):

```bash
dart run dmacro compile lib/models.dmacro
```

### Inline blocks in `.dart` files

No `.dmacro` file required — embed macros in an existing `.dart` file:

```dart
// lib/models.dart
// @@dmacro
defrecord Point { double x; double y; }
// @@end
```

After `dmacro compile lib/models.dart`, the macro source is preserved as comments and the generated class appears below `// @@generated`. Edit the comments, re-run to regenerate.

### Argument shapes

| You write | Your macro receives |
|---|---|
| `m(foo)` | `'foo'` (bare identifier) |
| `m("foo")` | `'"foo"'` — strip with `unquote(arg as String)` |
| `m(42)` | `42` (int) |
| `m(x > 0)` | `['>', 'x', 0]` |
| `m(f(a, b))` | `['f', 'a', 'b']` |
| Block syntax `m Name { T f; }` | `['m', 'Name', ['T', 'f']]` |

### Macro API

```dart
defmacro('name', (args) { ... });           // sync, returns Node
defAsyncMacro('name', (args) async { ... }); // async, can await I/O
unquote(arg as String)                       // strip surrounding quotes
gensym('tmp')                                // unique name per compile
$splice([node1, node2])                      // splice multiple nodes into parent
```

All exported from `package:dmacro/dmacro.dart`.

---

## Comparison

| | **dmacro** | freezed + build_runner | Official Dart macros |
|---|---|---|---|
| Ships today | ✅ | ✅ | ❌ cancelled Jan 2025 |
| Write your own generators | ✅ **the point** | ❌ fixed set | ✅ (was the plan) |
| I/O at generation time | ✅ | ❌ | ❌ (broke hot reload) |
| Zero runtime dependencies | ✅ | ❌ | — |
| No build daemon | ✅ | ❌ | — |
| Inject variables into scope | ✅ | ❌ | ❌ |
| Embed source expressions in errors | ✅ | ❌ | ❌ |
| Dart-like source syntax | ✅ | ✅ | ✅ |
| Works in Flutter projects | ✅ | ✅ | — |

---

## How it works (for the curious)

```
source (.dmacro)
    ↓  tokenizer + parser
List<Node>           ← code as data (nested lists — the Lisp model)
    ↓  async expander   ← your macros run here; await anything
List<Node>           ← fully expanded
    ↓  emitter
Dart source (.dart)
```

`Node` is `dynamic` — an atom or a `List<Node>`. A macro is `(List<Node>) → Node`. The emitter serializes the final tree to Dart source. The generated `.dart` file is committed alongside the `.dmacro` source — just like `build_runner` output, but without the daemon.

See [`doc/ARCHITECTURE.md`](doc/ARCHITECTURE.md) and [`doc/WRITING_MACROS.md`](doc/WRITING_MACROS.md) for the full story.

---

## Project layout

```
lib/
  dmacro.dart           Public API — import this
  src/
    core.dart           Node, expand(), emit()
    async_expand.dart   Async expander — the I/O capability
    builtins.dart       Standard library: unless, defrecord, defunion, $map, …
    schema_macros.dart  Standard library: defFromJsonSchema, defFromOpenApi, …
    cli.dart            runDmacro() — the full CLI as a library
bin/
  dmacro.dart           3-line shim: calls runDmacro(args)
doc/
  WRITING_MACROS.md     The authoring guide — start here
  ARCHITECTURE.md       Design decisions
  VISION.md             The north star
example/
  macro_library/        Pattern A + B distribution examples
  ecommerce/            defrecord in practice
  openapi_demo/         Types from an OpenAPI spec
```
