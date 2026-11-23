import 'package:flutter/material.dart';

import '../../../core/models/enums.dart';
import '../../../core/theme/app_theme.dart';

/// Prominent connection pill (docs/15_UX_DESIGN_GUARDRAILS.md §6).
/// Phase 0 has no live connection, so it shows "Not connected" plus the
/// selected mode. Online-only uses violet, distinct from local teal.
class ConnectionPill extends StatelessWidget {
  const ConnectionPill({super.key, required this.mode});

  final ConnectionMode mode;

  @override
  Widget build(BuildContext context) {
    final online = mode == ConnectionMode.onlineOnly;
    final color = online ? RtColors.violet : RtColors.teal;
    final icon = switch (mode) {
      ConnectionMode.auto => Icons.sync_alt_rounded,
      ConnectionMode.localOnly => Icons.wifi_rounded,
      ConnectionMode.onlineOnly => Icons.cloud_outlined,
    };

    return Semantics(
      label: 'Not connected. Mode: ${mode.label}',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: color.withValues(alpha: 0.6)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Not connected · ${mode.label}',
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .labelLarge
                    ?.copyWith(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
