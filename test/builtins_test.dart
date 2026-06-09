import 'package:test/test.dart';
import 'package:dmacro/dmacro.dart';

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
      final result = expand([
        'unless',
        ['>', 'x', 0],
        'y'
      ]) as List;
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
      final result = expand([
        'when',
        ['>', 'x', 0],
        'y'
      ]) as List;
      final cond = result[1];
      expect(cond, isNot(isA<List>().having((l) => l[0], 'head', '!')));
    });
  });

  // ─── assert-that ─────────────────────────────────────────────────────────────

  group('assert-that', () {
    test('expands to [if, [!, expr], [throw, ...]]', () {
      final result = expand([
        'assert-that',
        ['>', 'x', 0]
      ]) as List;
      expect(result[0], equals('if'));
      // negated condition
      final cond = result[1] as List;
      expect(cond[0], equals('!'));
      // then-branch is a throw
      final body = result[2] as List;
      expect(body[0], equals('throw'));
    });

    test('throw message contains source expression', () {
      final result = expand([
        'assert-that',
        ['<=', 'amount', 1000000]
      ]) as List;
      final body = result[2] as List;
      final msg = body[1] as String;
      // The message should contain the emitted expression
      expect(msg, contains('amount'));
      expect(msg, contains('1000000'));
    });

    test('string literal in expression produces valid Dart (no unescaped quotes)', () {
      // email.contains("@") — the " inside must be escaped in the error string
      final out = emit(expand([
        'assert-that',
        ['.contains', 'email', '"@"']
      ]));
      // Count unescaped quotes: the string must be well-formed Dart
      // A simple proxy: after the opening AssertionError(" the next " must be the
      // closing one, not an unescaped quote from the expression.
      expect(out, contains(r'\"@\"'));
    });
  });

  // ─── with-retry ──────────────────────────────────────────────────────────────

  group('with-retry', () {
    test('expands to [for-in, ...]', () {
      final result = expand([
        'with-retry',
        3,
        ['print', '"try"']
      ]) as List;
      expect(result[0], equals('for-in'));
    });

    test('for-in body contains a try node', () {
      final result = expand(['with-retry', 3, 'body']) as List;
      // result = ['for-in', attemptVar, iterableExpr, tryNode]
      final tryNode = result[3] as List;
      expect(tryNode[0], equals('try'));
    });

    test('try body contains break so loop exits on success', () {
      final result = expand(['with-retry', 3, 'body']) as List;
      // tryNode = ['try', doNode, errVar, catchBody]
      final tryNode = result[3] as List;
      final tryBody = tryNode[1] as List;
      // try body is a 'do' containing the user body and 'break'
      expect(tryBody[0], equals('do'));
      expect(tryBody.last, equals('break'));
    });

    test('emitted output contains break inside try block', () {
      final out = emit(expand(['with-retry', 2, 'body']));
      expect(out, contains('break'));
      // break must appear before the closing brace of try (not after catch)
      final tryIdx = out.indexOf('try {');
      final catchIdx = out.indexOf('} catch (');
      final breakIdx = out.indexOf('break');
      expect(breakIdx, greaterThan(tryIdx));
      expect(breakIdx, lessThan(catchIdx));
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
        'defrecord',
        'Point',
        ['double', 'x'],
        ['double', 'y'],
      ]) as List;
      expect(result[0], equals('defclass'));
      expect(result[1], equals('Point'));
    });

    test(
        'generates 2 fields + ctor + copyWith + equalop + hashop + tostringop + fromjson + tojson',
        () {
      final result = expand([
        'defrecord',
        'Point',
        ['double', 'x'],
        ['double', 'y'],
      ]) as List;
      // args = members = defclass head + name + members...
      final members =
          result.sublist(2); // everything after 'defclass' and 'Point'
      // 2 fields + ctor + copywith + equalop + hashop + tostringop + fromjson + tojson = 9
      expect(members.length, equals(9));
    });

    test('field nodes have correct types and names', () {
      final result = expand([
        'defrecord',
        'Point',
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
        'defrecord',
        'Foo',
        ['int', 'a'],
      ]) as List;
      final members = result.sublist(2);
      final ctor = members[1] as List;
      expect(ctor[0], equals('ctor'));
      expect(ctor[1], equals('Foo'));
    });

    test('emits valid Dart class', () {
      final node = expand([
        'defrecord',
        'Point',
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
        'defunion',
        'Shape',
        [
          'Circle',
          ['double', 'radius']
        ],
        [
          'Square',
          ['double', 'side']
        ],
      ]) as List;
      expect(result[0], equals('do'));
    });

    test('first child is the sealed class string', () {
      final result = expand([
        'defunion',
        'Shape',
        [
          'Circle',
          ['double', 'radius']
        ],
        [
          'Square',
          ['double', 'side']
        ],
      ]) as List;
      final sealedDecl = result[1] as String;
      expect(sealedDecl, contains('sealed class Shape'));
    });

    test('subsequent children are variant defclass nodes', () {
      final result = expand([
        'defunion',
        'Shape',
        [
          'Circle',
          ['double', 'radius']
        ],
        [
          'Square',
          ['double', 'side']
        ],
      ]) as List;
      // ['do', 'sealed class Shape {}', circle_class, square_class]
      expect(result.length, equals(4)); // do + sealed + 2 variants
      final circleClass = result[2] as List;
      expect(circleClass[0], equals('defclass'));
      expect((circleClass[1] as String), contains('Circle'));
    });

    test('emits sealed class + variant classes', () {
      final node = expand([
        'defunion',
        'Shape',
        [
          'Circle',
          ['double', 'radius']
        ],
        [
          'Square',
          ['double', 'side']
        ],
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
      final result = expand([
        'do',
        ['swap!', 'a', 'b']
      ]) as List;
      // 'do' + let + set! + set! = 4 items
      expect(result[0], equals('do'));
      expect(result.length, equals(4)); // do + 3 spliced statements
    });

    test('swap! statements: let tmp = a, a = b, b = tmp', () {
      resetGensym();
      final result = expand([
        'do',
        ['swap!', 'a', 'b']
      ]) as List;
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
      final result = expand([
        'do',
        ['swap!', 'x', 'y']
      ]) as List;
      final stmt1 = result[1] as List;
      final tmp = stmt1[1] as String;
      expect(tmp, startsWith('__swap_'));
    });

    test('swap! works inside when (if branch context)', () {
      resetGensym();
      final result = expand([
        'when',
        ['>', 'a', 'b'],
        ['swap!', 'a', 'b']
      ]);
      // should be ['if', cond, splice-flattened...]
      // when → if; swap! inside if body gets spliced
      final out = emit(result);
      expect(out, contains('if'));
    });

    test('expand is idempotent after swap! splice', () {
      resetGensym();
      final form = [
        'do',
        ['swap!', 'a', 'b']
      ];
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

    test('tmp variable uses gensym (unique, starts with __)', () {
      resetGensym();
      final result = expand(['once', 'x', 'expr']) as List;
      final letNode = result[1] as List;
      final tmpName = letNode[1] as String;
      expect(tmpName, startsWith('__'));
    });

    test('two once macros use different tmp vars (no collision)', () {
      resetGensym();
      final r1 = expand(['once', 'a', 'exprA']) as List;
      final r2 = expand(['once', 'b', 'exprB']) as List;
      final tmp1 = (r1[1] as List)[1] as String;
      final tmp2 = (r2[1] as List)[1] as String;
      expect(tmp1, isNot(equals(tmp2)));
    });
  });

  // ─── macro aliases (camelCase ↔ kebab-case) ───────────────────────────────────

  group('macro aliases', () {
    test('assertThat (camelCase) is registered and works', () {
      final result = expand(['assertThat', ['>', 'x', 0]]) as List;
      expect(result[0], equals('if'));
      final cond = result[1] as List;
      expect(cond[0], equals('!'));
    });

    test('assert-that (kebab) and assertThat produce same expansion', () {
      final kebab = expand([
        'assert-that',
        ['>=', 'n', 0]
      ]);
      final camel = expand([
        'assertThat',
        ['>=', 'n', 0]
      ]);
      expect(emit(kebab), equals(emit(camel)));
    });

    test('withRetry (camelCase) is registered and works', () {
      final result = expand(['withRetry', 3, 'body']) as List;
      expect(result[0], equals('for-in'));
    });

    test('with-retry (kebab) and withRetry produce same structure', () {
      resetGensym();
      final kebab = expand(['with-retry', 3, 'body']);
      resetGensym();
      final camel = expand(['withRetry', 3, 'body']);
      expect(emit(kebab), equals(emit(camel)));
    });
  });

  // ─── defrecord — edge cases ───────────────────────────────────────────────────

  group('defrecord — edge cases', () {
    test('defrecord with no fields emits class with empty const ctor', () {
      final node = expand(['defrecord', 'Empty']);
      final out = emit(node);
      expect(out, contains('class Empty'));
      expect(out, contains('const Empty();'));
    });

    test('defrecord with no fields still has 9 members (0 fields)', () {
      final result = expand(['defrecord', 'Empty']) as List;
      final members = result.sublist(2);
      // 0 fields + ctor + copywith + equalop + hashop + tostringop + fromjson + tojson = 7
      expect(members.length, equals(7));
    });

    test('defrecord with single field', () {
      final node = expand(['defrecord', 'Wrapper', ['String', 'value']]);
      final out = emit(node);
      expect(out, contains('class Wrapper'));
      expect(out, contains('final String value;'));
      expect(out, contains('const Wrapper({required this.value})'));
    });

    test('defrecord with nullable field has no required keyword in ctor', () {
      final node =
          expand(['defrecord', 'Box', ['String', 'id'], ['String?', 'label']]);
      final out = emit(node);
      expect(out, contains('required this.id'));
      expect(out, isNot(contains('required this.label')));
      expect(out, contains('this.label'));
    });

    test('defrecord emits fromJson and toJson', () {
      final node = expand(['defrecord', 'Item', ['int', 'n']]);
      final out = emit(node);
      expect(out, contains('factory Item.fromJson'));
      expect(out, contains('Map<String, dynamic> toJson()'));
    });

    test('defrecord copyWith non-nullable uses ?? this.field', () {
      final node = expand(['defrecord', 'Pt', ['double', 'x']]);
      final out = emit(node);
      expect(out, contains('x ?? this.x'));
    });

    test('defrecord copyWith nullable uses _dmUndefined sentinel', () {
      final node = expand(['defrecord', 'Pt', ['double?', 'z']]);
      final out = emit(node);
      expect(out, contains('_dmUndefined'));
      expect(out, contains('identical(z, _dmUndefined)'));
    });

    test('defrecord with List field uses _dmEq in ==', () {
      final node =
          expand(['defrecord', 'Foo', ['List<String>', 'items']]);
      final out = emit(node);
      expect(out, contains('_dmEq(other.items, items)'));
    });
  });

  // ─── defunion — edge cases ────────────────────────────────────────────────────

  group('defunion — edge cases', () {
    test('sealed parent class has const constructor', () {
      final result = expand([
        'defunion',
        'Expr',
        ['Num', ['int', 'value']],
      ]) as List;
      final sealedDecl = result[1] as String;
      expect(sealedDecl, contains('const Expr()'));
    });

    test('single-variant defunion works', () {
      final node = expand([
        'defunion',
        'Result',
        ['Ok', ['String', 'value']],
      ]);
      final out = emit(node);
      expect(out, contains('sealed class Result'));
      expect(out, contains('class Ok extends Result'));
    });

    test('variant class name includes extends parent', () {
      final result = expand([
        'defunion',
        'Shape',
        ['Circle', ['double', 'r']],
        ['Square', ['double', 's']],
      ]) as List;
      final circle = result[2] as List;
      expect((circle[1] as String), contains('extends Shape'));
    });

    test('variant with no fields has empty const ctor', () {
      final node = expand([
        'defunion',
        'Token',
        ['TkEof'],
      ]);
      final out = emit(node);
      expect(out, contains('const TkEof'));
    });

    test('defunion emits valid Dart with 3 variants', () {
      final node = expand([
        'defunion',
        'Msg',
        ['Start', ['String', 'id']],
        ['Stop'],
        ['Error', ['String', 'msg']],
      ]);
      final out = emit(node);
      expect(out, contains('sealed class Msg'));
      expect(out, contains('class Start extends Msg'));
      expect(out, contains('class Stop extends Msg'));
      expect(out, contains('class Error extends Msg'));
    });
  });

  // ─── defunion — value semantics ──────────────────────────────────────────────

  group('defunion — value semantics', () {
    test('variant emits copyWith', () {
      final out = emit(expand([
        'defunion',
        'Shape',
        ['Circle', ['double', 'radius']],
      ]));
      expect(out, contains('copyWith'));
    });

    test('variant emits == override', () {
      final out = emit(expand([
        'defunion',
        'Shape',
        ['Circle', ['double', 'radius']],
      ]));
      expect(out, contains('operator =='));
    });

    test('variant emits hashCode override', () {
      final out = emit(expand([
        'defunion',
        'Shape',
        ['Circle', ['double', 'radius']],
      ]));
      expect(out, contains('hashCode'));
    });

    test('variant emits toString override', () {
      final out = emit(expand([
        'defunion',
        'Shape',
        ['Circle', ['double', 'radius']],
      ]));
      expect(out, contains('toString()'));
    });

    test('== uses the variant name, not the sealed parent name', () {
      final out = emit(expand([
        'defunion',
        'Shape',
        ['Circle', ['double', 'radius']],
      ]));
      expect(out, contains('other is Circle'));
      expect(out, isNot(contains('other is Shape')));
    });

    test('no-field variant has valid == without trailing &&', () {
      final out = emit(expand([
        'defunion',
        'Token',
        ['TkEof'],
      ]));
      // Should not emit dangling '&& ;'
      expect(out, isNot(contains('&& ;')));
      expect(out, contains('other is TkEof'));
    });
  });

  // ─── equalop — empty fields ───────────────────────────────────────────────────

  group('equalop — empty fields', () {
    test('defrecord with no fields has valid == (no trailing &&)', () {
      final out = emit(expand(['defrecord', 'Empty']));
      expect(out, isNot(contains('&& ;')));
      expect(out, contains('other is Empty'));
    });
  });

  // ─── assert-that — more cases ────────────────────────────────────────────────

  group('assert-that — more cases', () {
    test('message contains the emitted expression source', () {
      final result = expand([
        'assert-that',
        ['&&', ['>', 'x', 0], ['<', 'x', 100]]
      ]) as List;
      final body = result[2] as List;
      final msg = body[1] as String;
      expect(msg, contains('x'));
      expect(msg, contains('100'));
    });

    test('emits valid if-throw Dart', () {
      final out = emit(expand([
        'assert-that',
        ['!=', 'ptr', null]
      ]));
      expect(out, contains('if'));
      expect(out, contains('throw'));
      expect(out, contains('AssertionError'));
    });
  });

  // ─── with-retry — more cases ─────────────────────────────────────────────────

  group('with-retry — more cases', () {
    test('n=1 means exactly one attempt before re-throw', () {
      resetGensym();
      final result = expand(['with-retry', 1, 'body']) as List;
      final tryNode = result[3] as List;
      // catch body: if attempt == (n-1) throw else print
      final catchBody = tryNode[3] as List;
      expect(catchBody[0], equals('if'));
    });

    test('loop variable and error variable are different gensyms', () {
      resetGensym();
      final result = expand(['with-retry', 2, 'body']) as List;
      final loopVar = result[1] as String;
      final tryNode = result[3] as List;
      final errVar = tryNode[2] as String;
      expect(loopVar, isNot(equals(errVar)));
    });
  });

  // ─── and-let — edge cases ────────────────────────────────────────────────────

  group('and-let — edge cases', () {
    test('three bindings nest three levels deep', () {
      final result = expand([
        'and-let',
        ['a', 1],
        ['b', 2],
        ['c', 3],
        'body',
      ]) as List;
      // outer: do [let a 1] inner
      // inner: do [let b 2] inner2
      // inner2: do [let c 3] body
      expect(result[0], equals('do'));
      final outerLet = result[1] as List;
      expect(outerLet[1], equals('a'));
      // verify nesting
      final inner = result[2] as List;
      expect(inner[0], equals('do'));
    });

    test('body is preserved as-is', () {
      final result = expand([
        'and-let',
        ['x', 42],
        'body_node',
      ]) as List;
      expect(result[2], equals('body_node'));
    });
  });
}
