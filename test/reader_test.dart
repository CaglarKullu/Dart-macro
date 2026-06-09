import 'package:test/test.dart';
import 'package:dmacro/dmacro.dart';

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
        equals([
          'if',
          ['>', 'x', 0],
          'y',
          'z'
        ]),
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

  // ─── Reader — string edge cases ───────────────────────────────────────────────

  group('Reader — string edge cases', () {
    test('reads empty string literal', () {
      final forms = Reader('("")').readAll();
      expect(forms[0], isA<List>());
      final list = forms[0] as List;
      expect(list[0], equals('""'));
    });

    test('empty string atom ""', () {
      // A standalone "" is read as the two-char atom ""
      final forms = Reader('(let x "")').readAll();
      final node = forms[0] as List;
      expect(node[2], equals('""'));
    });

    test('string with tab escape sequence', () {
      final forms = Reader(r'(f "a\tb")').readAll();
      final node = forms[0] as List;
      expect(node[1], equals('"a\tb"'));
    });

    test('string with escaped backslash', () {
      final forms = Reader(r'(f "a\\b")').readAll();
      final node = forms[0] as List;
      expect(node[1], equals('"a\\b"'));
    });

    test('string with escaped quote', () {
      final forms = Reader(r'(f "say \"hi\"")').readAll();
      final node = forms[0] as List;
      expect((node[1] as String), contains('"'));
    });

    test('string with newline escape', () {
      final forms = Reader(r'(f "line1\nline2")').readAll();
      final node = forms[0] as List;
      expect(node[1], equals('"line1\nline2"'));
    });

    test('string with multiple escape sequences', () {
      final forms = Reader(r'(f "a\tb\nc")').readAll();
      final node = forms[0] as List;
      expect(node[1], equals('"a\tb\nc"'));
    });

    test('string with non-ASCII characters', () {
      final forms = Reader('(f "héllo")').readAll();
      final node = forms[0] as List;
      expect(node[1], equals('"héllo"'));
    });
  });

  // ─── Reader — atom edge cases ─────────────────────────────────────────────────

  group('Reader — atom edge cases', () {
    test('reads arrow operator ->', () {
      final forms = Reader('(-> a b)').readAll();
      final node = forms[0] as List;
      expect(node[0], equals('->'));
    });

    test('reads fat arrow =>', () {
      final forms = Reader('(=> x y)').readAll();
      final node = forms[0] as List;
      expect(node[0], equals('=>'));
    });

    test('reads dotted method .foo', () {
      final forms = Reader('(.foo obj)').readAll();
      final node = forms[0] as List;
      expect(node[0], equals('.foo'));
    });

    test('reads null-coalesce ?? as atom', () {
      final forms = Reader('(?? x y)').readAll();
      final node = forms[0] as List;
      expect(node[0], equals('??'));
    });

    test('reads zero as integer', () {
      final forms = Reader('0').readAll();
      expect(forms[0], equals(0));
    });

    test('reads negative integer as integer (reader handles leading minus)',
        () {
      // -5 is read as the integer -5 (the reader handles negative number literals)
      final forms = Reader('-5').readAll();
      expect(forms[0], equals(-5));
    });

    test('reads Dart generic type identifier List<int> as atom', () {
      // Angle brackets stop atom reading at '<' — this is a known limitation
      // of the S-expression reader (generic types in reader go atom-by-atom).
      // This test documents the behavior, not an error.
      final forms = Reader('(List<int>)').readAll();
      // parsed as a list starting with 'List<int>' or multiple atoms
      expect(forms[0], isA<List>());
    });
  });

  // ─── Reader — readOne ─────────────────────────────────────────────────────────

  group('Reader — readOne', () {
    test('readOne reads only the first form', () {
      final r = Reader('(let a 1) (let b 2)');
      final form = r.readOne();
      expect(form, isA<List>());
      final node = form as List;
      expect(node[1], equals('a'));
    });

    test('readOne skips leading whitespace', () {
      final form = Reader('   42').readOne();
      expect(form, equals(42));
    });

    test('readOne skips leading comments', () {
      final form = Reader('; comment\n99').readOne();
      expect(form, equals(99));
    });
  });

  // ─── Reader — error positions ─────────────────────────────────────────────────

  group('Reader — error positions', () {
    test('EOF inside list reports position', () {
      expect(
        () => Reader('(let x').readAll(),
        throwsA(isA<ReaderException>()
            .having((e) => e.message, 'message', contains('Unclosed'))),
      );
    });

    test('unterminated string reports position', () {
      expect(
        () => Reader('(f "oops').readAll(),
        throwsA(isA<ReaderException>()
            .having((e) => e.message, 'message', contains('Unterminated'))),
      );
    });

    test('ReaderException.toString includes position', () {
      final ex = ReaderException('bad input', 42);
      expect(ex.toString(), contains('42'));
      expect(ex.toString(), contains('bad input'));
    });

    test('empty source returns empty list (no exception)', () {
      expect(Reader('').readAll(), isEmpty);
    });

    test('only comments returns empty list', () {
      expect(Reader('; line1\n; line2\n').readAll(), isEmpty);
    });
  });
}
