/// Async macros that generate Dart types from JSON Schema files at compile time.
///
/// This is the headline capability: I/O-based code generation with zero
/// non-SDK dependencies and no build_runner required.
library;

import 'dart:convert';
import 'dart:io';

import 'async_expand.dart';

/// Registers schema-reading macros. Call this alongside [registerBuiltins].
void registerSchemaMacros() {
  defAsyncMacro('defFromJsonSchema', (args) async {
    final path = _unquote(args[0] as String);

    final file = File(path);
    if (!file.existsSync()) {
      throw StateError(
        'defFromJsonSchema: file not found: $path\n'
        '  (resolved from working directory: ${Directory.current.path})',
      );
    }

    final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;

    if (json['title'] == null) {
      throw StateError('defFromJsonSchema: schema at $path missing "title"');
    }
    final name = json['title'] as String;
    final props = (json['properties'] as Map<String, dynamic>? ?? const {})
        .cast<String, dynamic>();
    final required =
        ((json['required'] as List<dynamic>?) ?? const []).cast<String>();

    final fields = <List<String>>[];
    for (final entry in props.entries) {
      var type = _dartType(entry.value as Map<String, dynamic>);
      if (!required.contains(entry.key)) type = '$type?';
      fields.add([type, entry.key]);
    }

    // Reuse the validated defrecord generation by returning the same AST shape.
    return ['defrecord', name, ...fields];
  });
}

// ─── Type mapping ─────────────────────────────────────────────────────────────

String _dartType(Map<String, dynamic> schema) {
  switch (schema['type'] as String?) {
    case 'number':  return 'double';
    case 'integer': return 'int';
    case 'string':  return 'String';
    case 'boolean': return 'bool';
    case 'array':
      final items = (schema['items'] as Map<String, dynamic>?) ?? const {};
      return 'List<${_dartType(items)}>';
    case 'object':
      return (schema['title'] as String?) ?? 'Map<String, dynamic>';
    default:
      return 'dynamic';
  }
}

String _unquote(String s) =>
    (s.startsWith('"') && s.endsWith('"')) ? s.substring(1, s.length - 1) : s;
