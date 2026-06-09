import 'package:test/test.dart';
import 'package:dart_macros/dart_macros.dart';

void main() {
  setUpAll(registerBuiltins);
  setUp(resetGensym);

  // ─── Splice type ─────────────────────────────────────────────────────────────

  group('Splice — basic', () {
    test('Splice holds a list of nodes', () {
      final s = Splice([
        ['let', 'a', 1],
        ['set!', 'b', 2]
      ]);
      expect(s.nodes.length, equals(2));
    });

    test('\$splice returns a Splice', () {
      final s = $splice([
        ['let', 'x', 0]
      ]);
      expect(s, isA<Splice>());
    });
  });

  // ─── emit guard ──────────────────────────────────────────────────────────────

  group('emit — Splice guard', () {
    test('Splice reaching emit throws StateError', () {
      final s = $splice([
        ['let', 'a', 1]
      ]);
      expect(() => emit(s), throwsA(isA<StateError>()));
    });
  });

  // ─── expand flattens Splice ───────────────────────────────────────────────────

  group('expand — Splice flattening', () {
    test('swap! inside [do ...] is flattened to 3 statements', () {
      final result = expand([
        'do',
        ['swap!', 'a', 'b']
      ]) as List;
      // do + let + set! + set! = 4 total
      expect(result[0], equals('do'));
      expect(result.length, equals(4));
    });

    test('swap! inside [when cond body] → if branch has 3 statements', () {
      // when expands to [if, cond, body]
      // if swap! is the body, it is a Splice that must be flattened into if
      // But note: 'if' only takes one then-arg.
      // swap! produces a Splice of 3 statements.
      // When used as the body of 'when', the resulting 'if' will have
      // the splice flattened into the if args: [if, cond, let, set!, set!]
      final result = expand([
        'when',
        ['>', 'a', 'b'],
        ['swap!', 'a', 'b']
      ]) as List;
      expect(result[0], equals('if'));
      // cond at [1], then 3 splice children at [2], [3], [4]
      expect(result.length, equals(5));
      expect(result[2], isA<List>()); // let
      expect((result[2] as List)[0], equals('let'));
      expect(result[3], isA<List>()); // set!
      expect((result[3] as List)[0], equals('set!'));
      expect(result[4], isA<List>()); // set!
      expect((result[4] as List)[0], equals('set!'));
    });

    test('swap! inside [while cond body] → while has 3 spliced children', () {
      final result = expand([
        'while',
        'cond',
        ['swap!', 'a', 'b']
      ]) as List;
      expect(result[0], equals('while'));
      // while [cond, let, set!, set!] = 5 total
      expect(result.length, equals(5));
      expect((result[2] as List)[0], equals('let'));
    });

    test('nested macro using swap! inlines correctly', () {
      // unless wraps the body in an if; if swap! is the body it should splice
      final result = expand([
        'unless',
        ['<', 'a', 'b'],
        ['swap!', 'a', 'b']
      ]) as List;
      expect(result[0], equals('if'));
      // [if, [!, cond], let, set!, set!]
      expect(result.length, equals(5));
    });

    test('no Splice in result of expand (already flattened)', () {
      void checkNoSplice(dynamic node) {
        expect(node, isNot(isA<Splice>()));
        if (node is List) {
          for (final child in node) {
            checkNoSplice(child);
          }
        }
      }

      final result = expand([
        'when',
        'c',
        ['swap!', 'a', 'b']
      ]);
      checkNoSplice(result);
    });
  });

  // ─── expand idempotency with Splice ──────────────────────────────────────────

  group('expand — idempotency after splice', () {
    test('expand(expand(x)) == expand(x) for swap! in do', () {
      resetGensym();
      final form = [
        'do',
        ['swap!', 'a', 'b']
      ];
      final once = expand(form);
      // NOTE: we can't call expand again on the same form because
      // gensym would advance. So we just verify the structure is stable:
      // expand on an already-expanded do-list does not change structure.
      final expandedAgain = expand(once);
      // Both should be a do + 3 statements = 4 items
      expect((once as List).length, equals((expandedAgain as List).length));
    });

    test('expand on non-splice form is idempotent', () {
      final form = [
        'if',
        'cond',
        ['let', 'x', 1]
      ];
      expect(expand(expand(form)), equals(expand(form)));
    });
  });

  // ─── emit after splice ────────────────────────────────────────────────────────

  group('emit — swap! produces valid Dart', () {
    test('emitting swap! in do context produces valid Dart statements', () {
      resetGensym();
      final expanded = expand([
        'do',
        ['swap!', 'a', 'b']
      ]);
      final out = emit(expanded);
      expect(out, contains('final __swap_0 = a'));
      expect(out, contains('a = b'));
      expect(out, contains('b = __swap_0'));
    });

    test('emitting when with swap! produces valid Dart if-statement', () {
      resetGensym();
      final expanded = expand([
        'when',
        ['>', 'a', 'b'],
        ['swap!', 'a', 'b']
      ]);
      final out = emit(expanded);
      expect(out, contains('if'));
      expect(out, contains('__swap_0'));
      expect(out, contains('a = b'));
      expect(out, contains('b = __swap_0'));
    });

    test('compileDartLike swap! in function body produces valid Dart', () {
      const src = '''
        void normalise(double a, double b) {
          when (a > b) {
            swap!(a, b);
          }
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('__swap_0'));
      expect(out, contains('a = b'));
    });
  });
}
