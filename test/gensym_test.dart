import 'package:test/test.dart';
import 'package:dmacro/dmacro.dart';

void main() {
  setUp(resetGensym);

  group('gensym — uniqueness', () {
    test('successive calls return different names', () {
      final a = gensym('x');
      final b = gensym('x');
      expect(a, isNot(equals(b)));
    });

    test('names use dm prefix with capitalised prefix and no leading underscore',
        () {
      final name = gensym('swap');
      expect(name, startsWith('dmSwap_'));
      expect(name, isNot(startsWith('_')));
    });

    test('default prefix is g', () {
      final name = gensym();
      expect(name, startsWith('dmG_'));
    });

    test('counter increments across different prefixes', () {
      final a = gensym('foo'); // dmFoo_0
      final b = gensym('bar'); // dmBar_1
      expect(a, contains('0'));
      expect(b, contains('1'));
    });
  });

  group('gensym — resetGensym', () {
    test('reset makes counter restart from 0', () {
      gensym();
      gensym();
      gensym();
      resetGensym();
      expect(gensym('x'), equals('dmX_0'));
    });

    test('same source compiles to identical output after reset', () {
      registerBuiltins();
      const src = '(let x 1)';
      resetGensym();
      final first = compile(src);
      resetGensym();
      final second = compile(src);
      expect(first, equals(second));
    });
  });

  group('gensym — collision safety', () {
    test('swap! temp does not collide with a pre-burned dmSwap_0', () {
      registerBuiltins();
      // Burn dmSwap_0 so the macro must use a later name
      gensym('swap'); // dmSwap_0 taken

      final parent = expand([
        'do',
        ['swap!', 'a', 'b']
      ]) as List;
      final letStmt = parent[1] as List;
      final tmp = letStmt[1] as String;
      expect(tmp, isNot(equals('dmSwap_0')));
      expect(tmp, startsWith('dmSwap_'));
    });

    test('compile() calls resetGensym() — repeated calls are deterministic',
        () {
      registerBuiltins();
      const src = '(do (let x 1) (let y 2))';
      final out1 = compile(src);
      final out2 = compile(src);
      expect(out1, equals(out2));
    });
  });
}
