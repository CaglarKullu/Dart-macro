# dmacro VS Code Extension

Syntax highlighting, compile-on-save, diagnostics, and Flutter hot-reload for `.dmacro` and `.sexp` files. See macro expansions inline without leaving the editor.

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
| Compile on save | Runs `dart run bin/dmacro.dart compile <file>` automatically on save |
| Diagnostics | Parse/compile errors shown as red squiggles at correct source location |
| Analyzer integration | `dart analyze` results mapped back to `.dmacro` source via `@dmacro-origin` comments |
| Flutter hot-reload | Fires 500 ms after successful compile if a Flutter debug session is active |
| Expand macro at cursor | Right-click or use command palette to see full macro expansion in a side panel |
| Code lens | "↑ dmacro: file:line" links on generated `.dart` files jump back to source |
| Command palette | `dmacro: Compile File`, `dmacro: Compile Workspace`, `dmacro: Expand Macro at Cursor` |

## Commands

**dmacro: Compile File** — Compile the active `.dmacro` or `.sexp` file. Results appear in the integrated terminal.

**dmacro: Compile Workspace** — Compile all `.dmacro`, `.sexp`, and inline-block `.dart` files in the workspace.

**dmacro: Expand Macro at Cursor** — Run `dmacro trace` on the active file and show the full expansion tree in a read-only Dart document in a side panel. Useful for understanding what a macro produces without opening the generated `.dart` file.

## Settings

| Setting | Default | Description |
|---------|---------|-------------|
| `dmacro.cliPath` | `""` | Explicit path to dmacro CLI (leave empty to use `dart run bin/dmacro.dart`) |
| `dmacro.formatOnCompile` | `true` | Run `dart format` on generated files |
| `dmacro.analyzeOnCompile` | `true` | Run `dart analyze` after compile and show warnings/errors in source |
| `dmacro.hotReloadOnCompile` | `true` | Flutter hot-reload after successful compile (requires active Flutter debug session) |
