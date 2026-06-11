/// Cross-isolate serialization for [Node] values.
///
/// `useMacros` runs Dart-function macros in a worker isolate and ships the
/// argument/result trees across a [SendPort]. Nodes are already nested lists of
/// primitives, so the only value that needs special handling is [Splice], which
/// is encoded as a sentinel map. Encoding to plain primitives (rather than
/// relying on isolate object-copy of the [Splice] class) keeps the wire format
/// explicit and immune to any cross-isolate class-identity surprises.
library;

import 'core.dart';

/// Sentinel key marking an encoded [Splice]. A real [Node] is never a [Map],
/// so this can never collide with user data.
const _spliceKey = '#dmacro:splice';

/// Encodes a [Node] tree into isolate-sendable primitives (lists, maps, atoms).
Object? encodeNode(Node node) {
  if (node is Splice) {
    return {_spliceKey: node.nodes.map(encodeNode).toList()};
  }
  if (node is List) {
    return node.map(encodeNode).toList();
  }
  return node; // String / num / bool / null — already sendable.
}

/// Inverse of [encodeNode]: rebuilds a [Node] tree from sent primitives.
Node decodeNode(Object? wire) {
  if (wire is Map && wire.containsKey(_spliceKey)) {
    return Splice(
        (wire[_spliceKey] as List).map(decodeNode).toList());
  }
  if (wire is List) {
    return wire.map(decodeNode).toList();
  }
  return wire;
}
