/// Built-in macro definitions.
///
/// These demonstrate what Lisp-style macros enable that is IMPOSSIBLE
/// in Dart without this system — even with macro_kit or build_runner.
///
/// Each macro is shown first with the raw-list API, then with the equivalent
/// typed node API. Both produce identical output:
///
///   RAW LIST:   defmacro('unless', (args) => ['if', ['!', args[0]], args[1]]);
///   TYPED API:  defmacro('unless', (args) => $if($not(args[0]), args[1]));
library;

import 'core.dart';
import 'gensym.dart';
import 'nodes.dart';
import 'splice.dart';

/// Registers all built-in macros.
void registerBuiltins() {
  _registerControlFlow();
  _registerBinding();
  _registerDataClass();
}

// ─── Control flow ─────────────────────────────────────────────────────────────

void _registerControlFlow() {
  // (unless condition body)
  // A function can't do this — it would evaluate both args before calling.
  // Raw:   defmacro('unless', (args) => ['if', ['!', args[0]], args[1]]);
  defmacro('unless', (args) => $if($not(args[0]), args[1]));

  // (when condition body)
  // Raw:   defmacro('when', (args) => ['if', args[0], args[1]]);
  defmacro('when', (args) => $if(args[0], args[1]));

  // (with-retry n body)
  // Generates a stateful retry loop. The variable _attempt is injected
  // into the caller's scope — impossible with a higher-order function.
  // Registered under both the kebab-case (.sexp) and camelCase (.dmacro) names.
  Node withRetry(List<Node> args) {
    final n = args[0];
    final body = args[1];
    final attempt = gensym('attempt');
    final err = gensym('err');
    return $forIn(
      attempt,
      'Iterable.generate(${emit(n)})',
      $try(
        body,
        err,
        $if(
          $eq(attempt, $sub(n, 1)),
          $throw(err),
          $call('print', [$str('Retrying...')]),
        ),
      ),
    );
  }

  defmacro('with-retry', withRetry);
  defmacro('withRetry', withRetry);

  // (assert-that expr)
  // Generates an error message that CONTAINS THE SOURCE OF THE EXPRESSION.
  // A function receives a value — it can never know what expression produced it.
  // Registered under both the kebab-case (.sexp) and camelCase (.dmacro) names.
  Node assertThat(List<Node> args) => $if(
        $not(args[0]),
        $throw('AssertionError("Expected: ${emit(args[0])}, got false")'),
      );
  defmacro('assert-that', assertThat);
  defmacro('assertThat', assertThat);
}

// ─── Binding ──────────────────────────────────────────────────────────────────

void _registerBinding() {
  // (swap! a b)
  // Injects a temp variable directly into the caller's scope.
  // A function receives values — it cannot write back to the caller's variables.
  // Uses $splice so the three statements are inlined into any parent context
  // (if body, while body, another macro, etc.) — not just defn bodies.
  defmacro('swap!', (args) {
    final tmp = gensym('swap');
    return $splice([
      $let(tmp, args[0]),
      $set(args[0] as String, args[1]),
      $set(args[1] as String, tmp),
    ]);
  });

  // (and-let [name expr] [name expr] ... body)
  // Cascading bindings where each can see the previous.
  defmacro('and-let', (args) {
    final bindings = args.sublist(0, args.length - 1);
    final body = args.last;
    Node result = body;
    for (final b in bindings.reversed) {
      final name = (b as List)[0] as String;
      final expr = b[1];
      result = $do([$let(name, expr), result]);
    }
    return result;
  });

  // (once name expr)
  // Evaluates expr exactly once and binds it — avoids double-evaluation.
  defmacro('once', (args) {
    final name = args[0] as String;
    final expr = args[1];
    final tmp = '_once_$name';
    return $do([
      $let(tmp, expr),
      $set(name, tmp),
    ]);
  });
}

// ─── Data class generation ────────────────────────────────────────────────────

void _registerDataClass() {
  // (defrecord Name [Type field] [Type field] ...)
  //
  // Generates a COMPLETE immutable data class from a compact spec.
  // This is fundamentally different from macro_kit which can only APPEND
  // to an existing class. This CREATES the class itself.
  //
  // One line of macro code replaces ~40 lines of Dart boilerplate.
  defmacro('defrecord', (args) {
    final name = args[0] as String;
    final fields = args
        .sublist(1)
        .map((f) => Field((f as List)[0] as String, f[1] as String))
        .toList();

    return $class(name, [
      ...fields.map((f) => $field(f.type, f.name)),
      $ctor(name, fields.map((f) => [f.type, f.name]).toList()),
      $copyWith(name, fields),
      $equality(name, fields),
      $hashCode(fields),
      $toString(name, fields),
      $fromJson(name, fields),
      $toJson(fields),
    ]);
  });

  // (defunion Name [Variant1 [Type field]...] [Variant2 ...])
  // Generates a sealed class hierarchy — like Freezed's union types.
  defmacro('defunion', (args) {
    final name = args[0] as String;
    final variants = args.sublist(1);

    final variantClasses = variants.map((v) {
      final variantName = (v as List)[0] as String;
      final variantFields = v
          .sublist(1)
          .map((f) => Field((f as List)[0] as String, f[1] as String))
          .toList();
      return $class('$variantName extends $name', [
        ...variantFields.map((f) => $field(f.type, f.name)),
        $ctor(variantName, variantFields.map((f) => [f.type, f.name]).toList()),
      ]);
    }).toList();

    // The parent carries a const constructor so the variant subclasses (which
    // use `const`) can call a const super constructor.
    return $do(
        ['sealed class $name {\n  const $name();\n}', ...variantClasses]);
  });
}
