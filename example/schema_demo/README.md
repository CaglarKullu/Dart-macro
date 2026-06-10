# Schema Demo

This example shows how dmacro generates a Dart class from a JSON Schema file
during the generation step — no annotation class required.

When you run `dmacro compile`, the macro reads the `.json` file and writes a
complete, typed, immutable `.dart` class. The generated class is static Dart:
it compiles into your app binary. If the schema changes after deployment, the
app uses the old types — you update the spec, re-run dmacro, and redeploy.

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

The macro produces a **complete, zero-dependency Dart class**:

```dart
class Payment {
  final double amount;
  final String currency;
  final String? reference;
  final List<String>? tags;

  const Payment({
    required this.amount,
    required this.currency,
    required this.reference,
    required this.tags,
  });

  Payment copyWith({double? amount, String? currency, String? reference, List<String>? tags}) => ...;

  @override
  bool operator ==(Object other) => ...;

  @override
  int get hashCode => ...;

  @override
  String toString() => ...;

  factory Payment.fromJson(Map<String, dynamic> json) => ...;
  Map<String, dynamic> toJson() => ...;
}
```

Notice: no imports, no external dependencies, full `fromJson`/`toJson` with camelCase key mapping, deep value equality, and `copyWith`.

## Advanced schema features

`defFromJsonSchema` handles the full JSON Schema feature set needed for real APIs:

- **`$defs` / `definitions`** — local type references are generated before the main record so `$ref` fields resolve correctly
- **Inline `enum` properties** — a Dart `enum` is generated alongside the record, with `values.byName` / `.name` serialization
- **`oneOf`** — generates a sealed `defunion` hierarchy
- **`format: date-time` / `date`** — mapped to `DateTime` with ISO-8601 serialization
- **`snake_case` JSON keys** — use `defrecord(snake_case)` in your macro source to emit `snake_case` JSON keys

## Custom JSON key mapping

If the schema doesn't perfectly match Dart conventions, override individual keys:

```dart
defrecord User {
  @json_key("user_id")
  String id;
  
  String email;
}
```

The `@json_key` annotation wins over any auto-conversion (camelCase or snake_case).

## How this compares to build_runner

With `build_runner` + `json_serializable`, you write the `Payment` class yourself,
add `@JsonSerializable()`, run the generator, and it fills in `fromJson`/`toJson`.
The class must exist before generation runs.

With dmacro, the JSON Schema is the source. You don't write a `Payment` class —
the macro creates it. One line replaces ~40 lines of Dart boilerplate.

The runtime behaviour is identical: both approaches produce static Dart types that
compile into your binary. Neither adapts to schema changes at runtime.
