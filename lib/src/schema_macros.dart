/// Async macros that generate Dart types from JSON Schema files at compile time.
///
/// This is the headline capability: I/O-based code generation with zero
/// non-SDK dependencies and no build_runner required.
library;

import 'dart:convert';
import 'dart:io';

import 'async_expand.dart';
import 'core.dart';

/// Registers schema-reading macros. Call this alongside [registerBuiltins].
void registerSchemaMacros() {
  // ─── defFromJsonSchema ──────────────────────────────────────────────────────

  defAsyncMacro('defFromJsonSchema', (args) async {
    final path = _unquote(args[0] as String);
    return _defrecordFromSchemaFile(path, callerMacro: 'defFromJsonSchema');
  });

  // ─── defAllFromJsonSchema ───────────────────────────────────────────────────

  defAsyncMacro('defAllFromJsonSchema', (args) async {
    final dirPath = _unquote(args[0] as String);
    final dir = Directory(dirPath);
    if (!dir.existsSync()) {
      throw StateError(
        'defAllFromJsonSchema: directory not found: $dirPath\n'
        '  (resolved from working directory: ${Directory.current.path})',
      );
    }

    final files = dir.listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
        ..sort((a, b) => a.path.compareTo(b.path)); // alphabetical = deterministic

    if (files.isEmpty) {
      throw StateError(
        'defAllFromJsonSchema: no .json files found in $dirPath',
      );
    }

    final records = <Node>[];
    for (final file in files) {
      records.add(await _defrecordFromSchemaFile(
        file.path,
        callerMacro: 'defAllFromJsonSchema',
      ));
    }

    // Wrap in 'do' so the caller receives a single node that splices cleanly.
    return ['do', ...records];
  });

  // ─── defFromOpenApi ─────────────────────────────────────────────────────────

  defAsyncMacro('defFromOpenApi', (args) async {
    final path       = _unquote(args[0] as String);
    final schemaName = _unquote(args[1] as String);

    final file = File(path);
    if (!file.existsSync()) {
      throw StateError(
        'defFromOpenApi: file not found: $path\n'
        '  (resolved from working directory: ${Directory.current.path})',
      );
    }

    Map<String, dynamic> spec;
    try {
      spec = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    } catch (e) {
      throw StateError(
        'defFromOpenApi: failed to parse $path as JSON: $e\n'
        '  Only JSON-format OpenAPI specs are supported (not YAML).',
      );
    }

    final schemas = (spec['components'] as Map<String, dynamic>?)?['schemas']
        as Map<String, dynamic>?;

    if (schemas == null) {
      throw StateError(
        'defFromOpenApi: no components/schemas section found in $path',
      );
    }

    final schema = schemas[schemaName] as Map<String, dynamic>?;
    if (schema == null) {
      final available = schemas.keys.join(', ');
      throw StateError(
        'defFromOpenApi: schema "$schemaName" not found in $path\n'
        '  Available schemas: $available',
      );
    }

    return _defrecordFromSchema(schemaName, schema);
  });
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

Future<Node> _defrecordFromSchemaFile(
  String path, {
  required String callerMacro,
}) async {
  final file = File(path);
  if (!file.existsSync()) {
    throw StateError(
      '$callerMacro: file not found: $path\n'
      '  (resolved from working directory: ${Directory.current.path})',
    );
  }

  final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  if (json['title'] == null) {
    throw StateError('$callerMacro: schema at $path missing "title"');
  }

  return _defrecordFromSchema(json['title'] as String, json);
}

Node _defrecordFromSchema(String name, Map<String, dynamic> schema) {
  final props =
      (schema['properties'] as Map<String, dynamic>? ?? const {})
          .cast<String, dynamic>();
  final required =
      ((schema['required'] as List<dynamic>?) ?? const []).cast<String>();

  final fields = <List<String>>[];
  for (final entry in props.entries) {
    var type = _dartType(entry.value as Map<String, dynamic>);
    if (!required.contains(entry.key)) type = '$type?';
    fields.add([type, entry.key]);
  }

  return ['defrecord', name, ...fields];
}

// ─── Type mapping ─────────────────────────────────────────────────────────────

String _dartType(Map<String, dynamic> schema) {
  // OpenAPI $ref: '#/components/schemas/Money' → 'Money'
  final ref = schema[r'$ref'] as String?;
  if (ref != null) return ref.split('/').last;

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
