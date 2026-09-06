import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/inventory_controller.dart';
import '../widgets/inventory_item_tile.dart';
import '../widgets/inventory_summary_bar.dart';
import '../widgets/sync_status_badge.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Icon(Icons.warehouse_rounded, size: 22, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Flexible(child: Text('Stockroom', overflow: TextOverflow.ellipsis)),
          ],
        ),
        actions: [
          Consumer<InventoryController>(
            builder: (context, controller, _) => SyncStatusBadge(status: controller.syncStatus),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: Consumer<InventoryController>(
        builder: (context, controller, _) {
          return switch (controller.loadState) {
            ViewLoadState.loading => const Center(child: CircularProgressIndicator()),
            ViewLoadState.error => _ErrorState(message: controller.errorMessage),
            ViewLoadState.ready => Column(
                children: [
                  InventorySummaryBar(
                    items: controller.items,
                    pendingCount: controller.pendingCount,
                  ),
                  Expanded(
                    child: controller.items.isEmpty
                        ? const _EmptyState()
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            itemCount: controller.items.length,
                            itemBuilder: (context, index) {
                              final item = controller.items[index];
                              return InventoryItemTile(
                                item: item,
                                onIncrement: () => controller.increment(item.id),
                                onDecrement: () => controller.decrement(item.id),
                              );
                            },
                          ),
                  ),
                ],
              ),
          };
        },
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.inventory_2_outlined, size: 32, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text('No inventory items', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'Items will appear here once added.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message});

  final String? message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.errorContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline_rounded, size: 32, color: scheme.onErrorContainer),
            ),
            const SizedBox(height: 16),
            Text('Something went wrong', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              message ?? 'Please restart the app.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
