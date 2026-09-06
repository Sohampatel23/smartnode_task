import '../entities/inventory_item.dart';
import '../entities/pending_operation.dart';

/// Persists the converged inventory state. Abstracted so the sync layer
/// doesn't know or care whether the concrete implementation uses Hive,
/// SQLite, or an in-memory fake in tests.
abstract class InventoryLocalStore {
  Future<void> init();

  List<InventoryItem> loadItems();

  Future<void> saveItem(InventoryItem item);

  /// Populates the store with [defaults] only if it is currently empty
  /// (first launch).
  Future<void> seedIfEmpty(List<InventoryItem> defaults);
}

/// Persists operations that have not yet been confirmed delivered to the
/// MQTT broker.
abstract class OperationQueueStore {
  Future<void> init();

  List<PendingOperation> loadPending();

  Future<void> enqueue(PendingOperation operation);

  Future<void> updateStatus(String operationId, PendingStatus status, {int? retryCount});

  Future<void> remove(String operationId);
}

/// Tracks operation ids that have already been applied to local state, so
/// re-delivery (QoS 1 redelivery, a UDP retransmit, or the same op arriving
/// over two transports) is a no-op instead of double-applying a delta.
abstract class ProcessedOperationsStore {
  Future<void> init();

  bool hasProcessed(String operationId);

  Future<void> markProcessed(String operationId);
}

/// Stable per-install identifier used to attribute operations and to let a
/// device recognize (and ignore) its own UDP broadcasts.
abstract class DeviceIdStore {
  Future<String> getOrCreateDeviceId();
}
