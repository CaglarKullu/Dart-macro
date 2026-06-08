/**
 * dart_sexp VS Code Extension
 *
 * Compiles .dmacro and .sexp files on save, shows diagnostics at the correct
 * source location, and provides syntax highlighting.
 */
import * as vscode from 'vscode';
import * as cp from 'child_process';
import * as path from 'path';

const DIAGNOSTIC_SOURCE = 'dart_sexp';
const diagnostics = vscode.languages.createDiagnosticCollection(DIAGNOSTIC_SOURCE);

export function activate(context: vscode.ExtensionContext): void {
  // 5.1 — Compile on save
  context.subscriptions.push(
    vscode.workspace.onDidSaveTextDocument(doc => {
      if (isSexpFile(doc.fileName)) {
        compileFile(doc.fileName);
      }
    }),
  );

  // 5.4 — Command palette commands
  context.subscriptions.push(
    vscode.commands.registerCommand('dart-sexp.compileFile', () => {
      const editor = vscode.window.activeTextEditor;
      if (editor && isSexpFile(editor.document.fileName)) {
        compileFile(editor.document.fileName);
      }
    }),
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('dart-sexp.compileWorkspace', () => {
      const folder = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
      if (folder) compileDir(folder);
    }),
  );

  context.subscriptions.push(diagnostics);
}

export function deactivate(): void {
  diagnostics.dispose();
}

// ─── Helpers ──────────────────────────────────────────────────────────────────

function isSexpFile(filePath: string): boolean {
  return filePath.endsWith('.dmacro') || filePath.endsWith('.sexp');
}

/** Resolves the sexp CLI command. Prefer an explicit path from settings;
 *  fall back to `dart run bin/sexp.dart` relative to the workspace. */
function sexpCmd(workDir: string): { cmd: string; args: string[] } {
  const cfg = vscode.workspace.getConfiguration('dart-sexp');
  const explicit: string = cfg.get('sexpPath') ?? '';
  if (explicit) return { cmd: explicit, args: [] };

  // Use dart run bin/sexp.dart from the workspace root.
  return { cmd: 'dart', args: ['run', path.join(workDir, 'bin', 'sexp.dart')] };
}

function compileFile(filePath: string): void {
  const workDir = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath ?? path.dirname(filePath);
  const { cmd, args } = sexpCmd(workDir);
  const cfg = vscode.workspace.getConfiguration('dart-sexp');
  const doFormat: boolean = cfg.get('formatOnCompile') ?? true;

  const cliArgs = [
    ...args, 'compile', filePath,
    ...(doFormat ? [] : ['--no-format']),
  ];

  cp.execFile(cmd, cliArgs, { cwd: workDir }, (err, _stdout, stderr) => {
    diagnostics.set(vscode.Uri.file(filePath), []);   // clear old errors

    if (err) {
      const diag = parseDiagnostics(filePath, stderr || err.message);
      diagnostics.set(vscode.Uri.file(filePath), diag);
      updateStatusBar('✗ dart_sexp error');
    } else {
      updateStatusBar('✓ dart_sexp compiled');
    }
  });
}

function compileDir(dir: string): void {
  const { cmd, args } = sexpCmd(dir);
  cp.execFile(cmd, [...args, 'compile', dir], { cwd: dir }, (err, _stdout, stderr) => {
    if (err) {
      vscode.window.showErrorMessage(`dart_sexp: ${stderr || err.message}`);
    } else {
      vscode.window.showInformationMessage('dart_sexp: workspace compiled successfully');
    }
  });
}

// ─── 5.3 — Diagnostics ────────────────────────────────────────────────────────

/**
 * Parses CLI stderr for `file:line:col: message` errors and maps them to
 * VS Code Diagnostic objects so they appear as squiggles in the source.
 */
function parseDiagnostics(filePath: string, output: string): vscode.Diagnostic[] {
  const results: vscode.Diagnostic[] = [];

  // Match patterns like:  12:5: Expected ';' ...
  // Or: ParseException: 12:5: ...
  const lineColPattern = /(\d+):(\d+):\s*(.+)/g;
  let m: RegExpExecArray | null;

  while ((m = lineColPattern.exec(output)) !== null) {
    const line   = Math.max(0, parseInt(m[1], 10) - 1);
    const col    = Math.max(0, parseInt(m[2], 10) - 1);
    const msg    = m[3].trim();
    const range  = new vscode.Range(line, col, line, col + 1);
    results.push(new vscode.Diagnostic(range, msg, vscode.DiagnosticSeverity.Error));
  }

  if (results.length === 0 && output.trim()) {
    // No location info — show at line 0 so something is visible.
    results.push(new vscode.Diagnostic(
      new vscode.Range(0, 0, 0, 0),
      output.trim(),
      vscode.DiagnosticSeverity.Error,
    ));
  }

  return results;
}

// ─── 5.4 — Status bar ────────────────────────────────────────────────────────

let statusItem: vscode.StatusBarItem | undefined;

function updateStatusBar(text: string): void {
  if (!statusItem) {
    statusItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 0);
    statusItem.show();
  }
  statusItem.text = text;
  // Auto-clear success message after 3 s.
  if (text.startsWith('✓')) {
    setTimeout(() => { if (statusItem) statusItem.text = 'dart_sexp'; }, 3000);
  }
}
