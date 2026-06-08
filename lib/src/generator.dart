/// Code generators for each built-in macro.
library;

import 'models.dart';

const _genStart = '  // ━━━ dart_macros generated ━━━';
const _genEnd   = '  // ━━━ end dart_macros ━━━';

abstract class MacroGenerator {
  /// Returns generated Dart code for the class body.
  /// Do NOT include GEN_START/GEN_END — the transformer wraps them.
  String generate(ClassInfo info);

  String get annotationName;
}

// ─────────────────────────────────────────────────────────────────────────────
// @DataClass
// Generates: copyWith · == · hashCode · toString
// ─────────────────────────────────────────────────────────────────────────────

class DataClassGenerator extends MacroGenerator {
  @override
  final String annotationName = 'DataClass';

  @override
  String generate(ClassInfo info) {
    final buf = StringBuffer();
    buf.writeln(_copyWith(info));
    buf.writeln(_equality(info));
    buf.writeln(_hashCode(info));
    buf.writeln(_toString(info));
    return buf.toString().trimRight();
  }

  String _copyWith(ClassInfo info) {
    if (info.fields.isEmpty) return '';
    final params = info.fields.map((f) {
      // Nullable fields stay nullable; non-nullable become nullable for the param
      final paramType = f.isNullable ? f.type : '${f.baseType}?';
      return '    $paramType ${f.name},';
    }).join('\n');

    final args = info.fields
        .map((f) => '      ${f.name}: ${f.name} ?? this.${f.name},')
        .join('\n');

    return '''
  ${info.name} copyWith({
$params
  }) {
    return ${info.name}(
$args
    );
  }
''';
  }

  String _equality(ClassInfo info) {
    if (info.fields.isEmpty) {
      return '''
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ${info.name};
''';
    }

    final checks = info.fields
        .map((f) => '        other.${f.name} == ${f.name}')
        .join(' &&\n');

    return '''
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ${info.name} &&
$checks;
  }
''';
  }

  String _hashCode(ClassInfo info) {
    if (info.fields.isEmpty) {
      return '  @override\n  int get hashCode => runtimeType.hashCode;\n';
    }
    if (info.fields.length == 1) {
      return '  @override\n  int get hashCode => ${info.fields.first.name}.hashCode;\n';
    }
    final fieldList = info.fields.map((f) => f.name).join(', ');
    return '  @override\n  int get hashCode => Object.hash($fieldList);\n';
  }

  String _toString(ClassInfo info) {
    final props = info.fields.map((f) => '${f.name}: \$${f.name}').join(', ');
    return "  @override\n  String toString() => '${info.name}($props)';\n";
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// @Singleton
// Generates: private constructor · static _instance · getInstance()
// ─────────────────────────────────────────────────────────────────────────────

class SingletonGenerator extends MacroGenerator {
  @override
  final String annotationName = 'Singleton';

  @override
  String generate(ClassInfo info) => '''
  ${info.name}._();

  static ${info.name}? _instance;

  static ${info.name} getInstance() {
    _instance ??= ${info.name}._();
    return _instance!;
  }''';
}

// ─────────────────────────────────────────────────────────────────────────────
// @Logged
// Generates: a log() helper and wraps toString for debug visibility
// ─────────────────────────────────────────────────────────────────────────────

class LoggedGenerator extends MacroGenerator {
  @override
  final String annotationName = 'Logged';

  @override
  String generate(ClassInfo info) => '''
  void log(String message) {
    // ignore: avoid_print
    print('[${info.name}] \$message');
  }

  void logFields() {
    log(toString());
  }''';
}

// ─────────────────────────────────────────────────────────────────────────────
// Registry — maps annotation name → generator
// ─────────────────────────────────────────────────────────────────────────────

final Map<String, MacroGenerator> macroRegistry = {
  'DataClass': DataClassGenerator(),
  'Singleton': SingletonGenerator(),
  'Logged':    LoggedGenerator(),
};
