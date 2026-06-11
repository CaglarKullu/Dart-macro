# macro_library — sharing macros across projects

This example shows both distribution patterns side-by-side.

## Pattern A: Dart-function macros via an entry point

`tool/dmacro.dart` imports a hypothetical `team_macros` package (represented
here by `macros/team_macros.dart`) and registers its macros before handing
control to the dmacro CLI.

```bash
# From the project root — run against this example:
dart run tool/dmacro.dart compile example/macro_library/widgets.dmacro
```

## Pattern B: template macros via importMacros

`shared_templates.dmacro` contains reusable Tier-1/Tier-2 template macros.
Any `.dmacro` source file loads them with:

```dart
importMacros("example/macro_library/shared_templates.dmacro");
```

See `example/macro_library/app.dmacro` for a combined example that uses
both a Dart-function macro (`defwidget`) and imported template macros.
