// annotation_style.dart
//
// FROZEN ILLUSTRATION — this is the annotation / build_runner shape that this
// project evaluated and rejected. There is no annotation tool in this repo; the
// "generated" block below is hand-frozen to show what in-place injection looks
// like. See doc/ANNOTATIONS_VS_PREPROCESSOR.md for the full comparison.
//
// Contrast with preprocessor_style.dmacro, which expresses the same model and is
// regenerated as a whole .dart file by `dmacro compile`.
library;

// Marker annotations. A real annotation system would ship these; this repo's
// prototype shipped none, which is why annotated files failed `dart analyze`.
class DataClass {
  const DataClass();
}

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

  // ━━━ generated (frozen) ━━━
  //
  // An annotation transformer can only APPEND members to a class you already
  // wrote — note there is no fromJson/toJson, no deep equality, and no way to
  // create this type from an external schema. Those need the preprocessor.

  Payment copyWith({
    double? amount,
    String? currency,
    String? reference,
  }) {
    return Payment(
      amount: amount ?? this.amount,
      currency: currency ?? this.currency,
      reference: reference ?? this.reference,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Payment &&
        other.amount == amount &&
        other.currency == currency &&
        other.reference == reference;
  }

  @override
  int get hashCode => Object.hash(amount, currency, reference);

  @override
  String toString() =>
      'Payment(amount: $amount, currency: $currency, reference: $reference)';
  // ━━━ end generated ━━━
}
