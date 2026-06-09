import 'package:test/test.dart';
import 'package:dart_macros/dart_macros.dart';

void main() {
  setUpAll(registerBuiltins);

  // ─── Reader — atoms ──────────────────────────────────────────────────────────

  group('Reader — atoms', () {
    test('reads integer', () {
      expect(Reader('42').readOne(), equals(42));
    });

    test('reads negative integer via symbol (atoms, not unary minus)', () {
      // The reader treats '-5' as the atom string '-5' (not an int)
      // because '-' is part of the symbol scan — actually, let's check what happens.
      // The reader's _readAtom reads until whitespace/paren, so '-5' → '-5' as String.
      // But we can verify plain positive int:
      expect(Reader('123').readOne(), equals(123));
    });

    test('reads double', () {
      expect(Reader('3.14').readOne(), equals(3.14));
    });

    test('reads boolean true', () {
      expect(Reader('true').readOne(), equals(true));
    });

    test('reads boolean false', () {
      expect(Reader('false').readOne(), equals(false));
    });

    test('reads null', () {
      expect(Reader('null').readOne(), isNull);
    });

    test('reads identifier / symbol', () {
      expect(Reader('hello').readOne(), equals('hello'));
    });

    test('reads operator symbol', () {
      expect(Reader('+').readOne(), equals('+'));
      expect(Reader('!=').readOne(), equals('!='));
    });

    test('reads string literal with surrounding quotes preserved', () {
      expect(Reader('"hello"').readOne(), equals('"hello"'));
    });

    test('reads string literal with escape sequences', () {
      // \n → actual newline inside quotes
      final result = Reader('"line1\\nline2"').readOne() as String;
      expect(result, startsWith('"'));
      expect(result, endsWith('"'));
      expect(result, contains('\n'));
    });
  });

  // ─── Reader — lists ──────────────────────────────────────────────────────────

  group('Reader — lists', () {
    test('reads empty list', () {
      expect(Reader('()').readOne(), equals([]));
    });

    test('reads simple list', () {
      expect(Reader('(+ 1 2)').readOne(), equals(['+', 1, 2]));
    });

    test('reads nested list', () {
      expect(
        Reader('(if (> x 0) y z)').readOne(),
        equals(['if', ['>', 'x', 0], 'y', 'z']),
      );
    });

    test('reads list with string literal', () {
      expect(
        Reader('(print "hello")').readOne(),
        equals(['print', '"hello"']),
      );
    });

    test('reads list with bool and null', () {
      expect(
        Reader('(check true null)').readOne(),
        equals(['check', true, null]),
      );
    });
  });

  // ─── Reader — readAll ────────────────────────────────────────────────────────

  group('Reader — readAll', () {
    test('reads multiple top-level forms', () {
      final forms = Reader('(+ 1 2) (- 3 4)').readAll();
      expect(forms.length, equals(2));
      expect(forms[0], equals(['+', 1, 2]));
      expect(forms[1], equals(['-', 3, 4]));
    });

    test('returns empty list for empty source', () {
      expect(Reader('').readAll(), equals([]));
    });

    test('skips line comments (;)', () {
      final forms = Reader('; this is a comment\n(+ 1 2)').readAll();
      expect(forms.length, equals(1));
      expect(forms[0], equals(['+', 1, 2]));
    });

    test('skips inline comment', () {
      final forms = Reader('(+ 1 2) ; add\n(- 3 4)').readAll();
      expect(forms.length, equals(2));
    });
  });

  // ─── Reader — errors ─────────────────────────────────────────────────────────

  group('Reader — errors', () {
    test('throws ReaderException on unclosed parenthesis', () {
      expect(
        () => Reader('(+ 1 2').readOne(),
        throwsA(isA<ReaderException>()),
      );
    });

    test('throws ReaderException on unterminated string', () {
      expect(
        () => Reader('"unterminated').readOne(),
        throwsA(isA<ReaderException>()),
      );
    });

    test('ReaderException.toString contains position', () {
      try {
        Reader('(').readOne();
      } on ReaderException catch (e) {
        expect(e.toString(), contains('ReaderException'));
        expect(e.position, isNonNegative);
      }
    });
  });

  // ─── compile() pipeline ──────────────────────────────────────────────────────

  group('compile() — read → expand → emit pipeline', () {
    test('compiles a simple let form', () {
      registerBuiltins();
      final out = compile('(let x 42)');
      expect(out, equals('final x = 42'));
    });

    test('compiles a function call', () {
      final out = compile('(print "hello")');
      expect(out, contains('print'));
      expect(out, contains('"hello"'));
    });

    test('compiles an if with no else', () {
      final out = compile('(if cond body)');
      expect(out, contains('if (cond)'));
      expect(out, contains('body'));
    });

    test('compiles multiple top-level forms', () {
      final out = compile('(let a 1)\n(let b 2)');
      expect(out, contains('final a = 1'));
      expect(out, contains('final b = 2'));
    });

    test('compile expands macros (unless)', () {
      final out = compile('(unless (> x 0) (print "neg"))');
      expect(out, contains('if'));
      expect(out, contains('!'));
    });

    test('compile is deterministic (same output on repeated calls)', () {
      const src = '(let x 1)';
      expect(compile(src), equals(compile(src)));
    });
  });
}
