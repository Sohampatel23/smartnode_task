import '../entities/inventory_item.dart';
import '../entities/inventory_operation.dart';
import '../entities/item_state_snapshot.dart';

/// Contract for real-time cloud sync over MQTT. Kept as an interface so the
/// [SyncManager] (and its tests) never depend on the concrete `mqtt_client`
/// package directly - see `data/mqtt/mqtt_service_impl.dart` for the real
/// implementation and a fake in `test/` for unit tests.
abstract class MqttService {
  /// True while connected to the broker with an active subscription.
  Stream<bool> get connectionState;

  /// Successfully parsed, validated operations received from the broker
  /// (malformed payloads are dropped before reaching this stream).
  Stream<InventoryOperation> get incomingOperations;

  /// Retained "current value" snapshots received from the broker - see
  /// [publishItemState]. Used to catch a reconnecting device up on changes
  /// it missed entirely while disconnected, which [incomingOperations]
  /// alone cannot do.
  Stream<ItemStateSnapshot> get incomingItemStates;

  bool get isConnected;

  Future<void> connect();

  Future<void> disconnect();

  /// Publishes [operation]. Returns true if the client accepted the publish
  /// call (i.e. was connected) - callers should not treat this as a
  /// guarantee of broker-side delivery; use [connectionState] plus
  /// application-level idempotency for that.
  Future<bool> publish(InventoryOperation operation);

  /// Publishes [item]'s converged quantity as a *retained* message, tagged
  /// with [causeOperationId] (the operation that produced this value), so
  /// any device that subscribes later - even long after this publish -
  /// gets it immediately, regardless of how many operations it missed
  /// while offline.
  Future<bool> publishItemState(InventoryItem item, String causeOperationId);
}
