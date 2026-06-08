/// Unquote-splicing — inline multiple nodes into the parent form.
///
/// The [Splice] class is defined in [core.dart] (to avoid circular imports).
/// This file re-exports it and provides the [$splice] convenience constructor.
///
/// Usage in a macro:
/// ```dart
/// defmacro('swap!', (args) {
///   final tmp = gensym('swap');
///   return $splice([
///     $let(tmp, args[0]),
///     $set(args[0] as String, args[1]),
///     $set(args[1] as String, tmp),
///   ]);
/// });
/// ```
///
/// The [expand] function in [core.dart] recognises [Splice] children and
/// inlines their [nodes] into the parent list.
library;

import 'core.dart';

export 'core.dart' show Splice;

/// Marks [nodes] to be spliced (inlined) into the parent form during expansion.
///
/// Returns a [Splice] object, which [expand] will flatten into the parent list.
Node $splice(List<Node> nodes) => Splice(nodes);
