# Changelog

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
- CLI: `dart run dart_macros:dmacro compile <file>`, `repl`, `watch`, `--check`.
- `dart pub global activate dart_macros` installs the `dmacro` command.

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
- The `docs/` directory is named contrary to the pub.dev `doc/` convention;
  this will be corrected in a future release.
