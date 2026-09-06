import 'package:smartnode_task/domain/entities/inventory_item.dart';
import 'package:smartnode_task/domain/entities/pending_operation.dart';
import 'package:smartnode_task/domain/repositories/local_store.dart';

class InMemoryInventoryLocalStore implements InventoryLocalStore {
  final Map<String, InventoryItem> _items = {};

  @override
  Future<void> init() async {}

  @override
  List<InventoryItem> loadItems() => _items.values.toList();

  @override
  Future<void> saveItem(InventoryItem item) async {
    _items[item.id] = item;
  }

  @override
  Future<void> seedIfEmpty(List<InventoryItem> defaults) async {
    if (_items.isNotEmpty) return;
    for (final item in defaults) {
      _items[item.id] = item;
    }
  }
}

class InMemoryOperationQueueStore implements OperationQueueStore {
  final Map<String, PendingOperation> _pending = {};

  @override
  Future<void> init() async {}

  @override
  List<PendingOperation> loadPending() {
    final list = _pending.values.toList();
    list.sort((a, b) => a.enqueuedAt.compareTo(b.enqueuedAt));
    return list;
  }

  @override
  Future<void> enqueue(PendingOperation operation) async {
    _pending[operation.operation.operationId] = operation;
  }

  @override
  Future<void> updateStatus(String operationId, PendingStatus status, {int? retryCount}) async {
    final current = _pending[operationId];
    if (current == null) return;
    _pending[operationId] = current.copyWith(status: status, retryCount: retryCount);
  }

  @override
  Future<void> remove(String operationId) async {
    _pending.remove(operationId);
  }
}

class InMemoryProcessedOperationsStore implements ProcessedOperationsStore {
  final Set<String> _seen = {};

  @override
  Future<void> init() async {}

  @override
  bool hasProcessed(String operationId) => _seen.contains(operationId);

  @override
  Future<void> markProcessed(String operationId) async {
    _seen.add(operationId);
  }
}
