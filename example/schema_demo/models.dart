class Payment {
  final double amount;
  final String currency;
  final String? reference;
  final List<String>? tags;
  const Payment({required this.amount, required this.currency, this.reference, this.tags});
  Payment copyWith({double? amount, String? currency, String? reference, List<String>? tags}) => Payment(amount: amount ?? this.amount, currency: currency ?? this.currency, reference: reference ?? this.reference, tags: tags ?? this.tags);
  @override
  bool operator ==(Object other) => identical(this, other) || other is Payment && other.amount == amount && other.currency == currency && other.reference == reference && other.tags == tags;
  @override
  int get hashCode => Object.hash(amount, currency, reference, tags);
  @override
  String toString() => 'Payment(amount: $amount, currency: $currency, reference: $reference, tags: $tags)';
}