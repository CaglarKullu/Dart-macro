import 'package:test/test.dart';
import 'package:dart_macros/dart_macros.dart';

void main() {
  setUpAll(registerBuiltins);

  group('expand', () {
    test('atom passes through unchanged', () {
      expect(expand('hello'), equals('hello'));
      expect(expand(42), equals(42));
      expect(expand(true), equals(true));
    });

    test('unknown form passes through unchanged', () {
      final input = ['unknown', 'a', 'b'];
      expect(expand(input), equals(input));
    });

    test('unless macro expands', () {
      final input = ['unless', ['>', 'balance', 0], ['print', '"negative"']];
      final result = expand(input) as List;
      expect(result.first, equals('if'));
    });

    test('expand is idempotent', () {
      final input = ['unless', ['>', 'x', 0], ['print', '"x"']];
      expect(expand(expand(input)), equals(expand(input)));
    });
  });

  group('emit', () {
    test('emits atom', () {
      expect(emit('hello'), equals('hello'));
      expect(emit(42), equals('42'));
    });

    test('emits if statement', () {
      final node = ['if', 'cond', 'then', 'else'];
      final out = emit(node);
      expect(out, contains('if (cond)'));
      expect(out, contains('then'));
      expect(out, contains('else'));
    });
  });
}
