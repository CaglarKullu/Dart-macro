/// Async expander — like [expand] but macro functions may be [FutureOr].
///
/// This is the keystone of Phase 2: macros can perform I/O (read files,
/// fetch schemas, query databases) at generation time. The expander awaits
/// each macro result in sequential order so gensym counters and I/O
/// side-effects remain deterministic.
///
/// Sync macros registered with [defmacro] continue to work unchanged — they
/// are discoverable via [getMacro] and awaited as [FutureOr].
library;

import 'dart:async';

import 'core.dart';
import 'dart_parser.dart';
import 'gensym.dart';
import 'reader.dart';
import 'tokenizer.dart';

typedef AsyncMacroFn = FutureOr<Node> Function(List<Node> args);

final _asyncMacros = <String, AsyncMacroFn>{};

/// Registers an async (or sync) macro.
/// Async macros shadow same-named sync macros registered with [defmacro].
void defAsyncMacro(String name, AsyncMacroFn fn) => _asyncMacros[name] = fn;

/// Names of every async-registered macro. Used by the `useMacros` worker to
/// report which macros a loaded Dart library exposes.
Iterable<String> asyncMacroNames() => _asyncMacros.keys;

/// Invokes the macro registered under [name] exactly once (no recursive
/// expansion of its result) and returns its raw output. Async macros take
/// priority over sync ones, matching [asyncExpand]'s dispatch. Throws
/// [MacroExpansionError] with the macro named if it is unknown or fails.
///
/// Used by the `useMacros` worker isolate: the parent's expander drives all
/// recursion, so a worker only ever evaluates one macro call at a time.
Future<Node> invokeMacroOnce(String name, List<Node> args) async {
  final asyncFn = _asyncMacros[name];
  final fn = asyncFn ?? getMacro(name);
  if (fn == null) {
    throw MacroExpansionError('macro "$name" is not registered in this worker');
  }
  try {
    return await fn(args);
  } on MacroExpansionError {
    rethrow;
  } catch (e) {
    throw MacroExpansionError('macro "$name" failed: $e');
  }
}

/// Recursively expands all macros in [node], awaiting async macro results.
///
/// Children are expanded sequentially (not concurrently) to preserve
/// deterministic gensym ordering and I/O side-effect order.
Future<Node> asyncExpand(Node node) async {
  // A macro may return a Splice (e.g. $map) whose nodes are unexpanded
  // templates — expand each, flattening any nested Splice one level up.
  if (node is Splice) {
    final out = <Node>[];
    for (final n in node.nodes) {
      final expanded = await asyncExpand(n);
      if (expanded is Splice) {
        out.addAll(expanded.nodes);
      } else {
        out.add(expanded);
      }
    }
    return Splice(out);
  }
  if (node is! List || node.isEmpty) return node;

  final head = node[0];
  final args = node.sublist(1);

  if (head is String) {
    // Async macros take priority over sync ones.
    final asyncFn = _asyncMacros[head];
    if (asyncFn != null) {
      try {
        return asyncExpand(await asyncFn(args));
      } on MacroExpansionError {
        rethrow;
      } catch (e) {
        throw MacroExpansionError('macro "$head" failed: $e');
      }
    }
    final syncFn = getMacro(head);
    if (syncFn != null) {
      try {
        return asyncExpand(syncFn(args));
      } on MacroExpansionError {
        rethrow;
      } catch (e) {
        throw MacroExpansionError('macro "$head" failed: $e');
      }
    }
  }

  // Not a macro — expand children sequentially, then flatten Splice.
  final out = <Node>[head];
  for (final child in args) {
    final expanded = await asyncExpand(child);
    if (expanded is Splice) {
      out.addAll(expanded.nodes);
    } else {
      out.add(expanded);
    }
  }
  return out;
}

/// Compiles an S-expression [source] string to Dart via the async expander.
/// Calls [resetGensym] first for deterministic output.
Future<String> asyncCompile(String source) async {
  resetGensym();
  resetEnumRegistry();
  final forms = Reader(source).readAll();
  final results = <String>[];
  for (final f in forms) {
    results.add(emitForm(await asyncExpand(f)));
  }
  return assembleOutput(results);
}

/// Compiles Dart-like (.dmacro) [source] to Dart via the async expander.
/// Calls [resetGensym] first for deterministic output.
Future<String> asyncCompileDartLike(String source) async {
  resetGensym();
  resetEnumRegistry();
  final tokens = Tokenizer(source).tokenize();
  final forms = DartLikeParser(tokens).parseProgram();
  final results = <String>[];
  for (final f in forms) {
    results.add(emitForm(await asyncExpand(f)));
  }
  return assembleOutput(results);
}

// ─── Origin-tracking variants ─────────────────────────────────────────────────
//
// These embed `// @dmacro-origin: <path>:<line>` comments before each top-level
// form so that post-compile tools (analyzer integration, IDE extensions) can map
// generated `.dart` line numbers back to the source `.dmacro`/`.sexp` location.

/// Like [asyncCompileDartLike] but prefixes each emitted form with an origin
/// comment: `// @dmacro-origin: <sourcePath>:<line>`.
///
/// Also sets the emitter source path so macros can embed per-element origin
/// markers (e.g. per-field markers inside a `defrecord` generated class).
/// Per-field markers are only emitted when [fieldOrigins] is true (off by
/// default — enable with `--field-origins` on the CLI).
/// Wraps expansion errors as [MacroExpansionError] with the source location.
Future<String> asyncCompileDartLikeWithOrigins(String source, String sourcePath,
    {bool fieldOrigins = false}) async {
  resetGensym();
  resetEnumRegistry();
  final tokens = Tokenizer(source).tokenize();
  final spanned = DartLikeParser(tokens).parseProgramSpanned();
  final results = <String>[];
  for (final (form, line) in spanned) {
    setEmitterSourcePath(sourcePath);
    setEmitterFieldOrigins(fieldOrigins);
    try {
      final emitted = emitForm(await asyncExpand(form));
      results.add('// @dmacro-origin: $sourcePath:$line\n$emitted');
    } catch (e) {
      // Always prepend source location, whether or not asyncExpand already
      // wrapped the error with macro-name attribution.
      final msg = e is MacroExpansionError ? e.message : '$e';
      throw MacroExpansionError('$sourcePath:$line: $msg');
    } finally {
      setEmitterSourcePath(null);
      setEmitterFieldOrigins(false);
    }
  }
  return assembleOutput(results);
}

/// Like [asyncCompile] (.sexp) but prefixes each emitted form with an origin
/// comment: `// @dmacro-origin: <sourcePath>:<line>`.
///
/// Also sets the emitter source path and wraps expansion errors as
/// [MacroExpansionError] with the source location.
/// Per-field markers are only emitted when [fieldOrigins] is true.
Future<String> asyncCompileWithOrigins(String source, String sourcePath,
    {bool fieldOrigins = false}) async {
  resetGensym();
  resetEnumRegistry();
  final spanned = Reader(source).readAllSpanned();
  final results = <String>[];
  for (final (form, line) in spanned) {
    setEmitterSourcePath(sourcePath);
    setEmitterFieldOrigins(fieldOrigins);
    try {
      final emitted = emitForm(await asyncExpand(form));
      results.add('// @dmacro-origin: $sourcePath:$line\n$emitted');
    } catch (e) {
      final msg = e is MacroExpansionError ? e.message : '$e';
      throw MacroExpansionError('$sourcePath:$line: $msg');
    } finally {
      setEmitterSourcePath(null);
      setEmitterFieldOrigins(false);
    }
  }
  return assembleOutput(results);
}

// ─── Trace variant ────────────────────────────────────────────────────────────

/// Expands [node] like [asyncExpand] but writes each macro invocation to [sink].
Future<Node> _asyncExpandWithTrace(
    Node node, StringSink sink, int depth, _TraceRef counter) async {
  if (node is Splice) {
    final out = <Node>[];
    for (final n in node.nodes) {
      final expanded = await _asyncExpandWithTrace(n, sink, depth, counter);
      if (expanded is Splice) {
        out.addAll(expanded.nodes);
      } else {
        out.add(expanded);
      }
    }
    return Splice(out);
  }
  if (node is! List || node.isEmpty) return node;

  final head = node[0];
  final args = node.sublist(1);

  if (head is String) {
    final asyncFn = _asyncMacros[head];
    final syncFn = getMacro(head);

    if (asyncFn != null || syncFn != null) {
      counter.value++;
      final pad = '  ' * depth;
      sink.writeln('$pad[${counter.value}] ${_abbrev(_nodeStr(node))}');
      final raw = asyncFn != null ? await asyncFn(args) : syncFn!(args);
      final result = await _asyncExpandWithTrace(raw, sink, depth + 1, counter);
      sink.writeln('$pad        → ${_abbrev(_nodeStr(result))}');
      return result;
    }
  }

  final out = <Node>[head];
  for (final child in args) {
    final expanded = await _asyncExpandWithTrace(child, sink, depth, counter);
    if (expanded is Splice) {
      out.addAll(expanded.nodes);
    } else {
      out.add(expanded);
    }
  }
  return out;
}

class _TraceRef {
  int value = 0;
}

String _nodeStr(Node node) {
  if (node == null) return 'null';
  if (node is Splice) return '~@(${node.nodes.map(_nodeStr).join(' ')})';
  if (node is List) {
    return node.isEmpty ? '()' : '(${node.map(_nodeStr).join(' ')})';
  }
  return '$node';
}

String _abbrev(String s, [int max = 100]) =>
    s.length <= max ? s : '${s.substring(0, max - 3)}...';

/// Compiles Dart-like [source] while printing each expansion step to [sink].
Future<String> asyncCompileDartLikeWithTrace(
    String source, String sourcePath, StringSink sink) async {
  resetGensym();
  resetEnumRegistry();
  final tokens = Tokenizer(source).tokenize();
  final spanned = DartLikeParser(tokens).parseProgramSpanned();
  final results = <String>[];
  final counter = _TraceRef();

  for (final (form, line) in spanned) {
    sink.writeln('\n─── $sourcePath:$line ───');
    sink.writeln('    ${_abbrev(_nodeStr(form))}');
    final expanded = await _asyncExpandWithTrace(form, sink, 0, counter);
    results.add(emitForm(expanded));
  }
  return assembleOutput(results);
}

/// Compiles S-expression [source] while printing each expansion step to [sink].
Future<String> asyncCompileWithTrace(
    String source, String sourcePath, StringSink sink) async {
  resetGensym();
  resetEnumRegistry();
  final spanned = Reader(source).readAllSpanned();
  final results = <String>[];
  final counter = _TraceRef();

  for (final (form, line) in spanned) {
    sink.writeln('\n─── $sourcePath:$line ───');
    sink.writeln('    ${_abbrev(_nodeStr(form))}');
    final expanded = await _asyncExpandWithTrace(form, sink, 0, counter);
    results.add(emitForm(expanded));
  }
  return assembleOutput(results);
}
