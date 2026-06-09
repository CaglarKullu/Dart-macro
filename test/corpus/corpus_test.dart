/// Phase 3 conformance corpus — real-world Dart snippets.
///
/// Each snippet either compiles to analyzer-clean Dart (assertions made here)
/// or fails with a located ParseException (not a silent mis-parse).
library;

import 'package:test/test.dart';
import 'package:dmacro/dmacro.dart';

void main() {
  setUpAll(registerBuiltins);

  // ─── 3.1 Named arguments ─────────────────────────────────────────────────────

  group('3.1 named arguments', () {
    test('named args in constructor call', () {
      const src = '''
        void setup() {
          Payment(amount: 100.0, currency: "USD");
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('amount: 100.0'));
      expect(out, contains('currency: "USD"'));
    });

    test('mixed positional + named args', () {
      const src = '''
        void foo() {
          log("msg", level: 2, tag: "x");
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('level: 2'));
      expect(out, contains('tag: "x"'));
    });

    test('named args in method call', () {
      const src = '''
        void bar() {
          obj.copyWith(amount: 50.0);
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('amount: 50.0'));
    });
  });

  // ─── 3.3 async / await / => ──────────────────────────────────────────────────

  group('3.3 async / await / arrow', () {
    test('async function with await', () {
      const src = '''
        Future<String> fetchUser(String id) async {
          final resp = await getResponse(id);
          return resp;
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('async'));
      expect(out, contains('await getResponse(id)'));
      expect(out, contains('Future<String>'));
    });

    test('arrow body function', () {
      const src = 'int double(int x) => x * 2;';
      final out = compileDartLike(src);
      expect(out, contains('=>'));
      expect(out, contains('x * 2'));
    });

    test('async arrow body', () {
      const src = 'Future<int> getCount() async => count;';
      final out = compileDartLike(src);
      expect(out, contains('async'));
      expect(out, contains('=>'));
    });

    test('await in expression', () {
      const src = '''
        Future<void> run() async {
          final result = await compute(42);
          return result;
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('await compute(42)'));
    });
  });

  // ─── 3.2 Cascades ────────────────────────────────────────────────────────────

  group('3.2 cascades', () {
    test('cascade method chain', () {
      const src = '''
        void fill(StringBuffer buf) {
          buf..write("a")..write("b");
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('..write("a")'));
      expect(out, contains('..write("b")'));
    });
  });

  // ─── 3.4 Misc expression coverage ────────────────────────────────────────────

  group('3.4 ternary operator', () {
    test('ternary returns correct Dart', () {
      const src = '''
        String label(bool b) {
          return b ? "yes" : "no";
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('?'));
      expect(out, contains('"yes"'));
      expect(out, contains('"no"'));
    });
  });

  group('3.4 null-aware operators', () {
    test('?? null-coalesce', () {
      const src = '''
        String getName(String? x) {
          return x ?? "default";
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('??'));
      expect(out, contains('"default"'));
    });

    test('?. null-aware method call', () {
      const src = '''
        void process(List? items) {
          items?.length;
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('?.'));
    });
  });

  group('3.4 list literals', () {
    test('list literal emits correctly', () {
      const src = '''
        List<int> nums() {
          return [1, 2, 3];
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('[1, 2, 3]'));
    });

    test('empty list literal', () {
      const src = '''
        List<String> empty() {
          return [];
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('[]'));
    });

    test('spread operator in list literal', () {
      const src = '''
        List<int> combined(List<int> a, List<int> b) {
          return [...a, ...b];
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('[...a, ...b]'));
    });
  });

  // ─── 3.5 Real-world snippets ─────────────────────────────────────────────────

  group('3.5 corpus snippets', () {
    test('snippet 1: guard function with unless', () {
      const src = '''
        bool validateAmount(double amount) {
          unless (amount > 0) {
            throw Exception("bad amount");
          }
          return true;
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('if'));
      expect(out, contains('!'));
      expect(out, contains('return true'));
    });

    test('snippet 2: swap two variables', () {
      const src = '''
        void normalise(double a, double b) {
          when (a > b) {
            swap!(a, b);
          }
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('if'));
      expect(out, contains('dmSwap_'));
    });

    test('snippet 3: defrecord with full class', () {
      const src = '''
        defrecord Point {
          double x;
          double y;
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('class Point'));
      expect(out, contains('final double x;'));
      expect(out, contains('copyWith'));
    });

    test('snippet 4: function with multiple returns', () {
      const src = '''
        int sign(int x) {
          if (x > 0) {
            return 1;
          }
          if (x < 0) {
            return -1;
          }
          return 0;
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('return 1'));
      expect(out, contains('return -1'));
      expect(out, contains('return 0'));
    });

    test('snippet 5: async data fetch pattern', () {
      const src = '''
        Future<String> fetchData(String url) async {
          final result = await fetch(url);
          return result;
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('async'));
      expect(out, contains('await fetch(url)'));
    });

    test('snippet 6: null-safe accessor chain', () {
      const src = '''
        int getLength(List? items) {
          return items?.length ?? 0;
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('?.'));
      expect(out, contains('??'));
    });

    test('snippet 7: boolean short-circuit', () {
      const src = '''
        bool isValidPayment(double amount, String currency) {
          return amount > 0 && currency != "";
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('&&'));
      expect(out, contains('>'));
      expect(out, contains('!='));
    });

    test('snippet 8: ternary in assignment', () {
      const src = '''
        void setLabel(bool active) {
          final label = active ? "on" : "off";
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('"on"'));
      expect(out, contains('"off"'));
    });

    test('snippet 9: list of items', () {
      const src = '''
        List<String> currencies() {
          return ["USD", "EUR", "GBP"];
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('"USD"'));
      expect(out, contains('"EUR"'));
    });

    test('snippet 10: method call chain', () {
      const src = '''
        String process(String s) {
          return s.toLowerCase();
        }
      ''';
      final out = compileDartLike(src);
      expect(out, contains('.toLowerCase()'));
    });
  });

  // ─── Errors clear and located ─────────────────────────────────────────────────

  group('3.5 parse errors are clear', () {
    test('unexpected token throws ParseException', () {
      expect(
        () => compileDartLike('123'),
        throwsA(isA<ParseException>()),
      );
    });

    test('missing closing brace throws ParseException', () {
      expect(
        () => compileDartLike('void f() { return 1;'),
        throwsA(isA<ParseException>()),
      );
    });

    test('unknown construct gives ParseException, not silent mis-parse', () {
      // A standalone number at top level is not a valid declaration.
      expect(
        () => compileDartLike('42;'),
        throwsA(isA<ParseException>()),
      );
    });
  });
}
