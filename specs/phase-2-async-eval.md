# Phase 2 — Async Compile-Time Evaluation

**This is the keystone phase — the capability no other Dart tool has.**

**Goal:** make the expander async so macros can perform I/O at expansion time, then build
`defFromJsonSchema` — a macro that reads a JSON Schema file at build time and generates a
complete, typed, immutable Dart class from it.

**Why it matters:** every existing Dart code-gen tool transforms code that already exists.
None can read an external *source of truth* (schema, spec, DB) because their execution
environments forbid I/O. A preprocessor with async macros can. This is the experiment that
determines whether the project has product value beyond learning. See `doc/ARCHITECTURE.md`
§"The preprocessor advantage".

**Prerequisite:** Phase 1 complete (`gensym`, `$splice`).

---

## Task 2.1 — Async expander

### Change
`expand` returns `Future<Node>`. Macros may be sync or async; the expander awaits async
results. Splice flattening (Phase 1) is preserved.

```dart
// lib/src/async_expand.dart  (or evolve core.dart's expand)
typedef MacroFn = FutureOr<Node> Function(List<Node> args);

Future<Node> expand(Node node) async {
  if (node is! List || node.isEmpty) return node;
  final head = node[0];
  final args = (node as List).sublist(1);

  if (head is String && _macros.containsKey(head)) {
    final result = await _macros[head]!(args);   // FutureOr → awaited
    return expand(result);                        // re-expand
  }

  final expanded = <Node>[];
  for (final a in args) {
    expanded.add(await expand(a));                // sequential: deterministic order
  }

  final out = <Node>[head];
  for (final child in expanded) {
    if (child is Splice) { out.addAll(child.nodes); }
    else { out.add(child); }
  }
  return out;
}
```

### Notes / decisions
- Use **sequential** awaits (not `Future.wait`) inside a single form so that gensym
  ordering and any I/O side effects are deterministic. Determinism > micro-perf here.
- `compile()` / `compileDartLike()` become `async` and `await` expansion.
- The CLI's `compile` command already runs in an async `main`; thread the await through.

### Acceptance criteria
1. All Phase 0/1 sync macros still work unchanged through the async expander.
2. An async macro that simply `await`s a `Future.value(...)` expands correctly.
3. Output remains deterministic across runs.

---

## Task 2.2 — `defFromJsonSchema` macro

### Behaviour
`defFromJsonSchema("path/to/schema.json")` reads the JSON Schema at **expansion time**
and emits a `defrecord`-equivalent class (reusing the validated `defrecord` generation
path where possible).

### Input — example schema (`schemas/payment.json`)
```json
{
  "title": "Payment",
  "type": "object",
  "properties": {
    "amount":    { "type": "number" },
    "currency":  { "type": "string" },
    "reference": { "type": "string" }
  },
  "required": ["amount", "currency"]
}
```

### Type mapping (JSON Schema → Dart)
| JSON Schema | Dart | Notes |
|-------------|------|-------|
| `"number"` | `double` | |
| `"integer"` | `int` | |
| `"string"` | `String` | |
| `"boolean"` | `bool` | |
| `"array"` of T | `List<T>` | recurse on `items` |
| `"object"` with `$ref`/title | that type's name | nested model |
| not in `required` | `T?` | nullable |

### Implementation sketch
```dart
// lib/src/schema_macros.dart
import 'dart:convert';
import 'dart:io';

void registerSchemaMacros() {
  defmacro('defFromJsonSchema', (args) async {
    final path = _unquote(args[0] as String);          // strip the literal quotes
    final json = jsonDecode(await File(path).readAsString())
        as Map<String, dynamic>;

    final name     = json['title'] as String;
    final props    = (json['properties'] as Map).cast<String, dynamic>();
    final required = ((json['required'] as List?) ?? const []).cast<String>();

    // Build the same field list defrecord expects: [dartType, fieldName]
    final fields = <List<String>>[];
    for (final entry in props.entries) {
      var type = _dartType(entry.value as Map<String, dynamic>);
      if (!required.contains(entry.key)) type = '$type?';
      fields.add([type, entry.key]);
    }

    // Reuse the validated defrecord generation by emitting the same AST shape.
    return ['defrecord', name, ...fields];
  });
}

String _dartType(Map<String, dynamic> schema) {
  switch (schema['type']) {
    case 'number':  return 'double';
    case 'integer': return 'int';
    case 'string':  return 'String';
    case 'boolean': return 'bool';
    case 'array':
      final items = schema['items'] as Map<String, dynamic>? ?? const {};
      return 'List<${_dartType(items)}>';
    case 'object':
      return (schema['title'] as String?) ?? 'Map<String, dynamic>';
    default:
      return 'dynamic';
  }
}

String _unquote(String s) =>
    (s.startsWith('"') && s.endsWith('"')) ? s.substring(1, s.length - 1) : s;
```

> Reuse, don't duplicate: `defFromJsonSchema` returns a `['defrecord', …]` node and lets
> the existing, validated `defrecord` macro do the actual class generation. This keeps one
> code path for class emission.

### Acceptance criteria
1. Given `schemas/payment.json` above, `defFromJsonSchema("schemas/payment.json");`
   compiles to the **same** `Payment` class as the hand-written `defrecord` in
   `doc/VALIDATED_LOGIC.md` (amount/currency required → non-null; reference optional →
   `String?`).
2. The emitted Dart passes `dart format` and `dart analyze` with no warnings.
3. A nested array property (`"tags": {"type":"array","items":{"type":"string"}}`) maps to
   `List<String>`.
4. A missing file produces a clear compile error naming the path, not a stack trace dump.
5. The whole thing runs with **zero non-SDK dependencies** (`dart:io`, `dart:convert` only).

---

## Task 2.3 — Demo + write-up

Produce `example/schema_demo/`:
- `schemas/payment.json`
- `models.dmacro` containing only `defFromJsonSchema("schemas/payment.json");`
- A short `README.md` showing the command and the generated `models.dart`.

This demo is the artifact that answers the product question. If watching a full typed
class fall out of a schema file with no build_runner is compelling, proceed to Phase 3.
If it feels underwhelming, stop and document — the project remains a strong exploration.

---

## Stretch (only if 2.1–2.3 land cleanly)

- `defFromOpenApi(path, "SchemaName")` — extract one named schema from an OpenAPI doc's
  `components/schemas`. Same type-mapping engine.
- `defAllFromJsonSchema("dir/")` — generate a class per `.json` in a directory.

Do **not** start the stretch items until 2.1–2.3 meet their acceptance criteria and are
committed.

---

## Phase 2 definition of done

- `expand` is async; all prior macros still pass their tests.
- `defFromJsonSchema` generates a class identical to the equivalent `defrecord`.
- `example/schema_demo/` exists and its README shows real input → real output.
- Emitted Dart is analyzer-clean and formatted.
- Decision recorded in `backlog/BACKLOG.md`: continue to Phase 3, or stop and document.
