import '../entities/inventory_item.dart';
import '../entities/sync_status.dart';

/// The single surface the presentation layer talks to. It knows nothing
/// about MQTT, UDP, connectivity, or persistence - all of that lives behind
/// the [SyncManager] this repository delegates to.
abstract class InventoryRepository {
  Future<void> init();

  List<InventoryItem> get currentItems;

  SyncStatus get currentStatus;

  int get currentPendingCount;

  Stream<List<InventoryItem>> watchItems();

  Stream<SyncStatus> watchSyncStatus();

  Stream<int> watchPendingCount();

  /// Applies [delta] to [itemId] (e.g. +1 / -1) and routes the resulting
  /// operation through cloud sync, local fallback, and/or the offline
  /// queue as appropriate for the current network state.
  Future<void> changeQuantity(String itemId, int delta);

  /// Hint that the app just returned to the foreground - lets the sync
  /// layer nudge a reconnect attempt without waiting for the passive
  /// reconnect timer.
  void onAppResumed();

  Future<void> dispose();
}
