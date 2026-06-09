# Changelog

## 0.3.0

### New features

- **User-definable macros in `.dmacro` syntax**: `defmacro name(params) { body }` now parses,
  registers, and expands as a template macro. Param names are substituted with call-site
  arguments throughout the body. Works in both `.dmacro` and `.sexp` formats.
- **`oneOf` → `defunion`**: JSON Schema / OpenAPI `oneOf` arrays are automatically mapped to
  sealed class hierarchies. Each variant must have a `title` or `$ref` for its name; required
  vs optional fields are preserved.
- **YAML OpenAPI support**: `defFromOpenApi` now accepts `.yaml` and `.yml` files in addition
  to `.json`. A built-in zero-dependency YAML parser handles block/flow mappings and sequences,
  quoted scalars, block scalars (`|`/`>`), and comments — the full subset needed for
  OpenAPI specs.

## 0.2.0

### Bug fixes

- **`withRetry`**: body now runs exactly once on success. Previously it ran N
  times regardless of outcome because the `for` loop had no `break` after the
  successful attempt.
- **`assertThat`**: `\` and `"` in the expression source are now escaped before
  embedding in the error string. Expressions containing string literals (e.g.
  `assertThat(email.contains("@"))`) previously generated invalid Dart.
- **`defunion`** variants now include `copyWith`, `==`, `hashCode`, and
  `toString` — matching what the README already claimed and what `defrecord`
  provides. The `==` check correctly uses the variant class name
  (`other is Circle`), not the sealed parent name.
- **`once`** macro: the temp variable now uses `gensym` instead of
  `_once_$name`, eliminating collisions when the same variable is bound twice.
- **`copyWith` with no fields**: emits `copyWith()` instead of `copyWith({})`
  (empty named-parameter block is invalid Dart).
- **`==` with no fields**: no longer emits a dangling `&&` for zero-field
  classes/variants.

### New features

- **`defFromJsonSchema` supports `$defs` / `definitions`**: schemas that
  declare local types in a `$defs` or `definitions` block now have those
  types generated before the main record. `$ref` fields pointing to `$defs`
  enums get enum-aware serialization automatically.
- **`trace` CLI command**: `dart run dmacro:dmacro trace <file>` prints each
  macro expansion step — useful for understanding what generated code
  corresponds to which macro call.

### Internal

- `genEnumSource()` shared helper eliminates the duplicated enum-generation
  string between the `defenum` macro and the `emit()` switch case.

## 0.1.0

Initial public release.

### Stable

- `defrecord` — generates a complete immutable data class: `const` constructor,
  `copyWith` (with explicit-null support via sentinel), structural `==`/`hashCode`,
  `toString`, `fromJson`, `toJson`. Zero non-SDK dependencies.
- `defunion` — generates a sealed class hierarchy (like Freezed union types).
- `defenum` — generates a Dart enum with `fromJson`/`toJson`; hand-authored
  `.dmacro` `defrecord` fields typed with a `defenum` name automatically receive
  enum-aware serialization.
- `unless`, `when`, `swap!`, `withRetry`, `assertThat` — control-flow macros.
- `.dmacro` source format — Dart-like syntax compiled to `.dart` by the CLI.
- `.sexp` source format — S-expression syntax for full Lisp-style macro power.
- CLI: `dart run dmacro:dmacro compile <file>`, `repl`, `watch`, `--check`.
- `dart pub global activate dmacro` installs the `dmacro` command.

### Experimental / preview

- `defFromJsonSchema` — generates a `defrecord` from a JSON Schema file at
  compile time (async macro; requires `dart:io`).
- `defFromOpenApi` — extracts a named schema from an OpenAPI `components/schemas`
  block.
- `defAllFromJsonSchema` — scans a directory and generates one record per `.json`
  file.
- VS Code extension (`vscode-ext/`) — compile-on-save, diagnostics, hot-reload
  wiring. Not yet published to the marketplace.

### Known limitations

- Parser does not support named constructors, initializer lists, traditional
  `for` loops, multiline string interpolation, `as`/`is` type checks, `switch`
  statements, or generics in function bodies. Use `.sexp` syntax for those cases.
- `defenum` must precede any `defrecord` that references it in the same file
  (no forward declaration).
- The `doc/` directory follows the pub.dev convention (renamed from `docs/` in 0.1.0).
- **Breakpoints and runtime stack traces** point to the generated `.dart` file, not the
  `.dmacro` source. The Dart VM has no mechanism to consume external source maps for
  JIT/AOT builds. Mitigations: (1) the VS Code extension shows a
  `↑ dmacro: file:line` code lens on every `@dmacro-origin` line in generated `.dart`
  files — click it to jump directly to the corresponding `.dmacro` source line;
  (2) `dart run dmacro:dmacro trace <file>` prints each macro expansion step so you
  can understand what generated code corresponds to which macro call.
