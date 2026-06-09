# Generate types from a directory of JSON Schemas

One macro call generates a Dart class for every `.json` file in a folder.
Add a schema, recompile, new class appears. No other changes required.

## How it works

`models.dmacro` contains a single line:

```dart
defAllFromJsonSchema("example/api_from_schema/schemas/");
```

The macro scans the `schemas/` directory, reads each `.json` file in alphabetical order, maps the schema fields to Dart types, and emits a `defrecord` class for each one.

## Schemas in this example

| File | Title | Required fields | Optional fields |
|---|---|---|---|
| `schemas/address.json` | `Address` | line1, city, country | line2, state, postcode |
| `schemas/notification.json` | `Notification` | id, userId, type, createdAt | title, body, isRead |
| `schemas/user.json` | `User` | id, email, createdAt | displayName, avatarUrl, isVerified |

## Compile

```bash
dart run bin/dmacro.dart compile example/api_from_schema/models.dmacro
# writes example/api_from_schema/models.dart
```

## Type mapping

| JSON Schema type | Dart type |
|---|---|
| `string` | `String` |
| `string` + `format: date-time` / `date` | `DateTime` (parsed in `fromJson`, ISO-8601 in `toJson`) |
| `integer` | `int` |
| `number` | `double` |
| `boolean` | `bool` |
| `array` with `items` | `List<T>` |
| `object` with `title` | the title as a type name |
| `enum` values on a property | generates a Dart `enum` and uses `values.byName` / `.name` for serialization |
| `$ref` pointing to a `$defs` / `definitions` entry | the referenced type, with enum-aware serialization if the target is an enum |
| `oneOf` array | `defunion` sealed class hierarchy |
| required field | `Type field` |
| optional field | `Type? field` (nullable, optional in constructor) |

Each generated class includes `fromJson`/`toJson`, deep `==`/`hashCode`, and `copyWith` — a ready-to-use API model, not just a data holder.

## Adding a new type

1. Create `schemas/product.json`:

```json
{
  "title": "Product",
  "type": "object",
  "required": ["id", "name", "price"],
  "properties": {
    "id":       { "type": "string" },
    "name":     { "type": "string" },
    "price":    { "type": "number" },
    "imageUrl": { "type": "string" }
  }
}
```

2. Recompile:

```bash
dart run bin/dmacro.dart compile example/api_from_schema/models.dmacro
```

`class Product` now appears in `models.dart`. No other file to touch.
