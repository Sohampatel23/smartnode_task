import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/app_constants.dart';
import '../../core/errors/app_exceptions.dart';
import '../../core/utils/app_logger.dart';
import '../../domain/entities/pending_operation.dart';
import '../../domain/repositories/local_store.dart';

/// Hive-backed offline queue. Entries persist across app restarts so that an
/// app kill mid-sync (or while fully offline) never silently drops a
/// warehouse worker's change - they are only removed once the [SyncManager]
/// confirms delivery.
class HiveOperationQueueStore implements OperationQueueStore {
  late Box _box;

  @override
  Future<void> init() async {
    try {
      _box = await Hive.openBox(AppConstants.pendingQueueBoxName);
    } catch (e, st) {
      AppLogger.error('Failed to open pending queue box', e, st);
      throw const StorageException('Could not open the pending sync queue.');
    }
  }

  @override
  List<PendingOperation> loadPending() {
    final items = _box.values
        .cast<Map>()
        .map((raw) => PendingOperation.fromStorageMap(raw))
        .toList();
    // Oldest-first so operations are re-published in the order they were
    // made once connectivity returns.
    items.sort((a, b) => a.enqueuedAt.compareTo(b.enqueuedAt));
    return items;
  }

  @override
  Future<void> enqueue(PendingOperation operation) async {
    await _box.put(operation.operation.operationId, operation.toStorageMap());
  }

  @override
  Future<void> updateStatus(String operationId, PendingStatus status, {int? retryCount}) async {
    final raw = _box.get(operationId);
    if (raw == null) return;
    final current = PendingOperation.fromStorageMap(raw as Map);
    final updated = current.copyWith(status: status, retryCount: retryCount);
    await _box.put(operationId, updated.toStorageMap());
  }

  @override
  Future<void> remove(String operationId) async {
    await _box.delete(operationId);
  }
}
