# Vision — dmacro is a kit for writing Dart code generators

> This document supersedes the original "schema → types, no build_runner" framing
> as the project's north star. That capability still exists and still matters — but
> it is now positioned as **one example of what the kit can do**, not the product.

## The one sentence

**dmacro lets any Dart developer write their own code generator — in their own
project, in minutes, with no package to publish and no `build_runner` to learn.**

## Why this is the real product

A macro is a function from code to code. That is the entire idea, and it is
general. The mistake in the original framing was shipping a *fixed menu* of
generators (`defrecord`, `defunion`, `defFromJsonSchema`) and calling those the
product. They are not the product. They are **demos**. The product is the thing
that made them easy to write: a small, well-defined contract —

```
macro: (List<Node> args) → Node
```

— plus a pipeline that reads source as data, runs macros over it, and emits clean
Dart. Everything `defrecord` does, a user should be able to do for *their own*
boilerplate: their theme extension, their BLoC wiring, their Firestore adapters,
their widget shells, their company's house style. We don't have to anticipate
those. We have to make them writable.

## The competitive truth

| | freezed / json_serializable | dmacro |
|---|---|---|
| Who decides what gets generated | The package author | **You** |
| To make a *new* kind of generator | Fork or file an issue | Write a macro in your repo |
| Tooling to learn | `build_runner`, `build.yaml`, `Builder`/`BuildStep`, publish a package | one function: `(args) → Node` |
| Where the generator lives | A separate published package | Next to the code it generates |

freezed is a *better class*. dmacro is a *better way to write any freezed*. If we
win, we don't beat freezed on freezed's turf — we make "write your own freezed in
an afternoon" the normal thing to do.

## The gap we must close (the whole game)

There are two macro-authoring paths today and they don't connect:

1. **Template macros** — `defmacro name(params) { body }` written directly in a
   `.dmacro` file. Pure substitution. Zero tooling to write. But they cannot loop,
   inspect node structure, branch on field types, or do I/O. They are the easy
   80% case (wrap this in that, rename, compose existing macros).

2. **Dart-function macros** — `defMacro(name, (args) => …)` / `defAsyncMacro`.
   Full power: real Dart, full control flow, I/O. This is how every built-in is
   built. **But today only the built-ins use it.** A user cannot register one
   without editing this repository.

The general-purpose promise is empty until a user can write path 2 **in their own
project**. Closing that gap — loadable, user-authored Dart-function macros — is
the headline work (see `specs/phase-10-macro-authoring.md`). Everything else is
secondary.

## What "reuse the code" means concretely

Nothing in the engine gets thrown away. The pivot is framing + one new capability:

- **Keep:** `core.dart` (expand/emit), reader, tokenizer, `dart_parser.dart`,
  `async_expand.dart`, `gensym`, `$splice`, the CLI pipeline. All of it.
- **Reframe:** `builtins.dart` and `schema_macros.dart` become the **standard
  library** — clearly labeled "these are macros written with the public API; you
  can write your own the same way."
- **Add:** a supported way to load user-authored Dart-function macros at compile
  time, and the authoring DX (errors that point at the macro, not the downstream
  Dart) that makes writing them tolerable.

## What does not change

- Still a preprocessor. Still outside the compiler. Still regenerates files.
- Still zero runtime dependencies in generated output.
- Still `(List<Node>) → Node` as the one contract.
- The schema/OpenAPI macros still ship — as the flagship examples in the standard
  library, not as the reason the project exists.
