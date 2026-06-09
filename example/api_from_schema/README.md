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
| `integer` | `int` |
| `number` | `double` |
| `boolean` | `bool` |
| `array` with `items` | `List<T>` |
| `object` with `title` | the title as a type name |
| required field | `Type field` |
| optional field | `Type? field` (nullable, optional in constructor) |

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
