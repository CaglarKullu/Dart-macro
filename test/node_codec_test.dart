/// Unit tests for the cross-isolate Node codec used by `useMacros`.
///
/// The wire format must round-trip every shape a macro produces — atoms,
/// nested lists, and Splice — so worker results reconstruct exactly on the
/// parent side.
library;

import 'package:dmacro/src/core.dart' show Splice;
import 'package:dmacro/src/node_codec.dart';
import 'package:test/test.dart';

void main() {
  group('node_codec — round-trips every Node shape', () {
    test('atoms pass through unchanged', () {
      for (final atom in ['ident', '"quoted"', 42, 3.14, true, false, null]) {
        expect(decodeNode(encodeNode(atom)), equals(atom));
      }
    });

    test('nested lists round-trip structurally', () {
      final node = [
        'class',
        'User',
        ['field', 'String', 'id'],
        ['method', 'toJson', []],
      ];
      expect(decodeNode(encodeNode(node)), equals(node));
    });

    test('a Splice round-trips to a Splice with equal contents', () {
      final decoded = decodeNode(encodeNode(Splice(['class A {}', 'class B {}'])));
      expect(decoded, isA<Splice>());
      expect((decoded as Splice).nodes, equals(['class A {}', 'class B {}']));
    });

    test('a Splice nested inside a list round-trips', () {
      final node = [
        'block',
        Splice([
          ['stmt', 1],
          ['stmt', 2],
        ]),
      ];
      final decoded = decodeNode(encodeNode(node)) as List;
      expect(decoded[0], equals('block'));
      expect(decoded[1], isA<Splice>());
      expect((decoded[1] as Splice).nodes, hasLength(2));
    });

    test('encoded form is plain primitives (isolate-sendable)', () {
      // No Splice instances should remain in the encoded tree — only
      // lists, maps, and atoms, which SendPort accepts.
      final encoded = encodeNode([
        'x',
        Splice(['y']),
      ]) as List;
      expect(encoded[1], isA<Map>());
      expect(encoded[1], isNot(isA<Splice>()));
    });
  });
}
