import 'package:flutter/material.dart';

import '../../domain/entities/sync_status.dart';

/// The required 🟢/🟡/🔴 indicator, rendered as an icon + colored pill with a
/// plain-language label. Tapping it reveals the fuller, non-technical
/// explanation via a snackbar rather than jargon in the app bar itself.
class SyncStatusBadge extends StatelessWidget {
  const SyncStatusBadge({super.key, required this.status});

  final SyncStatus status;

  Color get _color => switch (status) {
        SyncStatus.online => const Color(0xFF2E7D4F),
        SyncStatus.localNetworkOnly => const Color(0xFFB07300),
        SyncStatus.offline => const Color(0xFFC4402A),
        SyncStatus.connecting => const Color(0xFF6B7280),
      };

  IconData get _icon => switch (status) {
        SyncStatus.online => Icons.cloud_done_rounded,
        SyncStatus.localNetworkOnly => Icons.wifi_tethering_rounded,
        SyncStatus.offline => Icons.cloud_off_rounded,
        SyncStatus.connecting => Icons.sync_rounded,
      };

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Tooltip(
      message: status.description,
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: () {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(status.description)));
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: color.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_icon, size: 15, color: color),
              const SizedBox(width: 6),
              Text(
                status.label,
                style: TextStyle(
                  color: color,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
