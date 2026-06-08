# dart_macros

A compile-time macro preprocessor for Dart. No `build_runner`, no Flutter
constraints, no external dependencies — pure Dart SDK.

The Dart team [cancelled macros in January 2025](https://dart.dev/language/macros).
This project implements the same idea as a standalone CLI preprocessor.

---

## How it works

You annotate your classes. You run the tool. Generated code is injected
**directly into your source file**, wrapped in markers so it's idempotent
(safe to run repeatedly).

```
BEFORE                              AFTER
──────────────────────────────      ──────────────────────────────
@DataClass()                        @DataClass()
class Payment {                     class Payment {
  final double amount;                final double amount;
  final String currency;              final String currency;
  final String? reference;            final String? reference;
                                    
  const Payment({...});               const Payment({...});
}                                   
                                      // ━━━ dart_macros generated ━━━
                                      Payment copyWith({
                                        double? amount,
                                        String? currency,
                                        String? reference,
                                      }) { ... }
                                    
                                      @override
                                      bool operator ==(Object other) { ... }
                                    
                                      @override
                                      int get hashCode => Object.hash(...);
                                    
                                      @override
                                      String toString() => 'Payment(...)';
                                      // ━━━ end dart_macros ━━━
                                    }
```

---

## Available annotations

| Annotation     | Generates                                        |
|----------------|--------------------------------------------------|
| `@DataClass()` | `copyWith` · `==` · `hashCode` · `toString`      |
| `@Singleton()` | Private constructor · `_instance` · `getInstance()` |
| `@Logged()`    | `log(message)` · `logFields()` helpers           |

You can stack them:
```dart
@DataClass()
@Logged()
class ApiResponse { ... }
```

---

## Usage

```bash
# Apply macros in-place
dart run bin/dart_macros.dart build lib/

# Preview changes without writing
dart run bin/dart_macros.dart preview lib/

# Strip all generated blocks
dart run bin/dart_macros.dart clean lib/
```

---

## Adding your own macro

1. Add a class in `lib/src/generator.dart`:

```dart
class MyMacroGenerator extends MacroGenerator {
  @override
  final String annotationName = 'MyMacro';

  @override
  String generate(ClassInfo info) {
    // info.name     — class name
    // info.fields   — List<FieldInfo> (name, type, isFinal, isNullable)
    // info.annotations — List<String>
    return '''
  // your generated code here
  void myGeneratedMethod() {
    print('I was generated for \${info.name}');
  }''';
  }
}
```

2. Register it in the `macroRegistry` map at the bottom of `generator.dart`:

```dart
final Map<String, MacroGenerator> macroRegistry = {
  'DataClass': DataClassGenerator(),
  'Singleton': SingletonGenerator(),
  'Logged':    LoggedGenerator(),
  'MyMacro':  MyMacroGenerator(),  // add here
};
```

3. Run `dart run bin/dart_macros.dart build .`

---

## Why not build_runner?

`build_runner` requires:
- A separate `*.g.dart` file per source file
- Running `dart run build_runner build` after every change
- A full pub package to define a generator
- Separate annotation and generator packages

`dart_macros`:
- Injects code directly into your source file
- One command, no separate files
- Define a macro in 10 lines inside `generator.dart`
- Zero pub dependencies

The trade-off: `dart_macros` is a preprocessor, not a language feature.
It works on Dart source text, not a fully resolved AST. For complex cases
(custom generic type resolution, cross-file analysis), `build_runner` with
`package:analyzer` is more powerful.

---

## Project structure

```
dart_macros/
  bin/
    dart_macros.dart          CLI entry point
  lib/src/
    models.dart               FieldInfo, ClassInfo
    parser.dart               Dart source → ClassInfo (zero deps)
    generator.dart            MacroGenerator impls + registry
    transformer.dart          Applies generators, manages markers
  example/input/
    payment.dart              Example annotated input
  validate.py                 Logic validation (no Dart SDK needed)
  pubspec.yaml
```
