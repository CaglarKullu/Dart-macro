/// Data models for the annotation-based macro system.
library;

/// Information about a single field in a Dart class.
class FieldInfo {
  final String name;
  final String type;
  final bool isFinal;

  bool get isNullable => type.endsWith('?');

  /// The type without the trailing `?`, e.g. `String?` → `String`.
  String get baseType => isNullable ? type.substring(0, type.length - 1) : type;

  const FieldInfo({
    required this.name,
    required this.type,
    required this.isFinal,
  });
}

/// Information about a Dart class with macro annotations.
class ClassInfo {
  final String name;
  final List<String> annotations;
  final List<FieldInfo> fields;
  final int bodyStart;
  final int bodyEnd;

  const ClassInfo({
    required this.name,
    required this.annotations,
    required this.fields,
    required this.bodyStart,
    required this.bodyEnd,
  });

  bool hasAnnotation(String name) => annotations.contains(name);
}
