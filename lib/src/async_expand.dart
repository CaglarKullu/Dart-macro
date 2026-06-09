/// Async expander — like [expand] but macro functions may be [FutureOr].
///
/// This is the keystone of Phase 2: macros can perform I/O (read files,
/// fetch schemas, query databases) at compile time. The expander awaits
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

/// Recursively expands all macros in [node], awaiting async macro results.
///
/// Children are expanded sequentially (not concurrently) to preserve
/// deterministic gensym ordering and I/O side-effect order.
Future<Node> asyncExpand(Node node) async {
  if (node is! List || node.isEmpty) return node;

  final head = node[0];
  final args = node.sublist(1);

  if (head is String) {
    // Async macros take priority over sync ones.
    final asyncFn = _asyncMacros[head];
    if (asyncFn != null) {
      return asyncExpand(await asyncFn(args));
    }
    final syncFn = getMacro(head);
    if (syncFn != null) {
      return asyncExpand(syncFn(args));
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
    results.add(emit(await asyncExpand(f)));
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
    results.add(emit(await asyncExpand(f)));
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
Future<String> asyncCompileDartLikeWithOrigins(
    String source, String sourcePath) async {
  resetGensym();
  resetEnumRegistry();
  final tokens = Tokenizer(source).tokenize();
  final spanned = DartLikeParser(tokens).parseProgramSpanned();
  final results = <String>[];
  for (final (form, line) in spanned) {
    final emitted = emit(await asyncExpand(form));
    results.add('// @dmacro-origin: $sourcePath:$line\n$emitted');
  }
  return assembleOutput(results);
}

/// Like [asyncCompile] (.sexp) but prefixes each emitted form with an origin
/// comment: `// @dmacro-origin: <sourcePath>:<line>`.
Future<String> asyncCompileWithOrigins(
    String source, String sourcePath) async {
  resetGensym();
  resetEnumRegistry();
  final spanned = Reader(source).readAllSpanned();
  final results = <String>[];
  for (final (form, line) in spanned) {
    final emitted = emit(await asyncExpand(form));
    results.add('// @dmacro-origin: $sourcePath:$line\n$emitted');
  }
  return assembleOutput(results);
}
