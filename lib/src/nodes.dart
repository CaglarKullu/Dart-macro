/// Typed node constructors — a Dart-friendly API over the raw list engine.
///
/// These are pure Dart functions that construct [Node] values.
/// The $ prefix is a convention meaning "returns an AST node".
///
/// Compare:
///   Raw list:  ['if', ['!', condition], body]
///   Typed API: $if($not(condition), body)
///
/// Both produce identical output. The typed API is just Dart.
library;

import 'core.dart';

// ─── Arithmetic ───────────────────────────────────────────────────────────────

Node $add(Node a, Node b)  => ['+', a, b];
Node $sub(Node a, Node b)  => ['-', a, b];
Node $mul(Node a, Node b)  => ['*', a, b];
Node $div(Node a, Node b)  => ['/', a, b];

// ─── Comparison ───────────────────────────────────────────────────────────────

Node $eq(Node a, Node b)   => ['==', a, b];
Node $neq(Node a, Node b)  => ['!=', a, b];
Node $lt(Node a, Node b)   => ['<', a, b];
Node $gt(Node a, Node b)   => ['>', a, b];
Node $lte(Node a, Node b)  => ['<=', a, b];
Node $gte(Node a, Node b)  => ['>=', a, b];

// ─── Logic ────────────────────────────────────────────────────────────────────

Node $and(Node a, Node b)  => ['&&', a, b];
Node $or(Node a, Node b)   => ['||', a, b];
Node $not(Node expr)       => ['!', expr];

// ─── Bindings ─────────────────────────────────────────────────────────────────

Node $let(String name, Node value)  => ['let', name, value];
Node $var(String name, Node value)  => ['var', name, value];
Node $set(String name, Node value)  => ['set!', name, value];

// ─── Control flow ─────────────────────────────────────────────────────────────

Node $if(Node cond, Node then, [Node? else_]) =>
    else_ != null ? ['if', cond, then, else_] : ['if', cond, then];

Node $while(Node cond, Node body) => ['while', cond, body];

Node $forIn(String variable, Node iterable, Node body) =>
    ['for-in', variable, iterable, body];

Node $return(Node value)          => ['return', value];
Node $throw(Node value)           => ['throw', value];
Node $try(Node body, String catchVar, Node catchBody) =>
    ['try', body, catchVar, catchBody];

/// Sequence of statements — spliced into parent function body automatically.
Node $do(List<Node> stmts)        => ['do', ...stmts];

// ─── Calls ────────────────────────────────────────────────────────────────────

/// Regular function/macro call: `name(arg1, arg2)`
Node $call(String name, List<Node> args) => [name, ...args];

/// Method call: `receiver.method(arg1, arg2)`
Node $method(Node receiver, String method, [List<Node> args = const []]) =>
    ['.$method', receiver, ...args];

/// Property access: `receiver.prop`
Node $prop(Node receiver, String prop) => ['.-$prop', receiver];

// ─── Declarations ─────────────────────────────────────────────────────────────

/// Function definition: `returnType name(params) { body }`
Node $defn({
  required String returns,
  required String name,
  required List<Param> params,
  required List<Node> body,
}) => ['defn', returns, name, params.map((p) => [p.type, p.name]).toList(), ...body];

// ─── Class building ───────────────────────────────────────────────────────────

Node $field(String type, String name)     => ['field', type, name];
Node $ctor(String name, List<String> paramNames) => ['ctor', name, paramNames];
Node $class(String name, List<Node> members) => ['defclass', name, ...members];

Node $copyWith(String name, List<Field> fields) =>
    ['copywith', name, fields.map((f) => [f.type, f.name]).toList()];

Node $equality(String name, List<Field> fields) =>
    ['equalop', name, fields.map((f) => [f.type, f.name]).toList()];

Node $hashCode(List<Field> fields) =>
    ['hashop', null, fields.map((f) => [f.type, f.name]).toList()];

Node $toString(String name, List<Field> fields) =>
    ['tostringop', name, fields.map((f) => [f.type, f.name]).toList()];

// ─── Value helpers ────────────────────────────────────────────────────────────

/// A string literal node — emitted with surrounding quotes.
String $str(String value) => '"$value"';

/// An identifier node — emitted as-is.
String $id(String name)   => name;

// ─── Helper types ─────────────────────────────────────────────────────────────

/// A function/constructor parameter.
class Param {
  final String type;
  final String name;
  const Param(this.type, this.name);
}

/// A class field specification.
class Field {
  final String type;
  final String name;
  const Field(this.type, this.name);
}
