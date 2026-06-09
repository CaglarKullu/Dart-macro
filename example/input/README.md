# `input/` — annotations vs. the preprocessor, side by side

This folder shows the **same model** (`Payment`) written two ways:

| File | Approach | Status |
|------|----------|--------|
| [`annotation_style.dart`](annotation_style.dart) | `@DataClass` + in-place generated block (the `build_runner` / `freezed` shape) | **Frozen illustration** of the approach this project evaluated and **rejected** |
| [`preprocessor_style.dmacro`](preprocessor_style.dmacro) | `defrecord` → whole-file regeneration | **Live** — compile it with the CLI below |

```bash
dart run bin/dmacro.dart compile example/input/preprocessor_style.dmacro
# → writes example/input/preprocessor_style.dart
```

`annotation_style.dart` is a hand-frozen sample — there is no annotation tool in
this repo anymore. It defines its own marker annotation classes so it stays
analyzer-clean, and it shows what an in-place generated block looks like.

For the full reasoning — scored on evolution/effectiveness, usability, and
maintenance complexity — see
[`doc/ANNOTATIONS_VS_PREPROCESSOR.md`](../../doc/ANNOTATIONS_VS_PREPROCESSOR.md).

## The one-line summary

- **Annotations**: keep writing normal Dart classes, tag them, let a tool inject
  members. Low adoption friction, but generated code lives *inside* your file and
  the tool can only ever *append* to classes you already wrote — it cannot create
  a type from, say, a JSON schema.
- **Preprocessor (this project)**: write a compact declaration, get a complete
  analyzer-clean `.dart` file back. New file format, but no annotation
  boilerplate, no `*.g.dart`, and macros can run at compile time — including
  reading external files to synthesize types.
