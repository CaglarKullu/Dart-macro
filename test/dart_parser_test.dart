import 'package:test/test.dart';
import 'package:dmacro/dmacro.dart';

void main() {
  setUpAll(registerBuiltins);

  // ─── defrecord ────────────────────────────────────────────────────────────────

  group('DartLikeParser — defrecord', () {
    test('parses defrecord with simple fields', () {
      const src = '''
        defrecord Point {
          double x;
          double y;
        }
      ''';
      final tokens = Tokenizer(src).tokenize();
      final forms = DartLikeParser(tokens).parseProgram();
      expect(forms.length, equals(1));
      final form = forms[0] as List;
      expect(form[0], equals('defrecord'));
      expect(form[1], equals('Point'));
    });

    test('defrecord field list is correct', () {
      const src = '''
        defrecord Payment {
          double amount;
          String currency;
        }
      ''';
      final tokens = Tokenizer(src).tokenize();
      final forms = DartLikeParser(tokens).parseProgram();
      final form = forms[0] as List;
      // ['defrecord', 'Payment', ['double','amount', lineNum], ['String','currency', lineNum]]
      expect(form.length, equals(4));
      final f1 = form[2] as List;
      final f2 = form[3] as List;
      // Fields now carry a source line number as a third element.
      expect(f1.sublist(0, 2), equals(['double', 'amount']));
      expect(f1[2], isA<int>()); // line number
      expect(f2.sublist(0, 2), equals(['String', 'currency']));
      expect(f2[2], isA<int>()); // line number
    });

    test('defrecord with nullable field', () {
      const src = '''
        defrecord Foo {
          String? ref;
        }
      ''';
      final tokens = Tokenizer(src).tokenize();
      final forms = DartLikeParser(tokens).parseProgram();
      final form = forms[0] as List;
      final field = form[2] as List;
      expect(field[0], equals('String?'));
      expect(field[1], equals('ref'));
    });

    test('defrecord expands and emits valid Dart class', () {
      const src = '''
        defrecord Payment {
          double amount;
          String currency;
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('class Payment'));
      expect(out, contains('final double amount;'));
      expect(out, contains('final String currency;'));
      expect(out, contains('copyWith'));
      expect(out, contains('operator =='));
      expect(out, contains('hashCode'));
      expect(out, contains('toString()'));
    });
  });

  // ─── function declaration ─────────────────────────────────────────────────────

  group('DartLikeParser — function declaration', () {
    test('parses simple void function', () {
      const src = 'void hello() {}';
      final tokens = Tokenizer(src).tokenize();
      final forms = DartLikeParser(tokens).parseProgram();
      final form = forms[0] as List;
      expect(form[0], equals('defn'));
      expect(form[1], equals('void'));
      expect(form[2], equals('hello'));
    });

    test('parses function with parameters', () {
      const src = 'int add(int a, int b) { return a; }';
      final tokens = Tokenizer(src).tokenize();
      final forms = DartLikeParser(tokens).parseProgram();
      final form = forms[0] as List;
      expect(form[0], equals('defn'));
      final params = form[3] as List;
      expect(params.length, equals(2));
      expect(params[0], equals(['int', 'a']));
      expect(params[1], equals(['int', 'b']));
    });

    test('parses return statement', () {
      const src = 'int foo() { return 42; }';
      final tokens = Tokenizer(src).tokenize();
      final forms = DartLikeParser(tokens).parseProgram();
      final form = forms[0] as List;
      final body = form[4] as List;
      expect(body[0], equals('return'));
      expect(body[1], equals(42));
    });

    test('parses throw statement', () {
      const src = 'void foo() { throw Exception("e"); }';
      final tokens = Tokenizer(src).tokenize();
      final forms = DartLikeParser(tokens).parseProgram();
      final form = forms[0] as List;
      final body = form[4] as List;
      expect(body[0], equals('throw'));
    });
  });

  // ─── unless macro in dart-like syntax ────────────────────────────────────────

  group('DartLikeParser — macros in Dart-like syntax', () {
    test('unless compiles to if with negation', () {
      const src = '''
        bool validate(double amount) {
          unless (amount > 0) {
            throw Exception("bad");
          }
          return true;
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('if'));
      expect(out, contains('!'));
    });

    test('when compiles to if without negation', () {
      const src = '''
        void check(int x) {
          when (x > 0) {
            return x;
          }
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('if'));
    });
  });

  // ─── expressions ──────────────────────────────────────────────────────────────

  group('DartLikeParser — expressions', () {
    test('parses binary arithmetic', () {
      const src = 'int foo() { return a + b; }';
      final tokens = Tokenizer(src).tokenize();
      final forms = DartLikeParser(tokens).parseProgram();
      final form = forms[0] as List;
      final ret = form[4] as List;
      expect(ret[0], equals('return'));
      final expr = ret[1] as List;
      expect(expr[0], equals('+'));
    });

    test('parses comparison operator', () {
      const src = 'bool foo() { return a > b; }';
      final tokens = Tokenizer(src).tokenize();
      final forms = DartLikeParser(tokens).parseProgram();
      final form = forms[0] as List;
      final ret = form[4] as List;
      final expr = ret[1] as List;
      expect(expr[0], equals('>'));
    });

    test('parses method call with dot notation', () {
      const src = 'void foo() { list.add(x); }';
      final tokens = Tokenizer(src).tokenize();
      final forms = DartLikeParser(tokens).parseProgram();
      final form = forms[0] as List;
      final call = form[4] as List;
      expect(call[0], equals('.add'));
    });

    test('parses property access', () {
      const src = 'void foo() { return list.length; }';
      final tokens = Tokenizer(src).tokenize();
      final forms = DartLikeParser(tokens).parseProgram();
      final form = forms[0] as List;
      final ret = form[4] as List;
      final prop = ret[1] as List;
      expect(prop[0], equals('.-length'));
    });
  });

  // ─── let/var/set! ────────────────────────────────────────────────────────────

  group('DartLikeParser — bindings and assignment', () {
    test('parses final binding', () {
      const src = 'void foo() { final x = 1; }';
      final tokens = Tokenizer(src).tokenize();
      final forms = DartLikeParser(tokens).parseProgram();
      final form = forms[0] as List;
      final stmt = form[4] as List;
      expect(stmt[0], equals('let'));
      expect(stmt[1], equals('x'));
      expect(stmt[2], equals(1));
    });

    test('parses var binding', () {
      const src = 'void foo() { var x = 2; }';
      final tokens = Tokenizer(src).tokenize();
      final forms = DartLikeParser(tokens).parseProgram();
      final form = forms[0] as List;
      final stmt = form[4] as List;
      expect(stmt[0], equals('var'));
      expect(stmt[1], equals('x'));
    });

    test('parses assignment (set!)', () {
      const src = 'void foo() { x = 99; }';
      final tokens = Tokenizer(src).tokenize();
      final forms = DartLikeParser(tokens).parseProgram();
      final form = forms[0] as List;
      final stmt = form[4] as List;
      expect(stmt[0], equals('set!'));
      expect(stmt[1], equals('x'));
      expect(stmt[2], equals(99));
    });
  });

  // ─── errors ──────────────────────────────────────────────────────────────────

  group('DartLikeParser — errors', () {
    test('throws ParseException on unexpected token', () {
      // A standalone expression that is not a valid declaration
      expect(
        () {
          final tokens = Tokenizer('123').tokenize();
          DartLikeParser(tokens).parseProgram();
        },
        throwsA(isA<ParseException>()),
      );
    });

    test('throws ParseException on missing closing brace', () {
      expect(
        () {
          final tokens = Tokenizer('void foo() { return 1;').tokenize();
          DartLikeParser(tokens).parseProgram();
        },
        throwsA(isA<ParseException>()),
      );
    });
  });

  // ─── compileDartLike() end-to-end ────────────────────────────────────────────

  group('compileDartLike() — end-to-end', () {
    test('compiles Payment defrecord to valid Dart', () {
      const src = '''
        defrecord Payment {
          double amount;
          String currency;
          String? reference;
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('class Payment'));
      expect(out, contains('final String? reference;'));
    });

    test('compileDartLike is deterministic', () {
      const src = 'void foo() { return 1; }';
      expect(compileDartLike(src), equals(compileDartLike(src)));
    });

    test('compiles function with unless macro', () {
      const src = '''
        bool validatePayment(double amount) {
          unless (amount > 0) {
            throw Exception("bad");
          }
          return true;
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('bool validatePayment'));
      expect(out, contains('return true'));
    });
  });

  // ─── defmacro ────────────────────────────────────────────────────────────────

  group('DartLikeParser — defmacro', () {
    setUp(resetGensym);

    test('parses defmacro declaration', () {
      const src = '''
        defmacro double(x) {
          return x * 2;
        }
      ''';
      final tokens = Tokenizer(src).tokenize();
      final forms = DartLikeParser(tokens).parseProgram();
      expect(forms.length, equals(1));
      final form = forms[0] as List;
      expect(form[0], equals('defmacro'));
      expect(form[1], equals('double'));
      expect(form[2], equals(['x']));
    });

    test('defmacro registers and expands in compileDartLike', () {
      const src = '''
        defmacro twice(x) {
          return x + x;
        }
        int foo(int n) {
          twice(n);
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('n + n'));
      expect(out, isNot(contains('class')));
    });

    test('defmacro with multiple params', () {
      const src = '''
        defmacro add(a, b) {
          return a + b;
        }
        int bar(int x, int y) {
          add(x, y);
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('x + y'));
    });

    test('defmacro produces no Dart output for its own declaration', () {
      const src = '''
        defmacro noop(x) {
          return x;
        }
      ''';
      final out = compileDartLike(src);
      // The defmacro declaration itself produces no Dart output
      expect(out.trim(), isEmpty);
    });
  });
}
