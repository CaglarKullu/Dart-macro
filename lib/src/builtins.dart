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
  _registerUserMacros();
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
        $do([body, 'break']), // break on success so body runs exactly once
        err,
        $if(
          $eq(attempt, $sub(n, 1)),
          'rethrow',
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
  Node assertThat(List<Node> args) {
    // Escape \ and " so the emitted expression is safe inside a double-quoted string.
    final exprStr =
        emit(args[0]).replaceAll(r'\', r'\\').replaceAll('"', r'\"');
    return $if(
      $not(args[0]),
      $throw('AssertionError("Expected: $exprStr, got false")'),
    );
  }

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
    final tmp = gensym('once');
    return $do([
      $let(tmp, expr),
      $set(name, tmp),
    ]);
  });
}

// ─── Data class generation ────────────────────────────────────────────────────

void _registerDataClass() {
  // (defenum Name value1 value2 ...)
  //
  // Registers Name as a known enum type so subsequent defrecord declarations
  // in the same file can emit enum-aware fromJson/toJson for fields typed Name.
  // defenum must precede any defrecord that references it.
  //
  // Returns a raw Dart string atom (not a node) to prevent expand() from
  // re-invoking this macro on the returned value.
  defmacro('defenum', (args) {
    final name = args[0] as String;
    // Two call forms:
    //   flat:     ['defenum', 'Status', 'active', 'inactive']  (parser/reader)
    //   wrapped:  ['defenum', 'Status', ['active', 'inactive']] ($defEnum/schema macros)
    final List<dynamic> rawValues;
    if (args.length == 2 && args[1] is List) {
      rawValues = args[1] as List;
    } else {
      rawValues = args.sublist(1);
    }
    final values = rawValues.map((v) => v.toString()).toList();
    registerEnum(name);
    return genEnumSource(name, values);
  });

  // (defrecord Name [Type field] [Type field] ...)
  //
  // Generates a COMPLETE immutable data class from a compact spec.
  // This is fundamentally different from macro_kit which can only APPEND
  // to an existing class. This CREATES the class itself.
  //
  // One line of macro code replaces ~40 lines of Dart boilerplate.
  defmacro('defrecord', (args) {
    final name = args[0] as String;
    final fields = args.sublist(1).map((f) {
      final fList = f as List;
      var type = fList[0] as String;
      final fname = fList[1] as String;
      // Optional source line number — present when parsed from .dmacro source.
      final fieldLine = fList.length > 2 ? fList[2] as int? : null;
      // Optional explicit JSON key from @json_key("name") annotation.
      final jsonKey = fList.length > 3 ? fList[3] as String? : null;
      // If the field type is a defenum-registered name, add the enum: signal
      // so the emitter generates values.byName / .name serialization.
      final nullable = type.endsWith('?');
      final base = nullable ? type.substring(0, type.length - 1) : type;
      if (isRegisteredEnum(base)) {
        type = nullable ? 'enum:$base?' : 'enum:$base';
      }
      return Field(type, fname, line: fieldLine, jsonKey: jsonKey);
    }).toList();

    // Per-field origin markers require both a WithOrigins compile AND the
    // --field-origins flag. Off by default to keep generated files clean.
    final trackOrigins =
        getEmitterSourcePath() != null && getEmitterFieldOrigins();

    return $class(name, [
      ...fields.expand((f) => [
            if (trackOrigins && f.line != null) $origin(f.line!),
            $field(f.type, f.name),
          ]),
      $ctor(name, fields.map((f) => [f.type, f.name]).toList()),
      $copyWith(name, fields),
      $equality(name, fields),
      $hashCode(fields),
      $toString(name, fields),
      $fromJson(name, fields),
      $toJson(fields),
    ]);
  });

  // (defrecord_snake Name [Type field] ...) — identical to defrecord but
  // JSON keys are snake_case (orderId → "order_id"). Use when the API uses
  // snake_case and the Dart code uses camelCase.
  // Invoked via: defrecord(snake_case) Name { ... } in .dmacro source.
  defmacro('defrecord_snake', (args) {
    final name = args[0] as String;
    final fields = args.sublist(1).map((f) {
      final fList = f as List;
      var type = fList[0] as String;
      final fname = fList[1] as String;
      final fieldLine = fList.length > 2 ? fList[2] as int? : null;
      final jsonKey = fList.length > 3 ? fList[3] as String? : null;
      final nullable = type.endsWith('?');
      final base = nullable ? type.substring(0, type.length - 1) : type;
      if (isRegisteredEnum(base)) {
        type = nullable ? 'enum:$base?' : 'enum:$base';
      }
      return Field(type, fname, line: fieldLine, jsonKey: jsonKey);
    }).toList();

    final trackOrigins =
        getEmitterSourcePath() != null && getEmitterFieldOrigins();

    return $class(name, [
      ...fields.expand((f) => [
            if (trackOrigins && f.line != null) $origin(f.line!),
            $field(f.type, f.name),
          ]),
      $ctor(name, fields.map((f) => [f.type, f.name]).toList()),
      $copyWith(name, fields),
      $equality(name, fields),
      $hashCode(fields),
      $toString(name, fields),
      $fromJson(name, fields, snakeCase: true),
      $toJson(fields, snakeCase: true),
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
        $copyWith(variantName, variantFields),
        $equality(variantName, variantFields),
        $hashCode(variantFields),
        $toString(variantName, variantFields),
      ]);
    }).toList();

    // The parent carries a const constructor so the variant subclasses (which
    // use `const`) can call a const super constructor.
    return $do(
        ['sealed class $name {\n  const $name();\n}', ...variantClasses]);
  });
}

// ─── User-definable macros ────────────────────────────────────────────────────

void _registerUserMacros() {
  defmacro('defmacro', (args) {
    final name = args[0] as String;
    if (args.length < 3) {
      throw ArgumentError('defmacro $name: expected (name params body)');
    }
    final params = (args[1] as List).cast<String>();
    final body = args.length == 3 ? args[2] : ['do', ...args.sublist(2)];
    defmacro(name, (callArgs) {
      if (callArgs.length != params.length) {
        throw ArgumentError(
          '$name: expected ${params.length} arg(s), got ${callArgs.length}',
        );
      }
      final bindings = Map.fromIterables(params, callArgs);
      return _substitute(body, bindings);
    });
    return '';
  });
}

/// Public entry point for substituting [bindings] into [template].
/// Used by [defmacro_typed] in schema_macros.dart.
Node substituteBindings(Node template, Map<String, Node> bindings) =>
    _substitute(template, bindings);

Node _substitute(Node template, Map<String, Node> bindings) {
  if (template is String && bindings.containsKey(template)) {
    return bindings[template]!;
  }
  if (template is! List) return template;
  return template.map((n) => _substitute(n, bindings)).toList();
}
