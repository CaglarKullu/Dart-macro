# Writing your own macros

dmacro's product is not its built-in macros — it's that **you can write your
own**. A macro is one function:

```
(List<Node> args) → Node
```

`Node` is an atom (`String`, `int`, `double`, `bool`, `null`) or a
`List<Node>`. Your macro receives the call-site arguments as parsed structure,
returns new structure (or a plain Dart string), and the emitter writes it out.
Every built-in — `defrecord`, `defFromJsonSchema`, all of them — is written
with exactly the API described below. Nothing here is second-class.

## Setup (consumer project)

```yaml
# pubspec.yaml
dev_dependencies:
  dmacro:
    git: https://github.com/caglarkullu/dart-macro
```

Built-in macros work immediately, and so do your own — one command for both:

```bash
dart run dmacro compile lib/models.dmacro
```

To add your own Dart-function macros, write a plain Dart library that exposes
`void registerMacros()`, then load it from your `.dmacro` source with
`useMacros` — right where you use it, no entry point:

```dart
// lib/my_macros.dart
import 'package:dmacro/dmacro.dart';

void registerMacros() {
  // your macros go here — defmacro / defAsyncMacro
}
```

```dart
// lib/widgets.dmacro
useMacros("lib/my_macros.dart");      // or "package:my_macros/macros.dart"

// ...your macros are now available here, like builtins
```

```bash
dart run dmacro compile lib/widgets.dmacro   # full CLI, your macros loaded
dart run dmacro compile lib/ --check         # CI staleness gate
dart run dmacro watch lib/                    # recompile on save
```

`useMacros` runs the library in a worker isolate at generation time and
registers each macro it exposes, so they compose with the standard library and
each other transparently. Registering a name that already exists overrides it,
so you can even replace a built-in.

> **Prefer registering in code?** The classic entry-point pattern still works:
> write `tool/dmacro.dart` with
> `void main(args) => runDmacro(args, registerMacros: () { … });`
> and run `dart run tool/dmacro.dart`. `useMacros` simply means you rarely need
> it. (If you do use a root file, name it `tool/dmacro.dart`, not a root
> `build.dart` — Dart treats a root `build.dart` as a native-assets hook.)

## Tier 1 — template macros (no Dart needed)

For pure substitution, define macros directly in your `.dmacro` source:

```dart
defmacro guard(cond, err) {
  unless (cond) { throw Exception(err); }
}

bool createUser(String email) {
  guard(email.contains("@"), "Invalid email");
  return true;
}
```

Call-site arguments substitute for parameter names. For iteration, see Tier 2
(`$map`); for anything else — branching on structure, I/O, string building —
go to Tier 3.

## Tier 2 — `$map`: templates that iterate

A template macro can repeat a piece of itself once per argument. Two parts:

**Rest params** — a trailing `...rest` parameter collects all remaining call
arguments into a list:

```dart
defmacro logAll(...vals) {
  $map(vals, v) { print(v); }
}

void main() {
  logAll(user, request, response);
  // → print(user); print(request); print(response);
}
```

**`$map(items, binder…, template)`** — expands the template once per item and
splices the results into wherever the macro was called. With *multiple*
binders, each element is destructured positionally — which is exactly the
shape block-syntax fields arrive in (`[type, name]` pairs):

```dart
defmacro defChecks(name, ...fields) {
  $map(fields, t, n) {
    validate(t, n);
  }
}

defChecks Config {
  String host;
  int port;
}
// → validate(String, host); validate(int, port);
```

The template may call other macros (built-in or yours) — expansion keeps
going. `$map` calls can nest; inner results flatten into the outer splice.

Limits (by design — past these, use Tier 3):

- Substitution is whole-atom: a binder named `v` is **not** visible inside
  string literals (`"value: v"` stays literal).
- Pick binder names that don't collide with the enclosing macro's params —
  outer substitution runs first and will capture them.
- The template must be valid `.dmacro` statement syntax; you can't generate
  arbitrary text. Generating whole classes from data is Tier-3 territory.

## Tier 3 — Dart-function macros (full power)

> Anything a template can't express is written as a Dart function. That's not
> a downgrade — it's the same power the built-ins have.

A Tier-3 macro library is a plain Dart file with a `void registerMacros()`
function. You load it with `useMacros("…")` from any `.dmacro` source. Examples
below show the body of that function.

### A sync macro: structure in, structure out

```dart
// lib/macros.dart  → load with useMacros("lib/macros.dart")
void registerMacros() {
  // guarded(x > 0, "bad") → if (!(x > 0)) { throw Exception('bad'); }
  defmacro('guarded', (args) {
    return ['unless', args[0], ['throw', ['Exception', args[1]]]];
  });
}
```

Key things to notice:

- `args[0]` is the parsed condition — `['>', 'x', 0]`, not the string `"x > 0"`.
  You can inspect it, rewrite it, wrap it.
- Returning a list that *contains another macro call* (`unless`) is fine — the
  expander keeps expanding until no macros remain. Your macros compose with
  built-ins and with each other, **even across the `useMacros` isolate
  boundary**: the worker returns raw structure and the parent keeps expanding.

### An async macro: I/O at generation time

```dart
void registerMacros() {
  defAsyncMacro('defFromCsvHeader', (args) async {
    final path = unquote(args[0] as String);
    final header = (await File(path).readAsLines()).first;
    final fields = header.split(',');
    final decls = fields.map((f) => '  final String $f;').join('\n');
    return 'class Row {\n$decls\n}';
  });
}
```

Anything `await`-able is allowed: file reads, HTTP, database queries. This is
the capability the cancelled official Dart macros could not offer and
`build_runner` builders make painful — here it is one function.

### The argument shapes you'll actually see

| You write | Your macro receives |
|---|---|
| `m(foo)` | `'foo'` (bare identifier as `String`) |
| `m("foo")` | `'"foo"'` — **quotes included**; strip with `unquote(...)` |
| `m(42)`, `m(3.14)` | `42`, `3.14` (real numbers) |
| `m(x > 0)` | `['>', 'x', 0]` |
| `m(f(a, b))` | `['f', 'a', 'b']` |

`unquote` is exported from `package:dmacro/dmacro.dart`. It is a no-op on
anything that isn't a quoted string, so calling it unconditionally is safe.

### Returning code

Two equivalent options:

1. **Return a `String` of Dart source** — easiest for whole declarations
   (classes, functions). The emitter passes it through verbatim.
2. **Return a `Node` tree** — best for expression/statement transforms that
   must compose with further expansion (like `guarded` above).

For generated temporary variables use `gensym('tmp')` — it returns a unique
name per compilation, so your macro can never collide with the caller's
variables.

### Errors

Throw any exception with a clear message; the CLI reports it against the
source file. (`ArgumentError('defwidget: expected a name')` reads better than
an index-out-of-range three frames deep.)

## Current limitations (honest list)

- **String args keep their quotes** — `m("Foo")` arrives as `'"Foo"'`; strip
  with `unquote(arg as String)`.
- **`$map` substitution is whole-atom** — a binder named `v` replaces the
  bare identifier `v` everywhere in the template, but is *not* expanded inside
  string literals (`"value: v"` stays literal).
- **Template binder capture** — if a binder name matches a param of an outer
  template macro, the outer substitution runs first and captures it. Pick
  distinct names.
- **`throw` in argument position** — `m(throw Exception("x"))` emits bare
  `throw;`. Build the throw node inside the macro instead (see `guarded`).
- **Two directives, two file kinds** — `importMacros` loads template macros
  from `.dmacro`/`.sexp` files; `useMacros` loads Dart-function macros from
  `.dart` files. Use the one that matches the macro tier.
- **`useMacros` reloads on a per-run basis** — a worker isolate is spawned once
  per library and reused for the whole compile. In `watch` mode, editing a
  loaded `.dart` macro library requires restarting the watcher (the source
  `.dmacro` is still re-read on every save as usual).

## Sharing macros within a project

**Template macros (Tier 1/2)** — factor them into a shared `.dmacro` file and
load with `importMacros`:

```dart
// lib/macros/validators.dmacro
defmacro requireNonEmpty(val, msg) {
  unless (val.isNotEmpty) { throw Exception(msg); }
}
```

```dart
// lib/models.dmacro
importMacros("lib/macros/validators.dmacro");

bool createUser(String email) {
  requireNonEmpty(email, "email required");
  return true;
}
```

**Dart-function macros (Tier 3)** — factor them into a `.dart` library with a
`registerMacros()` function and load with `useMacros`:

```dart
// lib/macros/models.dart
import 'package:dmacro/dmacro.dart';
void registerMacros() {
  defAsyncMacro('defmodel', (args) async => /* … */ '');
}
```

```dart
// lib/models.dmacro
useMacros("lib/macros/models.dart");
defmodel User { String id; String name; }
```

Both directives accept `package:` URIs, resolved via
`.dart_tool/package_config.json` (written by `dart pub get`) — so a macro
package shared across projects is loaded with a single line, no entry point:

```dart
useMacros("package:team_macros/macros.dart");
importMacros("package:team_macros/templates.dmacro");
```
