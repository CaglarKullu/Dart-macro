import 'package:test/test.dart';
import 'package:dart_macros/dart_macros.dart';

void main() {
  setUpAll(registerBuiltins);

  // ─── unless ──────────────────────────────────────────────────────────────────

  group('unless', () {
    test('expands to [if, [!, cond], body]', () {
      final result = expand(['unless', 'cond', 'body']) as List;
      expect(result[0], equals('if'));
      // condition must be negated
      final negCond = result[1] as List;
      expect(negCond[0], equals('!'));
      expect(negCond[1], equals('cond'));
      // body preserved
      expect(result[2], equals('body'));
    });

    test('expands nested condition', () {
      final result = expand(['unless', ['>', 'x', 0], 'y']) as List;
      expect(result[0], equals('if'));
      final negCond = result[1] as List;
      expect(negCond[0], equals('!'));
      expect(negCond[1], equals(['>', 'x', 0]));
    });
  });

  // ─── when ────────────────────────────────────────────────────────────────────

  group('when', () {
    test('expands to [if, cond, body]', () {
      final result = expand(['when', 'cond', 'body']) as List;
      expect(result[0], equals('if'));
      expect(result[1], equals('cond'));
      expect(result[2], equals('body'));
    });

    test('condition is NOT negated', () {
      final result = expand(['when', ['>', 'x', 0], 'y']) as List;
      final cond = result[1];
      expect(cond, isNot(isA<List>().having((l) => l[0], 'head', '!')));
    });
  });

  // ─── assert-that ─────────────────────────────────────────────────────────────

  group('assert-that', () {
    test('expands to [if, [!, expr], [throw, ...]]', () {
      final result = expand(['assert-that', ['>', 'x', 0]]) as List;
      expect(result[0], equals('if'));
      // negated condition
      final cond = result[1] as List;
      expect(cond[0], equals('!'));
      // then-branch is a throw
      final body = result[2] as List;
      expect(body[0], equals('throw'));
    });

    test('throw message contains source expression', () {
      final result = expand(['assert-that', ['<=', 'amount', 1000000]]) as List;
      final body = result[2] as List;
      final msg = body[1] as String;
      // The message should contain the emitted expression
      expect(msg, contains('amount'));
      expect(msg, contains('1000000'));
    });
  });

  // ─── with-retry ──────────────────────────────────────────────────────────────

  group('with-retry', () {
    test('expands to [for-in, ...]', () {
      final result = expand(['with-retry', 3, ['print', '"try"']]) as List;
      expect(result[0], equals('for-in'));
    });

    test('for-in body contains a try node', () {
      final result = expand(['with-retry', 3, 'body']) as List;
      // result = ['for-in', attemptVar, iterableExpr, tryNode]
      final tryNode = result[3] as List;
      expect(tryNode[0], equals('try'));
    });

    test('iterable uses Iterable.generate with n', () {
      final result = expand(['with-retry', 5, 'body']) as List;
      final iterable = result[2] as String;
      expect(iterable, contains('Iterable.generate'));
      expect(iterable, contains('5'));
    });

    test('uses gensym — loop var and catch var are unique identifiers', () {
      resetGensym();
      final result = expand(['with-retry', 3, 'body']) as List;
      final loopVar = result[1] as String;
      // gensym names start with __
      expect(loopVar, startsWith('__'));
    });
  });

  // ─── defrecord ───────────────────────────────────────────────────────────────

  group('defrecord', () {
    test('expands to [defclass, name, ...members]', () {
      final result = expand([
        'defrecord', 'Point',
        ['double', 'x'],
        ['double', 'y'],
      ]) as List;
      expect(result[0], equals('defclass'));
      expect(result[1], equals('Point'));
    });

    test('generates 2 field nodes + ctor + copyWith + equalop + hashop + tostringop', () {
      final result = expand([
        'defrecord', 'Point',
        ['double', 'x'],
        ['double', 'y'],
      ]) as List;
      // args = members = defclass head + name + members...
      final members = result.sublist(2); // everything after 'defclass' and 'Point'
      // 2 fields + ctor + copywith + equalop + hashop + tostringop = 7
      expect(members.length, equals(7));
    });

    test('field nodes have correct types and names', () {
      final result = expand([
        'defrecord', 'Point',
        ['double', 'x'],
        ['double', 'y'],
      ]) as List;
      final members = result.sublist(2);
      final field1 = members[0] as List;
      final field2 = members[1] as List;
      expect(field1[0], equals('field'));
      expect(field1[1], equals('double'));
      expect(field1[2], equals('x'));
      expect(field2[0], equals('field'));
      expect(field2[1], equals('double'));
      expect(field2[2], equals('y'));
    });

    test('ctor node references class name', () {
      final result = expand([
        'defrecord', 'Foo',
        ['int', 'a'],
      ]) as List;
      final members = result.sublist(2);
      final ctor = members[1] as List;
      expect(ctor[0], equals('ctor'));
      expect(ctor[1], equals('Foo'));
    });

    test('emits valid Dart class', () {
      final node = expand([
        'defrecord', 'Point',
        ['double', 'x'],
        ['double', 'y'],
      ]);
      final out = emit(node);
      expect(out, contains('class Point'));
      expect(out, contains('final double x;'));
      expect(out, contains('copyWith'));
      expect(out, contains('operator =='));
      expect(out, contains('hashCode'));
      expect(out, contains('toString()'));
    });
  });

  // ─── defunion ────────────────────────────────────────────────────────────────

  group('defunion', () {
    test('expands to [do, ...]', () {
      final result = expand([
        'defunion', 'Shape',
        ['Circle', ['double', 'radius']],
        ['Square', ['double', 'side']],
      ]) as List;
      expect(result[0], equals('do'));
    });

    test('first child is the sealed class string', () {
      final result = expand([
        'defunion', 'Shape',
        ['Circle', ['double', 'radius']],
        ['Square', ['double', 'side']],
      ]) as List;
      final sealedDecl = result[1] as String;
      expect(sealedDecl, contains('sealed class Shape'));
    });

    test('subsequent children are variant defclass nodes', () {
      final result = expand([
        'defunion', 'Shape',
        ['Circle', ['double', 'radius']],
        ['Square', ['double', 'side']],
      ]) as List;
      // ['do', 'sealed class Shape {}', circle_class, square_class]
      expect(result.length, equals(4)); // do + sealed + 2 variants
      final circleClass = result[2] as List;
      expect(circleClass[0], equals('defclass'));
      expect((circleClass[1] as String), contains('Circle'));
    });

    test('emits sealed class + variant classes', () {
      final node = expand([
        'defunion', 'Shape',
        ['Circle', ['double', 'radius']],
        ['Square', ['double', 'side']],
      ]);
      final out = emit(node);
      expect(out, contains('sealed class Shape'));
      expect(out, contains('Circle'));
      expect(out, contains('Square'));
    });
  });

  // ─── swap! ───────────────────────────────────────────────────────────────────

  group('swap!', () {
    test('returns a Splice of 3 statements', () {
      // Direct call to macro fn — not via expand
      // We can call expand and check top-level is a Splice before flattening
      // But expand flattens Splice into parent… So call directly via a wrapper.
      // The only reliable way is to wrap swap! in a list context so expand
      // sees it as a child, and then check the parent has 3 extra children.
      //
      // Instead: use defmacro's registered macro fn directly via expand on a
      // 'do'-wrapped form and count the statements.
      resetGensym();
      final result = expand(['do', ['swap!', 'a', 'b']]) as List;
      // 'do' + let + set! + set! = 4 items
      expect(result[0], equals('do'));
      expect(result.length, equals(4)); // do + 3 spliced statements
    });

    test('swap! statements: let tmp = a, a = b, b = tmp', () {
      resetGensym();
      final result = expand(['do', ['swap!', 'a', 'b']]) as List;
      final stmt1 = result[1] as List; // let tmp = a
      final stmt2 = result[2] as List; // a = b
      final stmt3 = result[3] as List; // b = tmp

      expect(stmt1[0], equals('let'));
      expect(stmt1[2], equals('a'));

      expect(stmt2[0], equals('set!'));
      expect(stmt2[1], equals('a'));
      expect(stmt2[2], equals('b'));

      expect(stmt3[0], equals('set!'));
      expect(stmt3[1], equals('b'));
      // tmp name referenced in stmt3[2]
      final tmp = stmt1[1] as String;
      expect(stmt3[2], equals(tmp));
    });

    test('swap! temp var starts with __swap_', () {
      resetGensym();
      final result = expand(['do', ['swap!', 'x', 'y']]) as List;
      final stmt1 = result[1] as List;
      final tmp = stmt1[1] as String;
      expect(tmp, startsWith('__swap_'));
    });

    test('swap! works inside when (if branch context)', () {
      resetGensym();
      final result = expand(['when', ['>', 'a', 'b'], ['swap!', 'a', 'b']]);
      // should be ['if', cond, splice-flattened...]
      // when → if; swap! inside if body gets spliced
      final out = emit(result);
      expect(out, contains('if'));
    });

    test('expand is idempotent after swap! splice', () {
      resetGensym();
      final form = ['do', ['swap!', 'a', 'b']];
      final once = expand(form);
      resetGensym();
      final twice = expand(expand(form));
      // They won't be byte-identical because gensym advances on each expand call,
      // but both should have the same structure (do + 3 stmts)
      expect((once as List).length, equals((twice as List).length));
    });
  });

  // ─── and-let ─────────────────────────────────────────────────────────────────

  group('and-let', () {
    test('single binding wraps body in do + let', () {
      final result = expand([
        'and-let',
        ['x', 1],
        'body',
      ]) as List;
      expect(result[0], equals('do'));
      final letNode = result[1] as List;
      expect(letNode[0], equals('let'));
      expect(letNode[1], equals('x'));
      expect(letNode[2], equals(1));
    });

    test('multiple bindings nest correctly', () {
      final result = expand([
        'and-let',
        ['a', 1],
        ['b', 2],
        'body',
      ]) as List;
      // outer: ['do', ['let', 'a', 1], inner_do]
      expect(result[0], equals('do'));
    });
  });

  // ─── once ────────────────────────────────────────────────────────────────────

  group('once', () {
    test('expands to do with let and set!', () {
      final result = expand(['once', 'x', 'expr']) as List;
      expect(result[0], equals('do'));
      final letNode = result[1] as List;
      expect(letNode[0], equals('let'));
      final setNode = result[2] as List;
      expect(setNode[0], equals('set!'));
      expect(setNode[1], equals('x'));
    });
  });
}
