# dart_macros

Two compile-time macro systems for Dart. No `build_runner`, no Flutter
constraints, no external dependencies — pure Dart SDK.

The Dart team [cancelled language-level macros in January 2025](https://dart.dev/language/macros).
This project implements the same idea as a standalone CLI preprocessor.

---

## System 1 — `dmacro`: Lisp-style macros

The closest you can get to Lisp macros in Dart.
Code is data. Macros are functions. Full Dart emitted.

### The core idea

In Lisp, code and data are the same thing — both are nested lists.
A macro is just a function that receives a list and returns a list.

We do the same in Dart using `dynamic` (either atom or `List<dynamic>`):

```dart
// Dart equivalent of: (defmacro unless (condition body) `(if (not ,condition) ,body))
defmacro('unless', (args) => ['if', ['!', args[0]], args[1]]);

// Usage (code written as data):
final code = ['unless', ['>', 'balance', 0], ['print', '"negative"']];

// Expands to:  ['if', ['!', ['>', 'balance', 0]], ['print', '"negative"']]
// Emits:
// if (!(balance > 0)) {
//   print("negative")
// }
```

You can also use the typed node API for a more Dart-like feel:

```dart
defmacro('unless', (args) => $if($not(args[0]), args[1]));
```

Both styles produce identical output — choose whichever reads better.

### What this enables that nothing else in Dart can do

**`swap!` — variable injection into caller scope**

A function receives *values* — it can never write back to the caller's variables.
A macro receives *code* — it generates new code in the caller's scope.

```dart
defmacro('swap!', (args) => ['do',
  ['let', '_tmp', args[0]],
  ['set!', args[0], args[1]],
  ['set!', args[1], '_tmp'],
]);
// ['swap!', 'x', 'y'] emits:  final _tmp = x; x = y; y = _tmp;
```

**`assert-that` — error message contains source expression**

A function receives the boolean result of `amount > 0`.
The macro receives the expression `['>', 'amount', 0]` — it can read the source.

```dart
defmacro('assert-that', (args) => ['if',
  ['!', args[0]],
  ['throw', 'AssertionError("Expected: ${emit(args[0])}, got false")'],
]);
// ['assert-that', ['>', 'amount', 0]] emits:
// if (!(amount > 0)) { throw AssertionError("Expected: (amount > 0), got false") }
```

**`defrecord` — generates an entire class**

`macro_kit` and `build_runner` can only *append* to existing classes via mixins.
This generates the class itself from a compact spec:

```dart
['defrecord', 'Payment', ['double', 'amount'], ['String', 'currency']]
// Emits a complete class: fields, constructor, copyWith, ==, hashCode, toString
```

**Macros calling macros**

```dart
['unless', ['&&', ['>', 'x', 0], ['<', 'x', 10000]], ['throw', 'Exception("out of range")']]
// unless expands to if+! → then && expands recursively → pure Dart, zero runtime overhead
```

### Comparison

| | Lisp macros | dmacro | macro_kit | build_runner |
|---|---|---|---|---|
| Code is data | ✅ | ✅ Lists = code | ❌ Text | ❌ Text |
| Macro is same language | ✅ | ✅ Dart fn | ✅ Dart fn | ✅ Dart fn |
| Expression-level transforms | ✅ | ✅ | ❌ declarations only | ❌ declarations only |
| Variable injection | ✅ | ✅ | ❌ | ❌ |
| Generate entire class | ✅ | ✅ | ❌ only appends | ❌ |
| Process boundary | ❌ none | ❌ none | ✅ WebSocket | ✅ subprocess |
| Zero dependencies | ✅ | ✅ | ❌ | ❌ |
| Real Dart syntax | N/A | ❌ list syntax | ✅ | ✅ |

### Usage

```bash
dart run bin/dmacro.dart compile example/payment.sexp    # S-expression syntax
dart run bin/dmacro.dart compile example/payment.dmacro  # Dart-like syntax
dart run bin/dmacro.dart repl                            # interactive REPL
```

### The honest trade-off

You write code as data, not as normal Dart syntax:

```dart
// What you'd want to write:      // What you actually write:
unless (balance > 0) {            ['unless', ['>', 'balance', 0],
  print("negative");                ['print', '"negative"']]
}
```

The semantics are identical to Lisp macros. The ergonomics cost is the list
literal syntax — Lisp's reader gives you clean S-expressions for free.
`.dmacro` syntax (Dart-like source format) reduces this cost significantly.

---

## System 2 — `dart_macros`: annotation-based preprocessor

You annotate your classes. You run the tool. Generated code is injected
**directly into your source file**, wrapped in markers so it's idempotent.

```
BEFORE                              AFTER
──────────────────────────────      ──────────────────────────────
@DataClass()                        @DataClass()
class Payment {                     class Payment {
  final double amount;                final double amount;
  final String currency;              final String currency;
  final String? reference;            final String? reference;

  const Payment({...});               const Payment({...});
}
                                      // ━━━ dart_macros generated ━━━
                                      Payment copyWith({...}) { ... }
                                      @override bool operator ==(Object other) { ... }
                                      @override int get hashCode => Object.hash(...);
                                      @override String toString() => 'Payment(...)';
                                      // ━━━ end dart_macros ━━━
                                    }
```

### Available annotations

| Annotation     | Generates                                           |
|----------------|-----------------------------------------------------|
| `@DataClass()` | `copyWith` · `==` · `hashCode` · `toString`         |
| `@Singleton()` | Private constructor · `_instance` · `getInstance()` |
| `@Logged()`    | `log(message)` · `logFields()` helpers              |

### Usage

```bash
dart run bin/dart_macros.dart build lib/      # apply macros in-place
dart run bin/dart_macros.dart preview lib/    # show what would change
dart run bin/dart_macros.dart clean lib/      # strip all generated blocks
```

### Adding your own macro

1. Add a class in `lib/src/generator.dart`:

```dart
class MyMacroGenerator extends MacroGenerator {
  @override final String annotationName = 'MyMacro';

  @override
  String generate(ClassInfo info) {
    // info.name, info.fields (List<FieldInfo>), info.annotations
    return '  void myGeneratedMethod() => print("${info.name}");';
  }
}
```

2. Register it in the `macroRegistry` at the bottom of `generator.dart`.

3. Run `dart run bin/dart_macros.dart build .`

### Why not build_runner?

`build_runner` requires separate `*.g.dart` files, a full pub package, and
annotation + generator packages. `dart_macros` injects code directly into
your source file in one command with zero pub dependencies.

---

## Project structure

```
lib/src/
  core.dart               Node typedef, expand(), emit()
  reader.dart             S-expression reader
  tokenizer.dart          .dmacro tokenizer
  dart_parser.dart        .dmacro parser
  nodes.dart              Typed node constructors ($if, $not, …)
  builtins.dart           Built-in macros (unless, swap!, defrecord, …)
  models.dart             FieldInfo, ClassInfo
  dart_source_parser.dart Dart source → ClassInfo
  generator.dart          Annotation macro generators
  transformer.dart        Applies generators, manages markers
bin/
  sexp.dart               dmacro CLI (compile / repl)
  dart_macros.dart        dart_macros CLI (build / preview / clean)
example/
  main.dart               dmacro demo
  approaches.dart         Three ways to write macro code compared
  payment.sexp            Payment record in S-expression syntax
  payment.dmacro          Payment record in Dart-like syntax
docs/
  ARCHITECTURE.md         Design decisions and pipeline details
  VALIDATED_LOGIC.md      Reference logic validated in Python
specs/                    Per-phase specifications
backlog/                  Task tracking
```
