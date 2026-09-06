import 'package:flutter/foundation.dart';

import 'inventory_operation.dart';

enum PendingStatus { pending, syncing, failed }

/// A queued [InventoryOperation] awaiting confirmed delivery to the MQTT
/// broker. Entries are only removed once the broker has acknowledged
/// delivery (QoS 1 puback) - not merely once a publish call has been made -
/// so an app kill mid-flush cannot silently lose an update.
@immutable
class PendingOperation {
  const PendingOperation({
    required this.operation,
    required this.status,
    required this.retryCount,
    required this.enqueuedAt,
  });

  final InventoryOperation operation;
  final PendingStatus status;
  final int retryCount;
  final DateTime enqueuedAt;

  PendingOperation copyWith({PendingStatus? status, int? retryCount}) {
    return PendingOperation(
      operation: operation,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      enqueuedAt: enqueuedAt,
    );
  }

  Map<String, dynamic> toStorageMap() => {
        'operation': operation.toStorageMap(),
        'status': status.name,
        'retryCount': retryCount,
        'enqueuedAt': enqueuedAt.toIso8601String(),
      };

  factory PendingOperation.fromStorageMap(Map<dynamic, dynamic> map) {
    return PendingOperation(
      operation: InventoryOperation.fromStorageMap(
        Map<dynamic, dynamic>.from(map['operation'] as Map),
      ),
      status: PendingStatus.values.byName(map['status'] as String),
      retryCount: map['retryCount'] as int,
      enqueuedAt: DateTime.parse(map['enqueuedAt'] as String),
    );
  }
}
