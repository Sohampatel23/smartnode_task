import 'package:flutter/foundation.dart';

/// A single inventory row. Quantity is the current, converged value derived
/// from applying commutative deltas (see [InventoryOperation]) - it is never
/// blindly overwritten by an incoming absolute value.
@immutable
class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.name,
    required this.quantity,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final int quantity;
  final DateTime updatedAt;

  InventoryItem copyWith({int? quantity, DateTime? updatedAt}) {
    return InventoryItem(
      id: id,
      name: name,
      quantity: quantity ?? this.quantity,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'quantity': quantity,
        'updatedAt': updatedAt.toIso8601String(),
      };

  factory InventoryItem.fromMap(Map<dynamic, dynamic> map) {
    return InventoryItem(
      id: map['id'] as String,
      name: map['name'] as String,
      quantity: map['quantity'] as int,
      updatedAt: DateTime.parse(map['updatedAt'] as String),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is InventoryItem &&
      other.id == id &&
      other.name == name &&
      other.quantity == quantity &&
      other.updatedAt == updatedAt;

  @override
  int get hashCode => Object.hash(id, name, quantity, updatedAt);

  @override
  String toString() => 'InventoryItem($id, $name, qty=$quantity)';
}
