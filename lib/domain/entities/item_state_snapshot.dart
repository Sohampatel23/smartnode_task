import 'package:flutter/foundation.dart';

import 'inventory_item.dart';

/// A retained "current value" message for one item, tagged with the id of
/// the [InventoryOperation] that produced it.
///
/// The [lastOperationId] tag is what makes this safe to combine with the
/// live operations stream: a retained publish is *also* delivered live to
/// every already-subscribed client (retain only changes what a *future*
/// subscriber gets), so a connected device receives both the delta
/// operation and an echo of the resulting state for the same change. Without
/// a shared identifier, that echo would look like new information and get
/// applied on top of the delta already applied, double-counting the change.
/// Tagging it with the same [lastOperationId] lets [SyncManager] run it
/// through the exact same processed-operation de-dupe set as regular
/// operations.
@immutable
class ItemStateSnapshot {
  const ItemStateSnapshot({required this.item, required this.lastOperationId});

  final InventoryItem item;
  final String lastOperationId;

  Map<String, dynamic> toJsonMap() => {
        ...item.toMap(),
        'lastOperationId': lastOperationId,
      };

  factory ItemStateSnapshot.fromJsonMap(Map<String, dynamic> map) {
    return ItemStateSnapshot(
      item: InventoryItem.fromMap(map),
      lastOperationId: map['lastOperationId'] as String,
    );
  }
}
