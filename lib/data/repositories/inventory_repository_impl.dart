import '../../core/sync/sync_manager.dart';
import '../../domain/entities/inventory_item.dart';
import '../../domain/entities/sync_status.dart';
import '../../domain/repositories/inventory_repository.dart';

/// Thin adapter over [SyncManager]. Kept deliberately dumb: the interesting
/// logic (transport selection, dedupe, conflict handling) lives in
/// [SyncManager] so it can be unit-tested independently of this layer.
class InventoryRepositoryImpl implements InventoryRepository {
  InventoryRepositoryImpl(this._syncManager, this._defaultSeedItems);

  final SyncManager _syncManager;
  final List<InventoryItem> _defaultSeedItems;

  @override
  Future<void> init() => _syncManager.init(_defaultSeedItems);

  @override
  List<InventoryItem> get currentItems => _syncManager.currentItems;

  @override
  SyncStatus get currentStatus => _syncManager.currentStatus;

  @override
  int get currentPendingCount => _syncManager.currentPendingCount;

  @override
  Stream<List<InventoryItem>> watchItems() => _syncManager.itemsStream;

  @override
  Stream<SyncStatus> watchSyncStatus() => _syncManager.statusStream;

  @override
  Stream<int> watchPendingCount() => _syncManager.pendingCountStream;

  @override
  Future<void> changeQuantity(String itemId, int delta) =>
      _syncManager.changeQuantity(itemId, delta);

  @override
  void onAppResumed() => _syncManager.onAppResumed();

  @override
  Future<void> dispose() => _syncManager.dispose();
}
