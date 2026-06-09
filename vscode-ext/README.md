# dmacro VS Code Extension

Syntax highlighting, compile-on-save, diagnostics, and Flutter hot-reload for `.dmacro` and `.sexp` files.

## Install from source

```bash
cd vscode-ext
npm install
npm run package          # builds dmacro-0.1.0.vsix
code --install-extension dmacro-0.1.0.vsix
```

Or open VS Code → `Ctrl+Shift+P` → "Extensions: Install from VSIX…" → select `dmacro-0.1.0.vsix`.

## Features

| Feature | Detail |
|---------|--------|
| Syntax highlighting | `.dmacro` and `.sexp` files |
| Compile on save | Runs `dart run bin/dmacro.dart compile <file>` |
| Diagnostics | Parse/compile errors shown as squiggles at correct source location |
| Analyzer integration | `dart analyze` results mapped back to `.dmacro` source via `@dmacro-origin` |
| Flutter hot-reload | Fires after successful compile if a Flutter debug session is active |
| Command palette | `dmacro: Compile File`, `dmacro: Compile Workspace` |

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `dmacro.cliPath` | `""` | Explicit path to dmacro CLI (leave empty to use `dart run`) |
| `dmacro.formatOnCompile` | `true` | Run `dart format` on generated files |
| `dmacro.analyzeOnCompile` | `true` | Run `dart analyze` and show warnings in source |
| `dmacro.hotReloadOnCompile` | `true` | Flutter hot-reload after successful compile |
