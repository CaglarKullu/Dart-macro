# dart_sexp — Lisp-style macros in Dart

The closest you can get to Lisp macros in Dart.
Code is data. Macros are functions. Full Dart emitted.

---

## The core idea

In Lisp, code and data are the same thing — both are nested lists.
A macro is just a function that receives a list and returns a list.

We do the same in Dart using `dynamic` (either atom or `List<dynamic>`):

```dart
// Lisp:
// (defmacro unless (condition body)
//   `(if (not ,condition) ,body))

// Dart equivalent:
defmacro('unless', (args) => ['if', ['!', args[0]], args[1]]);

// Usage (code written as data):
final code = ['unless', ['>', 'balance', 0], ['print', '"negative"']];

// Expands to:
// ['if', ['!', ['>', 'balance', 0]], ['print', '"negative"']]

// Emits:
// if (!(balance > 0)) {
//   print("negative")
// }
```

---

## What this enables that nothing else in Dart can do

### 1. `swap!` — variable injection into caller scope

A function receives **values** — it can never write back to the caller's variables.
A macro receives **code** — it generates new code in the caller's scope.

```dart
defmacro('swap!', (args) => ['do',
  ['let', '_tmp', args[0]],
  ['set!', args[0], args[1]],
  ['set!', args[1], '_tmp'],
]);

// ['swap!', 'x', 'y'] emits:
// final _tmp = x;
// x = y;
// y = _tmp;
```

### 2. `assert-that` — error message contains source expression

A function receives the boolean result of `amount > 0`.
The macro receives the expression `['>', 'amount', 0]` — it can read the source.

```dart
defmacro('assert-that', (args) => ['if',
  ['!', args[0]],
  ['throw', 'AssertionError("Expected: ${emit(args[0])}, got false")'],
]);

// ['assert-that', ['>', 'amount', 0]] emits:
// if (!(amount > 0)) {
//   throw AssertionError("Expected: (amount > 0), got false")
// }
```

### 3. `defrecord` — generates an entire class

`macro_kit` and `build_runner` can only **append** to existing classes via mixins.
This generates the class itself from a compact spec:

```dart
defmacro('defrecord', (args) {
  final name   = args[0];
  final fields = args.sublist(1);
  return ['defclass', name,
    ...fields.map((f) => ['field', f[0], f[1]]),
    ['ctor', name, fields.map((f) => f[1]).toList()],
    ['copywith', name, fields],
    ['equalop',  name, fields],
    ['hashop',   name, fields],
    ...
  ];
});

// ['defrecord', 'Payment', ['double', 'amount'], ['String', 'currency']]
// Emits a complete class: fields, constructor, copyWith, ==, hashCode, toString
```

### 4. Macros calling macros

```dart
['unless',
  ['&&', ['>', 'x', 0], ['<', 'x', 10000]],
  ['throw', 'Exception("out of range")']
]
// unless expands to if+!
// then && expands recursively
// result is pure Dart with no runtime overhead
```

---

## Comparison

| | Lisp macros | dart_sexp | macro_kit | build_runner |
|---|---|---|---|---|
| Code is data | ✅ Lists = code | ✅ Lists = code | ❌ Text | ❌ Text |
| Macro is same language | ✅ Lisp fn | ✅ Dart fn | ✅ Dart fn | ✅ Dart fn |
| Full language power | ✅ | ✅ | ✅ | ✅ |
| Expression-level transforms | ✅ | ✅ | ❌ declarations only | ❌ declarations only |
| Variable injection | ✅ | ✅ | ❌ | ❌ |
| Generate entire class | ✅ | ✅ | ❌ only appends | ❌ |
| Process boundary | ❌ none | ❌ none | ✅ WebSocket | ✅ subprocess |
| IDE integration | native | ❌ | ✅ | ✅ |
| Real Dart syntax | N/A | ❌ list syntax | ✅ | ✅ |
| Zero dependencies | ✅ | ✅ | ❌ | ❌ |

---

## What we sacrifice

The unavoidable cost: **you write code as data, not as normal Dart syntax**.

```dart
// Dart you'd want to write:
unless (balance > 0) {
  print("negative");
}

// What you actually write:
['unless', ['>', 'balance', 0], ['print', '"negative"']]
```

Adding a parser layer on top would let you write a friendlier syntax — either
S-expressions `(unless (> balance 0) (print "negative"))` or a Dart-like DSL
that gets parsed into these lists. That's the next step.

---

## The honest answer

This is as close to Lisp macros as Dart can get because it has the same
fundamental property: **code and data are the same structure**, and **macros
are functions in the same language**. No process boundary. No serialization.
No file writes. The macro sees the code, not the value.

The gap from Lisp is the syntax layer — Lisp's reader gives you clean
S-expression syntax for free. In Dart, you pay with list literal noise.
The semantics are the same; the ergonomics are not.
