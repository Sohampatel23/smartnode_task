import 'package:flutter/material.dart';

import '../../domain/entities/inventory_item.dart';

/// A compact at-a-glance strip: how many distinct items, how many total
/// units on the floor, and how many changes are still waiting to reach the
/// cloud. One row, no cards-within-cards - just enough for a worker to
/// sanity-check the shelf without reading every line.
class InventorySummaryBar extends StatelessWidget {
  const InventorySummaryBar({super.key, required this.items, required this.pendingCount});

  final List<InventoryItem> items;
  final int pendingCount;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final totalUnits = items.fold<int>(0, (sum, item) => sum + item.quantity);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.4))),
      ),
      child: Row(
        children: [
          _Stat(label: 'Items', value: '${items.length}'),
          _divider(scheme),
          _Stat(label: 'Total units', value: '$totalUnits'),
          if (pendingCount > 0) ...[
            _divider(scheme),
            _Stat(
              label: 'Pending sync',
              value: '$pendingCount',
              color: const Color(0xFFB07300),
            ),
          ],
        ],
      ),
    );
  }

  Widget _divider(ColorScheme scheme) => Container(
        width: 1,
        height: 28,
        margin: const EdgeInsets.symmetric(horizontal: 16),
        color: scheme.outlineVariant.withValues(alpha: 0.5),
      );
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, this.color});

  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                color: color ?? scheme.onSurface,
              ),
        ),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
        ),
      ],
    );
  }
}
