// example/input/payment.dart
// Run: dart run bin/dart_macros.dart build example/input/
// Then look at this file — copyWith, ==, hashCode, toString are injected.

@DataClass()
class Payment {
  final double amount;
  final String currency;
  final String? reference;

  const Payment({
    required this.amount,
    required this.currency,
    this.reference,
  });
}

@DataClass()
@Logged()
class ApiResponse<T> {
  final int statusCode;
  final String message;
  final bool success;

  const ApiResponse({
    required this.statusCode,
    required this.message,
    required this.success,
  });
}

@Singleton()
class AppConfig {
  final String baseUrl = 'https://api.example.com';
  final int timeout = 30;
}
