/**
 * dmacro VS Code Extension
 *
 * Compiles .dmacro and .sexp files on save, shows diagnostics at the correct
 * source location, provides syntax highlighting, triggers Flutter hot-reload,
 * and surfaces dart-analyze warnings mapped back to the .dmacro source.
 */
import * as vscode from 'vscode';
import * as cp from 'child_process';
import * as path from 'path';
import * as fs from 'fs';

const DIAGNOSTIC_SOURCE = 'dmacro';
const diagnostics = vscode.languages.createDiagnosticCollection(DIAGNOSTIC_SOURCE);

export function activate(context: vscode.ExtensionContext): void {
  // 5.1 — Compile on save
  context.subscriptions.push(
    vscode.workspace.onDidSaveTextDocument(doc => {
      if (isDmacroFile(doc.fileName)) {
        compileFile(doc.fileName);
      }
    }),
  );

  // 5.4 — Command palette commands
  context.subscriptions.push(
    vscode.commands.registerCommand('dmacro.compileFile', () => {
      const editor = vscode.window.activeTextEditor;
      if (editor && isDmacroFile(editor.document.fileName)) {
        compileFile(editor.document.fileName);
      }
    }),
  );

  context.subscriptions.push(
    vscode.commands.registerCommand('dmacro.compileWorkspace', () => {
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

function isDmacroFile(filePath: string): boolean {
  return filePath.endsWith('.dmacro') || filePath.endsWith('.sexp');
}

/** Resolves the dmacro CLI command. Prefer an explicit path from settings;
 *  fall back to `dart run bin/dmacro.dart` relative to the workspace. */
function dmacroCmd(workDir: string): { cmd: string; args: string[] } {
  const cfg = vscode.workspace.getConfiguration('dmacro');
  const explicit: string = cfg.get('cliPath') ?? '';
  if (explicit) return { cmd: explicit, args: [] };

  // Use dart run bin/dmacro.dart from the workspace root.
  return { cmd: 'dart', args: ['run', path.join(workDir, 'bin', 'dmacro.dart')] };
}

function compileFile(filePath: string): void {
  const workDir = vscode.workspace.workspaceFolders?.[0]?.uri.fsPath ?? path.dirname(filePath);
  const { cmd, args } = dmacroCmd(workDir);
  const cfg = vscode.workspace.getConfiguration('dmacro');
  const doFormat: boolean      = cfg.get('formatOnCompile') ?? true;
  const doAnalyze: boolean     = cfg.get('analyzeOnCompile') ?? true;
  const doHotReload: boolean   = cfg.get('hotReloadOnCompile') ?? true;

  const cliArgs = [
    ...args, 'compile', filePath,
    ...(doFormat ? [] : ['--no-format']),
  ];

  cp.execFile(cmd, cliArgs, { cwd: workDir }, (err, _stdout, stderr) => {
    diagnostics.set(vscode.Uri.file(filePath), []);   // clear old compile errors

    if (err) {
      const diag = parseDiagnostics(filePath, stderr || err.message);
      diagnostics.set(vscode.Uri.file(filePath), diag);
      updateStatusBar('✗ dmacro error');
      return;
    }

    updateStatusBar('✓ dmacro compiled');

    // 5.5 — Trigger Flutter hot-reload if a Flutter/Dart debug session is active.
    if (doHotReload) {
      const session = vscode.debug.activeDebugSession;
      if (session?.type === 'dart') {
        vscode.commands.executeCommand('flutter.hotReload').then(
          undefined,
          () => { /* Flutter extension not available — ignore */ },
        );
      }
    }

    // 5.6 — Run dart analyze on the generated .dart and map errors back.
    if (doAnalyze) {
      const outPath = filePath.replace(/\.(dmacro|sexp)$/, '.dart');
      runAnalyzerAndShowDiagnostics(filePath, outPath);
    }
  });
}

function compileDir(dir: string): void {
  const { cmd, args } = dmacroCmd(dir);
  cp.execFile(cmd, [...args, 'compile', dir], { cwd: dir }, (err, _stdout, stderr) => {
    if (err) {
      vscode.window.showErrorMessage(`dmacro: ${stderr || err.message}`);
    } else {
      vscode.window.showInformationMessage('dmacro: workspace compiled successfully');
    }
  });
}

// ─── 5.5 / 5.6 — Analyzer integration ────────────────────────────────────────

/** @dmacro-origin comment pattern in generated .dart files */
const ORIGIN_RE = /\/\/ @dmacro-origin: (.+):(\d+)/;

/**
 * Reads the generated .dart file, builds a line-number → source-location map
 * from embedded `@dmacro-origin` comments, then runs `dart analyze --format json`
 * and surfaces any warnings/errors as VS Code diagnostics on the source .dmacro file.
 */
function runAnalyzerAndShowDiagnostics(
  sourcePath: string,
  dartPath: string,
): void {
  if (!fs.existsSync(dartPath)) return;

  // Build origin map: dart line → { file, srcLine }
  const origins: Array<{ dartLine: number; file: string; srcLine: number }> = [];
  try {
    const content = fs.readFileSync(dartPath, 'utf8');
    content.split('\n').forEach((text, idx) => {
      const m = ORIGIN_RE.exec(text);
      if (m) origins.push({ dartLine: idx + 1, file: m[1], srcLine: parseInt(m[2], 10) });
    });
  } catch { /* can't read generated file — skip */ }

  cp.execFile('dart', ['analyze', '--format', 'json', dartPath], (err, stdout) => {
    // Clear previous analyzer diagnostics on the source file.
    const analyzerDiags: vscode.Diagnostic[] = [];

    let json: { diagnostics?: AnalyzerDiagnostic[] } | undefined;
    try { json = JSON.parse(stdout); } catch { return; }
    if (!json?.diagnostics?.length) return;

    for (const d of json.diagnostics) {
      const dartLine = (d.location?.range?.start?.line ?? 0) + 1; // JSON is 0-based

      // Map generated dart line → closest origin comment before it.
      let srcLine = 0;
      for (const o of origins) {
        if (o.dartLine <= dartLine) srcLine = o.srcLine - 1; // VS Code is 0-based
        else break;
      }

      const severity = d.severity === 'ERROR'
        ? vscode.DiagnosticSeverity.Error
        : d.severity === 'WARNING'
          ? vscode.DiagnosticSeverity.Warning
          : vscode.DiagnosticSeverity.Information;

      const range = new vscode.Range(srcLine, 0, srcLine, 999);
      const msg   = `[analyzer] ${d.problemMessage}`;
      const diag  = new vscode.Diagnostic(range, msg, severity);
      diag.source = 'dmacro/dart-analyze';
      analyzerDiags.push(diag);
    }

    if (analyzerDiags.length > 0) {
      diagnostics.set(vscode.Uri.file(sourcePath), analyzerDiags);
    }
  });
}

interface AnalyzerDiagnostic {
  severity: string;
  problemMessage: string;
  location?: {
    range?: {
      start?: { line?: number; character?: number };
    };
  };
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
    setTimeout(() => { if (statusItem) statusItem.text = 'dmacro'; }, 3000);
  }
}
