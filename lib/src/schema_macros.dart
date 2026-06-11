/// Async macros that generate Dart types from JSON Schema files at compile time.
///
/// This is the headline capability: I/O-based code generation with zero
/// non-SDK dependencies and no build_runner required.
library;

import 'dart:convert';
import 'dart:io';

import 'async_expand.dart'
    show defAsyncMacro, asyncCompile, asyncCompileDartLike, asyncExpand;
import 'builtins.dart' show substituteBindings;
import 'core.dart';
import 'dep_graph.dart' show depGraph, resolveDepPath;
import 'gen_cache.dart' show currentSourceFile, recordGenerationInput;
import 'yaml_parser.dart';

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
    // and any enums declared inside $defs sections before processing fields
    // that might $ref them.
    _knownEnumNames.clear();
    for (final file in files) {
      recordGenerationInput(file.absolute.path);
      final json =
          jsonDecode(await file.readAsString()) as Map<String, dynamic>;
      if (json['enum'] != null) {
        // Register by title if present, fall back to the stem of the filename
        // so $ref: '#/.../Status' resolves even when the schema has no title.
        final title = (json['title'] as String?) ??
            file.uri.pathSegments.last.replaceAll('.json', '');
        _knownEnumNames.add(title);
      }
      _prescannDefs(json);
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

    recordGenerationInput(file.absolute.path);
    final content = await file.readAsString();
    Map<String, dynamic> spec;
    try {
      if (path.endsWith('.yaml') || path.endsWith('.yml')) {
        spec = parseYaml(content) as Map<String, dynamic>;
      } else {
        spec = jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (e) {
      throw StateError(
        'defFromOpenApi: failed to parse $path: $e\n'
        '  Supported formats: JSON (.json) and YAML (.yaml / .yml).',
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

  // ─── defmacro_typed ──────────────────────────────────────────────────────────
  //
  // Emitted by the parser for `defmacro(declaration)`, `defmacro(expression)`,
  // and `defmacro(statement)`. Registers the named macro and wraps each call
  // in a post-expansion validator so the declared output type is enforced.
  //
  // args: [outputType, name, params, body]
  //
  // Example:
  //   defmacro(declaration) makeConfig(name) {
  //     defrecord name { String host; int port; }
  //   }
  //   makeConfig(AppConfig);   // ← validated to be a declaration
  //
  // If the macro's expanded output does not match the declared type, an
  // [ArgumentError] is thrown at call time with a clear diagnostic.

  defAsyncMacro('defmacro_typed', (args) async {
    final outputType = args[0] as String;
    final name = args[1] as String;
    if (args.length < 4) {
      throw ArgumentError(
          'defmacro($outputType) $name: expected (type name params body)');
    }
    final params = (args[2] as List).cast<String>();
    final body = args.length == 4 ? args[3] : ['do', ...args.sublist(3)];

    const validTypes = {'declaration', 'expression', 'statement'};
    if (!validTypes.contains(outputType)) {
      throw ArgumentError(
        'defmacro($outputType) $name: unknown output type "$outputType".\n'
        '  Valid types: ${validTypes.join(", ")}',
      );
    }

    // Register as async so we can expand → emit → validate before returning.
    defAsyncMacro(name, (callArgs) async {
      if (callArgs.length != params.length) {
        throw ArgumentError(
          '$name: expected ${params.length} arg(s), got ${callArgs.length}',
        );
      }
      final bindings = Map.fromIterables(params, callArgs);
      final substituted = substituteBindings(body, bindings);
      final expanded = await asyncExpand(substituted);
      final emitted = emit(expanded);
      _validateMacroOutput(name, outputType, emitted);
      return expanded;
    });

    return '';
  });

  // ─── importMacros ────────────────────────────────────────────────────────────
  //
  // Loads macro definitions from another .dmacro file and registers them in the
  // current session. The imported file's output is discarded — only side-effects
  // (defmacro registrations) carry over.
  //
  // Usage in .dmacro file:
  //   importMacros("path/to/macros.dmacro");
  //   importMacros("package:mymacros/macros.dmacro");  // pub package path

  defAsyncMacro('importMacros', (args) async {
    var importPath = _unquote(args[0] as String);

    // Resolve package: URIs relative to the pub cache / package root if possible,
    // otherwise treat as a plain path relative to the working directory.
    if (importPath.startsWith('package:')) {
      final packageUri = Uri.parse(importPath);
      // Strip 'package:' prefix and attempt to find the file via pub's layout.
      // pub layout: .dart_tool/package_config.json lists rootUri for each package.
      final resolved = await _resolvePackageUri(packageUri);
      if (resolved == null) {
        throw StateError(
          'importMacros: could not resolve $importPath\n'
          '  Make sure `dart pub get` has been run in the project root.',
        );
      }
      importPath = resolved;
    }

    final file = File(importPath);
    if (!file.existsSync()) {
      throw StateError(
        'importMacros: file not found: $importPath\n'
        '  (resolved from working directory: ${Directory.current.path})',
      );
    }

    // Record dep-graph edge so watch mode recompiles when the imported file changes.
    final absImport = resolveDepPath(importPath);
    if (currentSourceFile.isNotEmpty) {
      depGraph.recordDependency(currentSourceFile, absImport);
    }

    // Parse and expand the imported file. Any defmacro calls inside register
    // macros as a side effect. Output is intentionally discarded.
    final source = await file.readAsString();
    if (importPath.endsWith('.dmacro')) {
      await asyncCompileDartLike(source);
    } else if (importPath.endsWith('.sexp')) {
      await asyncCompile(source);
    } else {
      throw StateError(
        'importMacros: unsupported file type for $importPath\n'
        '  Only .dmacro and .sexp files can be imported.',
      );
    }

    // Return empty string — no Dart output from an import statement.
    return '';
  });
}

// ─── defmacro_typed helpers ───────────────────────────────────────────────────

const _declarationStarters = {
  'class ',
  'abstract ',
  'enum ',
  'typedef ',
  'extension ',
  'mixin ',
  'sealed ',
};

void _validateMacroOutput(String name, String type, String emitted) {
  final trimmed = emitted.trim();
  if (trimmed.isEmpty) {
    throw ArgumentError(
      '$name (defmacro($type)): macro produced empty output.\n'
      '  A "$type" macro must produce non-empty Dart code.',
    );
  }
  switch (type) {
    case 'declaration':
      final startsWithDecl =
          _declarationStarters.any((kw) => trimmed.startsWith(kw)) ||
          RegExp(r'^[A-Za-z_][A-Za-z0-9_<>?,\s]*\s+[a-zA-Z_]\w*\s*\(')
              .hasMatch(trimmed);
      if (!startsWithDecl) {
        throw ArgumentError(
          '$name (defmacro(declaration)): output does not look like a declaration.\n'
          '  Expected a class, enum, typedef, or function declaration.\n'
          '  Got: ${trimmed.length > 80 ? '${trimmed.substring(0, 80)}…' : trimmed}',
        );
      }
    case 'expression':
      if (trimmed.endsWith(';')) {
        throw ArgumentError(
          '$name (defmacro(expression)): output ends with ";" — looks like a statement.\n'
          '  An "expression" macro should produce a value, not a statement.\n'
          '  Got: ${trimmed.length > 80 ? '${trimmed.substring(0, 80)}…' : trimmed}',
        );
      }
    case 'statement':
      if (!trimmed.endsWith(';') && !trimmed.endsWith('}')) {
        throw ArgumentError(
          '$name (defmacro(statement)): output does not look like a statement.\n'
          '  A "statement" macro should end with ";" or "}".\n'
          '  Got: ${trimmed.length > 80 ? '${trimmed.substring(0, 80)}…' : trimmed}',
        );
      }
  }
}

/// Resolves a `package:name/path.dmacro` URI to an absolute filesystem path
/// using the `.dart_tool/package_config.json` written by `dart pub get`.
Future<String?> _resolvePackageUri(Uri packageUri) async {
  final packageName = packageUri.pathSegments[0];
  final relativePath = packageUri.pathSegments.sublist(1).join('/');

  // Search up from the working directory for package_config.json.
  var dir = Directory.current;
  for (var i = 0; i < 10; i++) {
    final configFile =
        File('${dir.path}/.dart_tool/package_config.json');
    if (configFile.existsSync()) {
      try {
        final config =
            jsonDecode(configFile.readAsStringSync()) as Map<String, dynamic>;
        final packages = (config['packages'] as List<dynamic>?) ?? [];
        for (final pkg in packages) {
          final p = pkg as Map<String, dynamic>;
          if (p['name'] == packageName) {
            final rootUri = Uri.parse(p['rootUri'] as String);
            final absRoot = rootUri.isAbsolute
                ? rootUri.toFilePath()
                : '${dir.path}/${rootUri.path}';
            return '$absRoot/$relativePath';
          }
        }
      } catch (_) {
        return null;
      }
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  return null;
}

// ─── Shared helpers ───────────────────────────────────────────────────────────

/// Set of type names that are known to be enums (populated during pre-scan).
/// Used by [_dartType] to emit `enum:Name` signal for `$ref` fields.
final _knownEnumNames = <String>{};

/// Pre-scans the `$defs` / `definitions` block of [schema] and registers any
/// enum type names in [_knownEnumNames]. Must be called before generating
/// types so that `$ref` fields resolve correctly.
void _prescannDefs(Map<String, dynamic> schema) {
  final defs =
      (schema[r'$defs'] ?? schema['definitions']) as Map<String, dynamic>?;
  if (defs == null) return;
  for (final entry in defs.entries) {
    final defSchema = entry.value as Map<String, dynamic>;
    if (defSchema['enum'] != null) {
      final defName = (defSchema['title'] as String?) ?? entry.key;
      _knownEnumNames.add(defName);
    }
  }
}

/// Generates type nodes for all entries in the `$defs` / `definitions` block
/// of [schema]. Returns an empty list when no such block exists.
List<Node> _generateDefNodes(Map<String, dynamic> schema) {
  final defs =
      (schema[r'$defs'] ?? schema['definitions']) as Map<String, dynamic>?;
  if (defs == null) return const [];

  final nodes = <Node>[];
  for (final entry in defs.entries) {
    final defSchema = entry.value as Map<String, dynamic>;
    final defName = (defSchema['title'] as String?) ?? entry.key;
    final enumValues = defSchema['enum'] as List?;

    if (enumValues != null) {
      nodes.add(
          ['defenum', defName, enumValues.map((v) => v.toString()).toList()]);
    } else if (defSchema['type'] == 'object' ||
        defSchema['properties'] != null) {
      nodes.add(_defrecordFromSchema(defName, defSchema));
    }
  }
  return nodes;
}

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

  // Record the schema file as a generation-time input for caching.
  recordGenerationInput(file.absolute.path);
  final json = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
  if (json['title'] == null) {
    final hint = json['oneOf'] != null
        ? ' (for oneOf schemas, add a "title" to name the sealed parent class)'
        : '';
    throw StateError('$callerMacro: schema at $path missing "title"$hint');
  }

  final title = json['title'] as String;

  // Pre-scan $defs so $ref fields inside the main schema resolve correctly.
  _prescannDefs(json);

  // Top-level enum schema: `{"title": "Status", "enum": ["a", "b"]}`
  final enumValues = json['enum'] as List?;
  if (enumValues != null) {
    _knownEnumNames.add(title);
    return ['defenum', title, enumValues.map((v) => v.toString()).toList()];
  }

  final defNodes = _generateDefNodes(json);
  final record = _defrecordFromSchema(title, json);

  if (defNodes.isEmpty) return record;
  // Emit $defs types before the main record so they're in scope for $ref fields.
  return ['do', ...defNodes, record];
}

Node _defrecordFromSchema(String name, Map<String, dynamic> schema) {
  // oneOf → sealed class hierarchy (defunion)
  final oneOf = schema['oneOf'] as List?;
  if (oneOf != null) {
    return _defunionFromOneOf(name, oneOf.cast<Map<String, dynamic>>());
  }

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
      inlineEnums.add(
          ['defenum', enumName, enumValues.map((v) => v.toString()).toList()]);
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

// ─── oneOf → defunion ─────────────────────────────────────────────────────────

Node _defunionFromOneOf(
    String name, List<Map<String, dynamic>> variantSchemas) {
  final variants = <Node>[];
  for (final vs in variantSchemas) {
    // Variant name: prefer 'title', fall back to last segment of '$ref'.
    final String variantName;
    if (vs['title'] != null) {
      variantName = vs['title'] as String;
    } else if (vs[r'$ref'] != null) {
      variantName = (vs[r'$ref'] as String).split('/').last;
    } else {
      continue; // skip nameless variants
    }

    final props = (vs['properties'] as Map<String, dynamic>? ?? const {})
        .cast<String, dynamic>();
    final required = ((vs['required'] as List?) ?? const []).cast<String>();
    final fields = <List<String>>[];

    for (final entry in props.entries) {
      final propSchema = entry.value as Map<String, dynamic>;
      var type = _dartType(propSchema);
      if (!required.contains(entry.key)) type = '$type?';
      fields.add([type, entry.key]);
    }

    variants.add([variantName, ...fields]);
  }
  if (variants.isEmpty) {
    throw StateError(
      'defFromJsonSchema/defFromOpenApi: oneOf schema "$name" has no named '
      'variants. Each oneOf entry needs a "title" or a "\$ref".',
    );
  }
  return ['defunion', name, ...variants];
}

// ─── Type mapping ─────────────────────────────────────────────────────────────

String _dartType(Map<String, dynamic> schema) {
  // JSON Schema $ref: '#/$defs/Money' or OpenAPI '#/components/schemas/Money' → 'Money'
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
    .map(
        (part) => part.isEmpty ? '' : part[0].toUpperCase() + part.substring(1))
    .join('');

String _unquote(String s) =>
    (s.startsWith('"') && s.endsWith('"')) ? s.substring(1, s.length - 1) : s;
