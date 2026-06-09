# E-commerce domain model

A realistic set of data types for an e-commerce app — products, cart items, orders, shipping addresses, and an order status state machine.

## What's in `models.dmacro`

| Declaration | Generated | Lines saved |
|---|---|---|
| `defrecord Product` | Immutable product class with 7 fields, constructor, copyWith, ==, hashCode, toString | ~55 lines |
| `defrecord CartItem` | Cart item with quantity and pricing snapshot | ~40 lines |
| `defrecord ShippingAddress` | Address with optional fields | ~45 lines |
| `defrecord Order` | Full order with nested types (`List<CartItem>`, `ShippingAddress`) | ~55 lines |
| `defunion OrderStatus` | Sealed class with 6 variants (Pending/Processing/Shipped/Delivered/Cancelled/Refunded) | ~70 lines |
| `validateCartItem` | Validation function using `unless` + `assertThat` | ~15 lines |
| `validateOrder` | Order-level validation | ~10 lines |

**~290 lines of idiomatic Dart generated from ~60 lines of macro source.**

## Compile

```bash
dart run bin/dmacro.dart compile example/ecommerce/models.dmacro
# writes example/ecommerce/models.dart
```

## Usage in your Flutter app

```dart
import 'ecommerce/models.dart';

final product = Product(
  id: 'p1',
  name: 'Running Shoes',
  description: 'Lightweight trail runners',
  price: 89.99,
  stock: 42,
  category: 'footwear',
  // imageUrl is nullable — no argument needed
);

final updated = product.copyWith(stock: product.stock - 1);

// Pattern match on order state
switch (order.status) {
  case Shipped(:final trackingId, :final carrier):
    print('Shipped via $carrier — track: $trackingId');
  case Cancelled(:final reason):
    print('Cancelled: $reason');
  default: ...
}
```
