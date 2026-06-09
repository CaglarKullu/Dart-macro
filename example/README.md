# Examples

Each directory is a self-contained use case. Compile any `.dmacro` file with:

```bash
dart run bin/dmacro.dart compile <path/to/file.dmacro>
```

---

## [`ecommerce/`](ecommerce/)

A realistic e-commerce domain model — products, orders, cart items, shipping addresses, and an order status state machine.

Demonstrates: `defrecord`, `defunion`, `unless`, `assertThat`

```bash
dart run bin/dmacro.dart compile example/ecommerce/models.dmacro
```

---

## [`api_from_schema/`](api_from_schema/)

Generate a Dart class for every JSON Schema in a directory — one macro call.

Demonstrates: `defAllFromJsonSchema`

```bash
dart run bin/dmacro.dart compile example/api_from_schema/models.dmacro
```

---

## [`openapi_demo/`](openapi_demo/)

Generate types directly from an OpenAPI 3.0 spec by schema name.
Accepts both `.json` and `.yaml` / `.yml` specs — no external YAML library required.
`oneOf` schemas are automatically mapped to sealed `defunion` hierarchies.

Demonstrates: `defFromOpenApi`

```bash
dart run bin/dmacro.dart compile example/openapi_demo/models.dmacro
```

---

## [`schema_demo/`](schema_demo/)

Generate a single class from a JSON Schema file.

Demonstrates: `defFromJsonSchema`

```bash
dart run bin/dmacro.dart compile example/schema_demo/models.dmacro
```

---

## [`payment.dmacro`](payment.dmacro) / [`payment.sexp`](payment.sexp)

The same payment domain model written in both syntaxes — Dart-like (`.dmacro`) and S-expression (`.sexp`). Good for comparing the two styles.

---

## [`main.dart`](main.dart)

A runnable Dart program that exercises all built-in macros and prints the emitted output.

```bash
dart run example/main.dart
```
