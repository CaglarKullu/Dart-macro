# Validated Logic (Reference)

This document captures the **proven** behaviour of the core engine. The logic here was
validated in Python and ported to Dart. When the Dart implementation's behaviour is in
question, **this document is authoritative** — match its output exactly.

## `expand` — the macro expander

```
expand(node):
  if node is not a list, or is empty:        return node
  head, *args = node
  if head is a string AND head is a macro:   return expand( macro[head](args) )
  otherwise:                                 return [head, *map(expand, args)]
```

Key properties, all validated:

- Macros receive **unevaluated** operands (code, not values).
- The macro result is **re-expanded** (macros can expand to other macros).
- Non-macro lists are recursed into.
- Idempotent: `expand(expand(x)) == expand(x)`.

## `emit` — the Dart code generator

Emits Dart from an expanded AST. Validated rules:

| Node form | Emits |
|-----------|-------|
| `null` / `bool` / `int` / `double` | the literal |
| `String` atom | verbatim (identifier / operator / raw fragment) |
| `['+', a, b]` (and `- * / == != < > <= >= && \|\|`) | `(a OP b)`, variadic |
| `['!', x]` | `!x` |
| `['let', name, v]` | `final name = v` |
| `['var', name, v]` | `var name = v` |
| `['set!', name, v]` | `name = v` |
| `['return', v]` | `return v` |
| `['throw', v]` | `throw v` |
| `['do', s1, s2, …]` | statements joined with `;` |
| `['if', c, then]` | `if (c) { then }` |
| `['if', c, then, else]` | `if (c) { then } else { else }` |
| `['while', c, body]` | `while (c) { body }` |
| `['for-in', v, iter, body]` | `for (final v in iter) { body }` |
| `['try', body, e, catch]` | `try { body } catch (e) { catch }` |
| `['defn', ret, name, params, …body]` | function declaration |
| `['defclass', name, …members]` | `class name { members }` |
| `['field', type, name]` | `final type name;` |
| `['ctor', name, [[type,p]…]]` | `const name({required this.p, …});` — nullable types omit `required` |
| `['copywith', name, [[type,name]…]]` | a `copyWith` method |
| `['equalop', name, fields]` | `operator ==` override |
| `['hashop', _, fields]` | `hashCode` override |
| `['tostringop', name, fields]` | `toString` override |
| `['.method', recv, …args]` | `recv.method(args)` |
| `['.-prop', recv]` | `recv.prop` |
| `[name, …args]` (default) | `name(args)` — function call |

The `defn` emitter **splices top-level `do` blocks** into the function body (a Phase 1
`$splice` generalizes this).

## Validated macro definitions

These produce the outputs shown. Use them as regression tests.

```
unless(cond, body)        → ['if', ['!', cond], body]
when(cond, body)          → ['if', cond, body]

swap!(a, b)               → ['do', ['let', TMP, a],
                                    ['set!', a, b],
                                    ['set!', b, TMP]]
                            (TMP must come from gensym — see Phase 1)

assertThat(expr)          → ['if', ['!', expr],
                                  ['throw', 'AssertionError("Expected: '
                                            + emit(expr) + ', got false")']]

withRetry(n, body)        → ['for-in', ATTEMPT, 'Iterable.generate(' + emit(n) + ')',
                              ['try', body, ERR,
                                ['if', ['==', ATTEMPT, ['-', n, 1]],
                                       ['throw', ERR],
                                       ['print', '"Retrying..."']]]]

defrecord(name, fields…)  → ['defclass', name,
                              field(t,n) for each field,
                              ['ctor', name, [names]],
                              ['copywith', name, fields],
                              ['equalop', name, fields],
                              ['hashop', null, fields],
                              ['tostringop', name, fields]]
```

## Validated end-to-end example

**Input (.dmacro):**

```dart
defrecord Payment {
  double  amount;
  String  currency;
  String? reference;
}

bool validatePayment(double amount, String currency) {
  unless (amount > 0) {
    throw Exception("Amount must be positive");
  }
  assertThat(amount <= 1000000);
  return true;
}

void normalise(double a, double b) {
  when (a > b) {
    swap!(a, b);
  }
}
```

**Output (Dart) — this is the exact validated result (modulo gensym names):**

```dart
class Payment {
  final double amount;
  final String currency;
  final String? reference;
  const Payment({required this.amount, required this.currency, this.reference});
  Payment copyWith({double? amount, String? currency, String? reference}) =>
      Payment(amount: amount ?? this.amount, currency: currency ?? this.currency,
              reference: reference ?? this.reference);
  @override
  bool operator ==(Object other) => identical(this, other) || other is Payment &&
      other.amount == amount && other.currency == currency && other.reference == reference;
  @override
  int get hashCode => Object.hash(amount, currency, reference);
  @override
  String toString() => 'Payment(amount: $amount, currency: $currency, reference: $reference)';
}

bool validatePayment(double amount, String currency) {
  if (!(amount > 0)) {
    throw Exception("Amount must be positive");
  }
  if (!(amount <= 1000000)) {
    throw AssertionError("Expected: (amount <= 1000000), got false");
  }
  return true;
}

void normalise(double a, double b) {
  if ((a > b)) {
    final _tmp = a;
    a = b;
    b = _tmp;
  }
}
```

> Note on formatting: the validated emitter produces correct but unformatted Dart. Running
> `dart format` on the output is expected and should be part of the compile step or tests.
> The redundant outer parens in `((a > b))` are harmless; `dart format` and the analyzer
> accept them. Tightening them is a nice-to-have, not required.

## Tokenizer rules (validated)

- Two-char operators matched before single-char.
- `"..."` strings stored **with** surrounding quotes; escapes `\n \t \" \\` handled.
- Numbers: contain `.` → double, else int.
- Identifiers: `[A-Za-z_][A-Za-z0-9_]*`, optionally one trailing `!` (macro names like
  `swap!`) unless the `!` is followed by `=`.
- Generic types (`List<String>`, `Map<String, dynamic>`) are read by the **parser's**
  type rule, not the tokenizer — the tokenizer emits `<` `>` as operators.
- `//` line comments skipped.

## Parser rules (validated)

- Precedence climbing as listed in `ARCHITECTURE.md`.
- `_parseType`: `Name` optionally followed by `<T, U, …>` and/or `?`.
- `final`/`var` with optional leading type: lookahead — if an IDENT (or `?`) follows the
  first IDENT, the first was the type.
- Control-flow-style macro call: an expression-statement immediately followed by `{ … }`
  becomes `[macroName, ...args, block]`, where a single-statement block is that statement
  and a multi-statement block is `['do', …]`.
