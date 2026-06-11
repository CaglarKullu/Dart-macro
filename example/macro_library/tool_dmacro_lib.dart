/// Entry point for the macro_library example (Pattern A).
///
/// In a real consumer project this lives at `tool/dmacro.dart`.
/// It imports the macro library package and passes its register function
/// to runDmacro — the full CLI (compile/watch/trace/--check/REPL) is
/// available with the team macros loaded.
///
/// Run with:
///   dart run example/macro_library/tool_dmacro_lib.dart compile \
///     example/macro_library/app.dmacro

import 'package:dmacro/dmacro.dart';

import 'macros/team_macros.dart';

void main(List<String> args) =>
    runDmacro(args, registerMacros: registerTeamMacros);
