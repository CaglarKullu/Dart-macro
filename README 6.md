# Reference Implementation

This folder contains the **validated** code the specs are built on. It is ground truth —
when a spec and this code disagree about current behaviour, the code wins (and the spec
should be corrected).

## `dart/` — the validated Dart engine (Phase 0)

The working engine, already ported from the validated Python logic:

- `core.dart` — `Node`, `expand`, `emit`
- `reader.dart` — S-expression front-end
- `tokenizer.dart` + `dart_parser.dart` — Dart-like (`.dmacro`) front-end
- `nodes.dart` — typed constructor API (`$if`, `$not`, …)
- `builtins.dart` — standard macros
- `sexp.dart` — CLI (`compile`, `repl`)

**First implementation step:** drop these into a fresh `dart create` package under
`lib/src/` and `bin/`, add a `pubspec.yaml`, and confirm they compile and reproduce
`docs/VALIDATED_LOGIC.md`. Then write the Phase 0 tests listed in the backlog before
starting Phase 1.

> These files were authored and validated outside a Dart toolchain (logic proven in
> Python, then translated). Expect to run `dart format` and `dart analyze` and fix any
> minor analyzer nits on first compile — the *logic* is validated, the *lint-cleanliness*
> is not yet.

## `validation/` — the Python ground truth

`dart_parser_validate.py` is the end-to-end reference: tokenizer → parser → expander →
emitter, with the demo program and its expected Dart output. Run it to see the exact
intended behaviour:

```bash
python3 validation/dart_parser_validate.py
```

If you change expansion or emission semantics in Dart, update this validator in lockstep
so it remains an executable spec.

## `examples/`

- `payment.dmacro` — Dart-like syntax sample
- `payment.sexp` — equivalent S-expression sample

Both should compile to equivalent Dart, demonstrating the "two front-ends, one AST"
invariant.
