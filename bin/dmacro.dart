/// dmacro compiler CLI
///
/// Supports three source formats:
///   .sexp   — S-expression syntax  (Lisp-style)
///   .dmacro — Dart-like syntax     (looks like Dart)
///   .dart   — Regular Dart with embedded // @@dmacro ... // @@end blocks
///
/// Both .sexp and .dmacro compile to a sibling .dart file.
/// .dart files with @@dmacro blocks are updated in-place.
///
/// Usage:
///   dart run bin/dmacro.dart compile <file|dir>         — print/write Dart
///   dart run bin/dmacro.dart compile <file> -o out.dart — write to specific file
///   dart run bin/dmacro.dart compile <dir> --check      — CI staleness check
///   dart run bin/dmacro.dart watch <path>               — watch and recompile
///   dart run bin/dmacro.dart repl                       — interactive REPL
library;

import 'dart:async';
import 'dart:io';

import 'package:dmacro/src/builtins.dart';
import 'package:dmacro/src/core.dart' show MacroExpansionError;
import 'package:dmacro/src/dep_graph.dart' show depGraph;
import 'package:dmacro/src/gen_cache.dart' as gc
    show
        clearGenerationInputs,
        computeFingerprint,
        currentSourceFile,
        generationInputFiles,
        isCurrent,
        storedGenerationInputs,
        storedImports,
        updateCache;
import 'package:dmacro/src/schema_macros.dart';
import 'package:dmacro/src/async_expand.dart'
    show
        asyncCompile,
        asyncCompileDartLike,
        asyncCompileDartLikeWithOrigins,
        asyncCompileDartLikeWithTrace,
        asyncCompileWithOrigins,
        asyncCompileWithTrace;
import 'dart:convert' show jsonDecode;

/// Marker that starts an inline dmacro block in a .dart file.
const _blockStart = '// @@dmacro';

/// Marker that separates macro source (commented out) from generated code.
const _blockGenerated = '// @@generated';

/// Marker that ends an inline dmacro block.
const _blockEnd = '// @@end';

void main(List<String> args) async {
  registerBuiltins();
  registerSchemaMacros();

  if (args.isEmpty || args.first == 'help') {
    _usage();
    return;
  }

  switch (args.first) {
    case 'compile':
      await _compileCmd(args.sublist(1));
    case 'watch':
      await _watchCmd(args.sublist(1));
    case 'repl':
      await _repl();
    case 'trace':
      await _traceCmd(args.sublist(1));
    default:
      stderr.writeln('Unknown command: ${args.first}');
      _usage();
      exit(1);
  }
}

// ─── compile command ──────────────────────────────────────────────────────────

Future<void> _compileCmd(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
        'Usage: dmacro compile <file|dir> [-o output] [--check] [--no-format] [--field-origins]');
    exit(1);
  }

  String? outputPath;
  bool checkMode = false;
  bool doFormat = true;
  bool fieldOrigins = false;

  final positional = <String>[];
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '-o' && i + 1 < args.length) {
      outputPath = args[++i];
    } else if (args[i] == '--check') {
      checkMode = true;
    } else if (args[i] == '--no-format') {
      doFormat = false;
    } else if (args[i] == '--field-origins') {
      fieldOrigins = true;
    } else {
      positional.add(args[i]);
    }
  }

  final target = positional.first;
  final entity = FileSystemEntity.typeSync(target);

  if (entity == FileSystemEntityType.directory) {
    await _compileDir(target,
        checkMode: checkMode, doFormat: doFormat, fieldOrigins: fieldOrigins);
  } else if (entity == FileSystemEntityType.file) {
    if (target.endsWith('.dart')) {
      // Inline @@dmacro block mode: expand blocks inside an existing .dart file.
      final stale = await _compileDartInline(target,
          checkMode: checkMode, doFormat: doFormat);
      if (checkMode && stale) {
        stderr.writeln('STALE');
        exit(1);
      }
    } else {
      final stale = await _compileSingle(target,
          outputPath: outputPath,
          checkMode: checkMode,
          doFormat: doFormat,
          fieldOrigins: fieldOrigins);
      if (checkMode && stale) {
        stderr.writeln('STALE');
        exit(1);
      }
    }
  } else {
    stderr.writeln('Error: $target does not exist');
    exit(1);
  }
}

Future<void> _compileDir(String dir,
    {bool checkMode = false,
    bool doFormat = true,
    bool fieldOrigins = false}) async {
  final allFiles = Directory(dir).listSync(recursive: true).whereType<File>();

  final macroSources = allFiles
      .where((f) => f.path.endsWith('.dmacro') || f.path.endsWith('.sexp'))
      .toList();

  final inlineDartFiles = allFiles
      .where((f) =>
          f.path.endsWith('.dart') &&
          f.readAsStringSync().contains(_blockStart))
      .toList();

  if (macroSources.isEmpty && inlineDartFiles.isEmpty) {
    stderr.writeln('No .dmacro, .sexp, or inline-block .dart files found under $dir');
    return;
  }

  var stale = 0;
  for (final file in macroSources) {
    final outPath = _outputPath(file.path);
    final wasStale = await _compileSingle(file.path,
        outputPath: outPath,
        checkMode: checkMode,
        doFormat: doFormat,
        fieldOrigins: fieldOrigins);
    if (wasStale) stale++;
  }

  for (final file in inlineDartFiles) {
    final wasStale = await _compileDartInline(file.path,
        checkMode: checkMode, doFormat: doFormat);
    if (wasStale) stale++;
  }

  if (checkMode) {
    if (stale > 0) {
      stderr.writeln('$stale file(s) out of date');
      exit(1);
    } else {
      stderr.writeln('All outputs up to date');
    }
  }
}

/// Compiles one file. Returns true if the file was stale (only relevant in
/// check mode).
Future<bool> _compileSingle(String inputPath,
    {String? outputPath,
    bool checkMode = false,
    bool doFormat = true,
    bool fieldOrigins = false}) async {
  final source = await File(inputPath).readAsString();
  final absInputPath = File(inputPath).absolute.path;
  final outFile = outputPath ?? _outputPath(inputPath);

  // Per-file gen-cache state: track which extra files are read during expansion.
  gc.clearGenerationInputs();
  gc.currentSourceFile = absInputPath;
  depGraph.clearSource(absInputPath);

  // Skip recompilation when source and all generation-time inputs are unchanged.
  // Use previously stored imports (dep graph is in-memory only — doesn't
  // persist across CLI runs).
  if (!checkMode && File(outFile).existsSync()) {
    final prevImports = gc.storedImports(absInputPath);
    final prevGenInputs = gc.storedGenerationInputs(absInputPath);
    final fp = gc.computeFingerprint(source, prevImports, prevGenInputs);
    if (gc.isCurrent(absInputPath, fp)) {
      stderr.writeln('↷ $inputPath (unchanged)');
      return false;
    }
  }

  String dart;

  try {
    // Origin-tracking variants embed `// @dmacro-origin: file:line` markers so
    // post-compile analyzer errors can be mapped back to source positions.
    dart = inputPath.endsWith('.dmacro')
        ? await asyncCompileDartLikeWithOrigins(source, inputPath,
            fieldOrigins: fieldOrigins)
        : await asyncCompileWithOrigins(source, inputPath,
            fieldOrigins: fieldOrigins);
  } catch (e) {
    // MacroExpansionError already contains "file:line: message" — print as-is.
    // Other exceptions (ParseException, TokenizerException) need the input path
    // prepended, and we strip their verbose class-name prefix.
    if (e is MacroExpansionError) {
      stderr.writeln(e);
    } else {
      stderr.writeln('$inputPath: ${_stripExceptionPrefix(e)}');
    }
    exit(1);
  }

  if (doFormat) dart = _format(dart);

  final header = '// Generated by dmacro from $inputPath\n'
      '// Do not edit — edit the source file instead.\n\n';
  final output = header + dart;

  if (checkMode) {
    // Just check whether the on-disk file matches; don't write.
    final exists = File(outFile).existsSync();
    if (!exists || File(outFile).readAsStringSync() != output) {
      stderr.writeln('STALE: $outFile');
      return true;
    }
    return false;
  }

  if (outputPath != null) {
    await File(outFile).writeAsString(output);
    stderr.writeln('✓ $inputPath → $outFile');
  } else if (File(inputPath).parent.path.isNotEmpty) {
    // No explicit output — derive sibling .dart file and write it.
    await File(outFile).writeAsString(output);
    stderr.writeln('✓ $inputPath → $outFile');
  } else {
    print(output);
  }

  // Persist fingerprint so the next run can skip recompilation.
  final newImports = depGraph.importsOf(absInputPath);
  final newGenInputs = List<String>.from(gc.generationInputFiles);
  final newFp = gc.computeFingerprint(source, newImports, newGenInputs);
  gc.updateCache(absInputPath, newFp, newGenInputs, newImports);

  return false;
}

/// Derives the output .dart path from a source path.
String _outputPath(String srcPath) =>
    srcPath.replaceFirst(RegExp(r'\.(dmacro|sexp)$'), '.dart');

// ─── Inline .dart block processing ───────────────────────────────────────────

/// Processes a `.dart` file containing `// @@dmacro` / `// @@end` inline
/// blocks, expands each block in-place, and writes the result back.
///
/// Block format — initial (user writes this):
/// ```
/// // @@dmacro
/// defrecord Product {
///   String id;
/// }
/// // @@end
/// ```
///
/// Block format after first expansion (file stays analyzer-clean):
/// ```
/// // @@dmacro
/// // defrecord Product {
/// //   String id;
/// // }
/// // @@generated
/// class Product { ... }
/// // @@end
/// ```
///
/// Returns true if the file was stale (only meaningful in [checkMode]).
Future<bool> _compileDartInline(String dartPath,
    {bool checkMode = false, bool doFormat = true}) async {
  final original = await File(dartPath).readAsString();

  if (!original.contains(_blockStart)) {
    stderr.writeln('$dartPath: no // @@dmacro blocks found');
    return false;
  }

  String updated;
  try {
    updated = await _processInlineBlocks(original, dartPath);
  } catch (e) {
    if (e is MacroExpansionError) {
      stderr.writeln(e);
    } else {
      stderr.writeln('$dartPath: ${_stripExceptionPrefix(e)}');
    }
    exit(1);
  }

  // Normalize both sides under the same formatter so re-running an already-
  // expanded file doesn't produce a false "stale" result.
  if (doFormat) updated = _format(updated);

  if (checkMode) {
    if (original != updated) {
      stderr.writeln('STALE: $dartPath');
      return true;
    }
    return false;
  }

  if (original != updated) {
    await File(dartPath).writeAsString(updated);
    stderr.writeln('✓ $dartPath (inline blocks expanded)');
  } else {
    stderr.writeln('✓ $dartPath (no changes)');
  }
  return false;
}

/// Finds all `// @@dmacro` / `// @@end` blocks in [source], expands each, and
/// returns the modified source with generated code inserted between
/// `// @@generated` and `// @@end`.
Future<String> _processInlineBlocks(String source, String sourcePath) async {
  final buffer = StringBuffer();
  // Matches from // @@dmacro (at start of a line) through // @@end (at start
  // of a line), capturing everything in between.
  final blockRe = RegExp(
    r'^// @@dmacro\n(.*?)\n// @@end',
    dotAll: true,
    multiLine: true,
  );

  var lastEnd = 0;
  for (final match in blockRe.allMatches(source)) {
    // Text before this block — copy verbatim.
    buffer.write(source.substring(lastEnd, match.start));

    final blockContent = match.group(1)!;
    String macroSource;

    if (blockContent.contains('\n$_blockGenerated\n') ||
        blockContent.startsWith('$_blockGenerated\n')) {
      // Regeneration mode: macro source is commented out above @@generated.
      final genMarker = blockContent.contains('\n$_blockGenerated\n')
          ? '\n$_blockGenerated\n'
          : '$_blockGenerated\n';
      final sourceSection =
          blockContent.substring(0, blockContent.indexOf(genMarker));
      macroSource = sourceSection
          .split('\n')
          .map((l) => l.startsWith('// ') ? l.substring(3) : l)
          .join('\n');
    } else {
      // Fresh block: everything between @@dmacro and @@end is macro source.
      macroSource = blockContent;
    }

    // Expand the macro source.
    final expanded = await asyncCompileDartLike(macroSource.trim());

    // Emit: commented source above @@generated, generated code below.
    final commentedLines = macroSource
        .trimRight()
        .split('\n')
        .map((l) => l.isEmpty ? '//' : '// $l')
        .join('\n');

    buffer
      ..write('$_blockStart\n')
      ..write(commentedLines)
      ..write('\n$_blockGenerated\n')
      ..write(expanded.trim())
      ..write('\n$_blockEnd');

    lastEnd = match.end;
  }

  buffer.write(source.substring(lastEnd));
  return buffer.toString();
}

// ─── watch command ───────────────────────────────────────────────────────────

Future<void> _watchCmd(List<String> args) async {
  final path = args.isEmpty ? '.' : args.first;
  final doFormat = !args.contains('--no-format');
  final withAnalyze = args.contains('--with-analyze');

  print('dmacro — watching $path … (Ctrl+C to stop)'
      '${withAnalyze ? "  [analyzer on]" : ""}');

  // Initial full build.
  await _compileDir(path, doFormat: doFormat);

  // Debounce timers per path.
  final debounce = <String, Timer>{};

  Directory(path).watch(recursive: true).listen((event) {
    final p = event.path;
    if (event.type == FileSystemEvent.delete) return;
    final isMacroSource = p.endsWith('.dmacro') || p.endsWith('.sexp');
    final isDart = p.endsWith('.dart');
    if (!isMacroSource && !isDart) return;

    debounce[p]?.cancel();
    debounce[p] = Timer(const Duration(milliseconds: 100), () async {
      try {
        if (isDart) {
          final content = await File(p).readAsString();
          if (!content.contains(_blockStart)) return;
          await _compileDartInline(p, doFormat: doFormat);
        } else {
          final outFile = _outputPath(p);
          await _compileSingle(p, outputPath: outFile, doFormat: doFormat);
          if (withAnalyze) await _analyzeOutput(outFile, p);

          // Cascade: recompile all files that import this macro file.
          final absP = File(p).absolute.path;
          for (final dep in depGraph.dependentsOf(absP)) {
            if (dep.endsWith('.dmacro') || dep.endsWith('.sexp')) {
              final depOut = _outputPath(dep);
              await _compileSingle(dep, outputPath: depOut, doFormat: doFormat);
              if (withAnalyze) await _analyzeOutput(depOut, dep);
            }
          }
        }
      } catch (e) {
        stderr.writeln('✗ $p: $e');
      }
    });
  });

  // Keep the process alive.
  await Completer<void>().future;
}

// ─── Analyzer integration ─────────────────────────────────────────────────────

/// Runs `dart analyze` on [dartPath] and prints any issues with source
/// locations mapped back to the `.dmacro`/`.sexp` origin using the
/// `@dmacro-origin` comments embedded in the generated file.
Future<void> _analyzeOutput(String dartPath, String sourcePath) async {
  // Use --format json for reliable machine-parseable output.
  final result = Process.runSync(
    Platform.resolvedExecutable,
    ['analyze', '--format', 'json', dartPath],
    stdoutEncoding: systemEncoding,
    stderrEncoding: systemEncoding,
  );

  final raw = result.stdout.toString().trim();
  if (raw.isEmpty) return;

  Map<String, dynamic> json;
  try {
    json = jsonDecode(raw) as Map<String, dynamic>;
  } catch (_) {
    return; // Non-JSON output (e.g., "No issues found!") — nothing to do.
  }

  final diagnostics = json['diagnostics'] as List<dynamic>? ?? [];
  if (diagnostics.isEmpty) return;

  // Build origin map from the generated file so we can map dart line numbers
  // back to source positions.
  final originMap = _buildOriginMap(dartPath);

  for (final d in diagnostics) {
    final diag = d as Map<String, dynamic>;
    final sev = (diag['severity'] as String? ?? 'info').toLowerCase();
    final msg = diag['problemMessage'] as String? ?? '';
    final loc = diag['location'] as Map<String, dynamic>? ?? {};
    final range = loc['range'] as Map<String, dynamic>? ?? {};
    final start = range['start'] as Map<String, dynamic>? ?? {};
    final dartLine = (start['line'] as int? ?? 0) + 1; // json is 0-indexed

    final sourceRef = _lookupOrigin(originMap, dartLine) ?? '$sourcePath:?';
    stderr.writeln('  analyzer $sev: $sourceRef: $msg');
  }
}

/// Reads a generated `.dart` file and extracts `@dmacro-origin` comments.
/// Returns a list of (dartLine, sourceRef) sorted by dartLine.
List<(int dartLine, String sourceRef)> _buildOriginMap(String dartPath) {
  final result = <(int, String)>[];
  final lines = File(dartPath).readAsLinesSync();
  final pattern = RegExp(r'// @dmacro-origin: (.+)');
  for (var i = 0; i < lines.length; i++) {
    final m = pattern.firstMatch(lines[i]);
    if (m != null) result.add((i + 1, m.group(1)!));
  }
  return result;
}

/// Returns the closest source reference for a generated Dart line number.
String? _lookupOrigin(List<(int, String)> origins, int dartLine) {
  String? best;
  for (final (line, ref) in origins) {
    if (line <= dartLine) {
      best = ref;
    } else {
      break;
    }
  }
  return best;
}

// ─── trace command ───────────────────────────────────────────────────────────

/// Expands all macros in [inputPath] step-by-step and prints each expansion.
///
/// Useful for debugging custom macros: you can see exactly which macro ran,
/// what input it received, and what AST it produced at each step.
Future<void> _traceCmd(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln('Usage: dmacro trace <file.dmacro|file.sexp>');
    exit(1);
  }
  final inputPath = args.first;
  if (!File(inputPath).existsSync()) {
    stderr.writeln('Error: $inputPath does not exist');
    exit(1);
  }
  final source = await File(inputPath).readAsString();
  stdout.writeln('dmacro trace — $inputPath');
  try {
    if (inputPath.endsWith('.dmacro')) {
      await asyncCompileDartLikeWithTrace(source, inputPath, stdout);
    } else {
      await asyncCompileWithTrace(source, inputPath, stdout);
    }
  } catch (e) {
    if (e is MacroExpansionError) {
      stderr.writeln(e);
    } else {
      stderr.writeln('$inputPath: ${_stripExceptionPrefix(e)}');
    }
    exit(1);
  }
}

// ─── REPL ────────────────────────────────────────────────────────────────────

Future<void> _repl() async {
  print(
      'dmacro REPL — type Dart-like code or S-expressions. Ctrl+C to exit.\n');

  while (true) {
    stdout.write('dmacro> ');
    final line = stdin.readLineSync();
    if (line == null) break;
    if (line.trim().isEmpty) continue;

    try {
      // Auto-detect: S-expression starts with (, Dart-like doesn't
      final dart = line.trimLeft().startsWith('(')
          ? await asyncCompile(line)
          : await asyncCompileDartLike(line);
      print('→ $dart\n');
    } catch (e) {
      print('Error: $e\n');
    }
  }
}

// ─── dart format ─────────────────────────────────────────────────────────────

/// Runs `dart format` on [code] via a temp file; falls back to [code] on any
/// error so a missing Dart SDK never breaks the build.
String _format(String code) {
  File? tmp;
  try {
    tmp = File('${Directory.systemTemp.path}'
        '/dmacro_fmt_${DateTime.now().microsecondsSinceEpoch}.dart');
    tmp.writeAsStringSync(code);
    final result = Process.runSync(
      Platform.resolvedExecutable,
      ['format', tmp.path],
    );
    if (result.exitCode == 0) return tmp.readAsStringSync();
  } catch (_) {
    // Format failure is non-fatal.
  } finally {
    try {
      tmp?.deleteSync();
    } catch (_) {}
  }
  return code;
}

// ─── Error formatting ────────────────────────────────────────────────────────

/// Strips verbose class-name prefixes (e.g. `ParseException: `) so the CLI
/// outputs the standard `file:line:col: message` format that IDEs understand.
String _stripExceptionPrefix(Object e) {
  final s = '$e';
  for (final prefix in const [
    'ParseException: ',
    'TokenizerException: ',
    'FormatException: ',
    'StateError: ',
  ]) {
    if (s.startsWith(prefix)) return s.substring(prefix.length);
  }
  return s;
}

// ─── help ────────────────────────────────────────────────────────────────────

void _usage() => print('''
dmacro — Lisp-style macros that compile to Dart

Usage:
  dart run bin/dmacro.dart compile <file.dmacro>              Dart-like → Dart
  dart run bin/dmacro.dart compile <file.sexp>                S-expression → Dart
  dart run bin/dmacro.dart compile <file.dart>                Expand inline @@dmacro blocks
  dart run bin/dmacro.dart compile <file> -o output.dart      Write to specific file
  dart run bin/dmacro.dart compile <dir>                      Compile all sources under dir
  dart run bin/dmacro.dart compile <dir> --check              CI: exit non-zero if stale
  dart run bin/dmacro.dart compile <file> --no-format         Skip dart format
  dart run bin/dmacro.dart watch <path>                       Watch and recompile on save
  dart run bin/dmacro.dart watch <path> --with-analyze        Watch + run dart analyze after each compile
  dart run bin/dmacro.dart trace <file>                       Print each macro expansion step (debug)
  dart run bin/dmacro.dart repl                               Interactive REPL

Dart-like syntax (.dmacro):
  defrecord Payment { double amount; String currency; }
  bool validate(double amount) {
    unless (amount > 0) { throw Exception("invalid"); }
    return true;
  }
  defFromJsonSchema("schemas/payment.json");

Inline blocks inside existing .dart files:
  // @@dmacro
  defrecord Product { String id; String name; double price; }
  // @@end
  (run dmacro compile on the .dart file — expands block in-place)

S-expression syntax (.sexp):
  (defrecord Payment (double amount) (String currency))
  (defn bool validate ((double amount))
    (unless (> amount 0) (throw (Exception "invalid")))
    (return true))

Built-in macros (both syntaxes):
  unless / when               Custom control flow
  swap!                       Variable swap — injects temp into caller scope
  assert-that                 Error message contains the source expression
  with-retry                  Retry loop with injected state
  defrecord                   Immutable data class with copyWith / == / hashCode
  defunion                    Sealed class hierarchy
  defFromJsonSchema(path)     Generate class from JSON Schema during generation step
  importMacros(path)          Load macro definitions from another .dmacro file
''');
