import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants/app_constants.dart';
import '../../domain/entities/inventory_item.dart';

/// A single inventory row: a package icon, name, an optional low-stock tag,
/// a large readable quantity, and big touch-friendly +/- buttons. Designed
/// for a warehouse worker who needs to glance and tap quickly on a shelf
/// floor, not admire a UI - see README UI/UX notes.
class InventoryItemTile extends StatelessWidget {
  const InventoryItemTile({
    super.key,
    required this.item,
    required this.onIncrement,
    required this.onDecrement,
  });

  final InventoryItem item;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  static const double _buttonSize = 44;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final canDecrement = item.quantity > 0;
    final isLowStock = item.quantity <= AppConstants.lowStockThreshold;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 16, 14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.inventory_2_rounded, size: 22, color: scheme.onPrimaryContainer),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    item.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (isLowStock) ...[
                    const SizedBox(height: 4),
                    _LowStockTag(),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            _RoundIconButton(
              icon: Icons.remove_rounded,
              size: _buttonSize,
              filled: false,
              enabled: canDecrement,
              semanticLabel: 'Decrease ${item.name} quantity',
              onPressed: onDecrement,
            ),
            SizedBox(
              width: 52,
              child: Center(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 160),
                  transitionBuilder: (child, animation) =>
                      ScaleTransition(scale: animation, child: child),
                  child: Text(
                    '${item.quantity}',
                    key: ValueKey(item.quantity),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                  ),
                ),
              ),
            ),
            _RoundIconButton(
              icon: Icons.add_rounded,
              size: _buttonSize,
              filled: true,
              enabled: true,
              semanticLabel: 'Increase ${item.name} quantity',
              onPressed: onIncrement,
            ),
          ],
        ),
      ),
    );
  }
}

class _LowStockTag extends StatelessWidget {
  const _LowStockTag();

  static const _amber = Color(0xFFB07300);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: _amber.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _amber.withValues(alpha: 0.35)),
      ),
      child: const Text(
        'Low stock',
        style: TextStyle(
          color: _amber,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  const _RoundIconButton({
    required this.icon,
    required this.size,
    required this.filled,
    required this.enabled,
    required this.semanticLabel,
    required this.onPressed,
  });

  final IconData icon;
  final double size;
  final bool filled;
  final bool enabled;
  final String semanticLabel;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final Color background;
    final Color foreground;
    if (!enabled) {
      background = scheme.surfaceContainerHighest;
      foreground = scheme.onSurfaceVariant.withValues(alpha: 0.5);
    } else if (filled) {
      background = scheme.primary;
      foreground = scheme.onPrimary;
    } else {
      background = scheme.surfaceContainerHighest;
      foreground = scheme.onSurfaceVariant;
    }

    return Semantics(
      button: true,
      label: semanticLabel,
      child: SizedBox(
        width: size,
        height: size,
        child: Material(
          color: background,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: enabled
                ? () {
                    HapticFeedback.lightImpact();
                    onPressed();
                  }
                : null,
            child: Icon(icon, size: 20, color: foreground),
          ),
        ),
      ),
    );
  }
}
