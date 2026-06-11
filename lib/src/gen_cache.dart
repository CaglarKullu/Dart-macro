/// Content-hash cache for dmacro generation-time I/O.
///
/// When a file is compiled, its fingerprint = FNV-1a hash of all inputs:
///   - source file content
///   - every importMacros / useMacros file
///   - every external file read during expansion (schemas, OpenAPI specs)
///
/// If the fingerprint matches the stored value, the output is current and
/// compilation can be skipped. After a successful compile the fingerprint and
/// output hash are persisted in `.dart_tool/dmacro/cache.json`.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// Per-compilation list of extra files that were read at generation time
/// (e.g. by defFromJsonSchema). Reset at the start of each compilation.
final List<String> generationInputFiles = [];

/// The source file currently being compiled. Set by [_compileSingle] so macros
/// can record the source context for dep-graph edges.
String currentSourceFile = '';

/// Adds [path] to the current compilation's input set.
void recordGenerationInput(String path) {
  if (!generationInputFiles.contains(path)) {
    generationInputFiles.add(path);
  }
}

/// Clears the generation-input list. Call at the start of each compilation.
void clearGenerationInputs() {
  generationInputFiles.clear();
  currentSourceFile = '';
}

// ─── Hashing — pure Dart, no external deps ───────────────────────────────────

/// FNV-1a 64-bit hash. Deterministic, fast, zero collision rate for text.
/// Not cryptographic, but sufficient for cache fingerprinting.
String _fnv1a(Uint8List bytes) {
  var h = 0xcbf29ce484222325;
  for (final b in bytes) {
    h ^= b;
    // 64-bit multiply kept in range via masking (Dart ints are 64-bit on VM)
    h = (h * 0x100000001b3) & 0xffffffffffffffff;
  }
  return h.toRadixString(16).padLeft(16, '0');
}

String _hashString(String s) => _fnv1a(Uint8List.fromList(utf8.encode(s)));
String _hashBytes(Uint8List b) => _fnv1a(b);

// ─── Cache persistence ────────────────────────────────────────────────────────

const _cacheFile = '.dart_tool/dmacro/cache.json';

Map<String, Map<String, String>>? _cache;

Map<String, Map<String, String>> _loadCache() {
  if (_cache != null) return _cache!;
  final f = File(_cacheFile);
  if (f.existsSync()) {
    try {
      final raw = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
      _cache =
          raw.map((k, v) => MapEntry(k, Map<String, String>.from(v as Map)));
      return _cache!;
    } catch (_) {}
  }
  _cache = {};
  return _cache!;
}

void _saveCache() {
  final f = File(_cacheFile);
  f.parent.createSync(recursive: true);
  f.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(_cache));
}

// ─── Fingerprinting ───────────────────────────────────────────────────────────

/// Computes the fingerprint for a compilation given:
/// - [sourceContent]: the raw source text
/// - [importedPaths]: files pulled in by importMacros / useMacros
/// - [generationPaths]: files read at generation time (schemas, etc.)
String computeFingerprint(
  String sourceContent,
  List<String> importedPaths,
  List<String> generationPaths,
) {
  final parts = <String>[];
  parts.add(_hashString(sourceContent));

  for (final p in [...importedPaths, ...generationPaths]..sort()) {
    final f = File(p);
    if (f.existsSync()) {
      parts.add('$p:${_hashBytes(f.readAsBytesSync())}');
    }
  }
  return _hashString(parts.join('\n'));
}

// ─── Public API ───────────────────────────────────────────────────────────────

/// Returns true if the cached fingerprint for [sourceFile] matches [fp].
bool isCurrent(String sourceFile, String fp) {
  final entry = _loadCache()[sourceFile];
  return entry != null && entry['fingerprint'] == fp;
}

/// Returns the generation-input paths stored from the previous compilation of
/// [sourceFile]. Used to compute the fingerprint before re-expanding.
List<String> storedGenerationInputs(String sourceFile) {
  final entry = _loadCache()[sourceFile];
  if (entry == null) return const [];
  final raw = entry['generationInputs'];
  if (raw == null || raw.isEmpty) return const [];
  return raw.split('|').where((s) => s.isNotEmpty).toList();
}

/// Stores [fp] and the generation-input paths for [sourceFile].
void updateCache(
    String sourceFile, String fp, List<String> generationInputPaths) {
  _loadCache()[sourceFile] = {
    'fingerprint': fp,
    'generationInputs': generationInputPaths.join('|'),
  };
  _saveCache();
}

/// Removes the cache entry for [sourceFile], forcing a recompile next time.
void invalidate(String sourceFile) {
  _loadCache().remove(sourceFile);
  _saveCache();
}
