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
    _knownEnumNames.clear();
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

    final files = dir
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.json'))
        .toList()
      ..sort(
          (a, b) => a.path.compareTo(b.path)); // alphabetical = deterministic

    if (files.isEmpty) {
      throw StateError(
        'defAllFromJsonSchema: no .json files found in $dirPath',
      );
    }

    // Clear stale registry, then pre-scan to register top-level enum schemas
    // before processing fields that might $ref them.
    _knownEnumNames.clear();
    for (final file in files) {
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      final title = json['title'] as String?;
      if (title != null && json['enum'] != null) {
        _knownEnumNames.add(title);
      }
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
    final path = _unquote(args[0] as String);
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

    // Pre-scan all schemas to register enums so $ref can resolve them.
    _knownEnumNames.clear();
    for (final entry in schemas.entries) {
      final s = entry.value as Map<String, dynamic>;
      if (s['enum'] != null) {
        _knownEnumNames.add(entry.key);
      }
    }

    return _defrecordFromSchema(schemaName, schema);
  });
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

/// Set of type names that are known to be enums (populated during pre-scan).
/// Used by [_dartType] to emit `enum:Name` signal for `$ref` fields.
final _knownEnumNames = <String>{};

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

  final title = json['title'] as String;

  // Top-level enum schema: `{"title": "Status", "enum": ["a", "b"]}`
  final enumValues = json['enum'] as List?;
  if (enumValues != null) {
    _knownEnumNames.add(title);
    return ['defenum', title, enumValues.map((v) => v.toString()).toList()];
  }

  return _defrecordFromSchema(title, json);
}

Node _defrecordFromSchema(String name, Map<String, dynamic> schema) {
  final props = (schema['properties'] as Map<String, dynamic>? ?? const {})
      .cast<String, dynamic>();
  final required =
      ((schema['required'] as List<dynamic>?) ?? const []).cast<String>();

  final fields = <List<String>>[];
  final inlineEnums = <Node>[];

  for (final entry in props.entries) {
    final propSchema = entry.value as Map<String, dynamic>;
    final enumValues = propSchema['enum'] as List?;

    if (enumValues != null) {
      // Inline enum property: derive name from the field key and generate a
      // separate enum declaration alongside the record.
      final enumName = _toPascalCase(entry.key);
      _knownEnumNames.add(enumName);
      inlineEnums
          .add(['defenum', enumName, enumValues.map((v) => v.toString()).toList()]);
      var type = 'enum:$enumName';
      if (!required.contains(entry.key)) type = '$type?';
      fields.add([type, entry.key]);
    } else {
      var type = _dartType(propSchema);
      if (!required.contains(entry.key)) type = '$type?';
      fields.add([type, entry.key]);
    }
  }

  final record = ['defrecord', name, ...fields];
  if (inlineEnums.isEmpty) return record;
  // Wrap in 'do' so both the enum declaration(s) and the record are emitted.
  return ['do', ...inlineEnums, record];
}

// ─── Type mapping ─────────────────────────────────────────────────────────────

String _dartType(Map<String, dynamic> schema) {
  // OpenAPI $ref: '#/components/schemas/Money' → 'Money'
  final ref = schema[r'$ref'] as String?;
  if (ref != null) {
    final refName = ref.split('/').last;
    // Preserve the enum signal so fromJson/toJson use values.byName/.name.
    return _knownEnumNames.contains(refName) ? 'enum:$refName' : refName;
  }

  switch (schema['type'] as String?) {
    case 'number':
      return 'double';
    case 'integer':
      return 'int';
    case 'string':
      // JSON Schema `format` for temporal strings maps to DateTime; the
      // generated fromJson/toJson handle parse/ISO-8601 automatically.
      final format = schema['format'] as String?;
      return (format == 'date-time' || format == 'date')
          ? 'DateTime'
          : 'String';
    case 'boolean':
      return 'bool';
    case 'array':
      final items = (schema['items'] as Map<String, dynamic>?) ?? const {};
      return 'List<${_dartType(items)}>';
    case 'object':
      return (schema['title'] as String?) ?? 'Map<String, dynamic>';
    default:
      return 'dynamic';
  }
}

/// PascalCase: `status` → `Status`, `order_status` → `OrderStatus`.
String _toPascalCase(String s) => s
    .split('_')
    .map((part) =>
        part.isEmpty ? '' : part[0].toUpperCase() + part.substring(1))
    .join('');

String _unquote(String s) =>
    (s.startsWith('"') && s.endsWith('"')) ? s.substring(1, s.length - 1) : s;
