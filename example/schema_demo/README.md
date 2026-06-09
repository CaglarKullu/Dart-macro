# Schema Demo

This example shows **async compile-time I/O** — a macro reads a JSON Schema
at build time and generates a complete, typed, immutable Dart class with no
build_runner required.

## Input

`schemas/payment.json` — a plain JSON Schema:

```json
{
  "title": "Payment",
  "type": "object",
  "properties": {
    "amount":    { "type": "number" },
    "currency":  { "type": "string" },
    "reference": { "type": "string" },
    "tags":      { "type": "array", "items": { "type": "string" } }
  },
  "required": ["amount", "currency"]
}
```

`models.dmacro` — one line of macro invocation:

```
defFromJsonSchema("example/schema_demo/schemas/payment.json");
```

## Command

```bash
dart run bin/dmacro.dart compile example/schema_demo/models.dmacro
```

## Output (`models.dart`)

```dart
class Payment {
  final double amount;
  final String currency;
  final String? reference;
  final List<String>? tags;
  const Payment({required this.amount, required this.currency, required this.reference, required this.tags});
  Payment copyWith({double? amount, String? currency, String? reference, List<String>? tags}) => ...;
  @override bool operator ==(Object other) => ...;
  @override int get hashCode => ...;
  @override String toString() => ...;
}
```

## Advanced schema features

`defFromJsonSchema` handles the full JSON Schema feature set needed for real APIs:

- **`$defs` / `definitions`** — local type references are generated before the main record so `$ref` fields resolve correctly
- **Inline `enum` properties** — a Dart `enum` is generated alongside the record, with `values.byName` / `.name` serialization
- **`oneOf`** — generates a sealed `defunion` hierarchy
- **`format: date-time` / `date`** — mapped to `DateTime` with ISO-8601 serialization

## What this proves

Every existing Dart code-gen tool (build_runner, freezed, json_serializable) transforms
**code that already exists**. They cannot read an external source of truth at expansion
time because their execution environments forbid I/O.

A preprocessor with async macros **can**. One macro call — zero build configuration,
zero generated annotation boilerplate, and the schema is the single source of truth.
