import 'package:flutter_test/flutter_test.dart';
import 'package:smartnode_task/domain/entities/inventory_item.dart';
import 'package:smartnode_task/domain/entities/sync_status.dart';
import 'package:smartnode_task/domain/repositories/inventory_repository.dart';
import 'package:smartnode_task/presentation/controllers/inventory_controller.dart';

class _FakeRepository implements InventoryRepository {
  List<InventoryItem> items = [
    InventoryItem(id: '1', name: 'B Item', quantity: 5, updatedAt: DateTime(2026, 1, 1)),
    InventoryItem(id: '2', name: 'A Item', quantity: 3, updatedAt: DateTime(2026, 1, 1)),
  ];
  SyncStatus status = SyncStatus.online;
  int pending = 0;
  final List<(String, int)> changes = [];

  @override
  Future<void> init() async {}

  @override
  List<InventoryItem> get currentItems => items;

  @override
  SyncStatus get currentStatus => status;

  @override
  int get currentPendingCount => pending;

  @override
  Stream<List<InventoryItem>> watchItems() => const Stream.empty();

  @override
  Stream<SyncStatus> watchSyncStatus() => const Stream.empty();

  @override
  Stream<int> watchPendingCount() => const Stream.empty();

  @override
  Future<void> changeQuantity(String itemId, int delta) async {
    changes.add((itemId, delta));
  }

  @override
  void onAppResumed() {}

  @override
  Future<void> dispose() async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('controller exposes items sorted by name and forwards ready state', () async {
    final repo = _FakeRepository();
    final controller = InventoryController(repo);

    await controller.init();

    expect(controller.loadState, ViewLoadState.ready);
    expect(controller.items.map((e) => e.name), ['A Item', 'B Item']);
    expect(controller.syncStatus, SyncStatus.online);
  });

  test('increment/decrement delegate to the repository with the right delta', () async {
    final repo = _FakeRepository();
    final controller = InventoryController(repo);
    await controller.init();

    await controller.increment('1');
    await controller.decrement('2');

    expect(repo.changes, [('1', 1), ('2', -1)]);
  });
}
