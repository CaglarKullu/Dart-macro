/// Simulates a "team_macros" pub package: a collection of Dart-function
/// macros that any project can load by importing this file from their
/// tool/dmacro.dart entry point.
///
/// In a real distribution this would be a separate pub package:
///   dev_dependencies:
///     team_macros:
///       git: https://github.com/myorg/team_macros
library;

import 'package:dmacro/dmacro.dart';

void registerTeamMacros() {
  _registerWidgetMacros();
  _registerValidationMacros();
}

void _registerWidgetMacros() {
  defAsyncMacro('defwidget', (args) async {
    final name = unquote(args[0] as String);
    final fields = args.skip(1).cast<List>().toList();

    final decls = fields.map((f) => '  final ${f[0]} ${f[1]};').join('\n');
    final params = fields.map((f) {
      final req = (f[0] as String).endsWith('?') ? '' : 'required ';
      return '${req}this.${f[1]}';
    }).join(', ');

    return '''class $name extends StatelessWidget {
$decls

  const $name({super.key, $params});

  @override
  Widget build(BuildContext context) {
    throw UnimplementedError('implement build');
  }
}''';
  });
}

void _registerValidationMacros() {
  defmacro('assertNotEmpty', (args) {
    final field = args[0];
    final msg = args.length > 1 ? args[1] : '"must not be empty"';
    return ['if', ['==', field, '""'], ['throw', ['ArgumentError', msg]]];
  });
}
