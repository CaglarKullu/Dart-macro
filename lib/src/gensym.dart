/// Hygiene — unique symbol generation for macros.
///
/// Macros that introduce temporary variables must use [gensym] to avoid
/// colliding with user-defined variables (variable capture).
///
/// Call [resetGensym] at the start of each compilation unit so that output
/// is deterministic: same source → same generated names.
library;

int _counter = 0;

/// Returns a unique identifier: `__<prefix>_<n>`
///
/// Examples: `__swap_0`, `__attempt_1`, `__g_2`
String gensym([String prefix = 'g']) => '__${prefix}_${_counter++}';

/// Resets the gensym counter to 0.
///
/// MUST be called at the start of each compilation unit for deterministic
/// output (same input always produces identical symbol names).
void resetGensym() => _counter = 0;
