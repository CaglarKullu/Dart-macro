// inline_demo.dart
//
// Demonstrates embedding dmacro blocks directly in a regular .dart file.
// No separate .dmacro file needed.
//
// Run:
//   dart run bin/dmacro.dart compile example/inline_demo.dart
//
// The macro source is preserved as comments so the file stays
// analyzer-clean and re-runs are idempotent.

// @@dmacro
// defrecord Point { double x; double y; }
// @@generated
class Point {
  final double x;
  final double y;
  const Point({required this.x, required this.y});
  Point copyWith({double? x, double? y}) =>
      Point(x: x ?? this.x, y: y ?? this.y);
  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Point && other.x == x && other.y == y;
  @override
  int get hashCode => Object.hashAll([x, y]);
  @override
  String toString() => 'Point(x: $x, y: $y)';
  factory Point.fromJson(Map<String, dynamic> json) =>
      Point(x: (json['x'] as num).toDouble(), y: (json['y'] as num).toDouble());
  Map<String, dynamic> toJson() => {'x': x, 'y': y};
}
// @@end

// @@dmacro
// defrecord Color { int r; int g; int b; }
// @@generated
class Color {
  final int r;
  final int g;
  final int b;
  const Color({required this.r, required this.g, required this.b});
  Color copyWith({int? r, int? g, int? b}) =>
      Color(r: r ?? this.r, g: g ?? this.g, b: b ?? this.b);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Color && other.r == r && other.g == g && other.b == b;
  @override
  int get hashCode => Object.hashAll([r, g, b]);
  @override
  String toString() => 'Color(r: $r, g: $g, b: $b)';
  factory Color.fromJson(Map<String, dynamic> json) =>
      Color(r: json['r'] as int, g: json['g'] as int, b: json['b'] as int);
  Map<String, dynamic> toJson() => {'r': r, 'g': g, 'b': b};
}
// @@end

// Regular Dart below — uses the generated types directly.

void main() {
  const origin = Point(x: 0, y: 0);
  final moved = origin.copyWith(x: 3, y: 4);
  print(moved); // Point(x: 3.0, y: 4.0)

  const red = Color(r: 255, g: 0, b: 0);
  print(red.toJson()); // {r: 255, g: 0, b: 0}
}
