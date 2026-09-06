import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:smartnode_task/domain/entities/inventory_item.dart';
import 'package:smartnode_task/domain/entities/sync_status.dart';
import 'package:smartnode_task/domain/repositories/inventory_repository.dart';
import 'package:smartnode_task/presentation/controllers/inventory_controller.dart';
import 'package:smartnode_task/presentation/screens/inventory_screen.dart';

class _FakeRepository implements InventoryRepository {
  final List<InventoryItem> _items = [
    InventoryItem(id: '1', name: 'Widget A', quantity: 5, updatedAt: DateTime(2026, 1, 1)),
  ];

  final _itemsController = StreamController<List<InventoryItem>>.broadcast();

  @override
  Future<void> init() async {}

  @override
  List<InventoryItem> get currentItems => _items;

  @override
  SyncStatus get currentStatus => SyncStatus.online;

  @override
  int get currentPendingCount => 0;

  @override
  Stream<List<InventoryItem>> watchItems() => _itemsController.stream;

  @override
  Stream<SyncStatus> watchSyncStatus() => const Stream.empty();

  @override
  Stream<int> watchPendingCount() => const Stream.empty();

  @override
  Future<void> changeQuantity(String itemId, int delta) async {
    final index = _items.indexWhere((i) => i.id == itemId);
    _items[index] = _items[index].copyWith(quantity: _items[index].quantity + delta);
    _itemsController.add(List.of(_items));
  }

  @override
  void onAppResumed() {}

  @override
  Future<void> dispose() async {}
}

void main() {
  testWidgets('shows inventory items and the online sync badge, and can tap +', (tester) async {
    final controller = InventoryController(_FakeRepository());
    await controller.init();

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider.value(
          value: controller,
          child: const InventoryScreen(),
        ),
      ),
    );

    expect(find.text('Widget A'), findsOneWidget);
    // The quantity chip is targeted by its ValueKey rather than plain text,
    // since the summary bar's "Total units" stat can coincidentally show
    // the same digit.
    expect(find.byKey(const ValueKey(5)), findsOneWidget);
    expect(find.text('Online'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Increase Widget A quantity'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200)); // let the quantity's switch animation settle

    expect(find.byKey(const ValueKey(6)), findsOneWidget);
  });

  testWidgets('shows empty state when there are no items', (tester) async {
    final repo = _FakeRepository();
    final controller = InventoryController(repo);
    repo._items.clear();
    await controller.init();

    await tester.pumpWidget(
      MaterialApp(
        home: ChangeNotifierProvider.value(
          value: controller,
          child: const InventoryScreen(),
        ),
      ),
    );

    expect(find.text('No inventory items'), findsOneWidget);
  });
}
