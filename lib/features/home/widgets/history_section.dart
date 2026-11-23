import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/providers.dart';

/// Connection history from `paired_controllers`. Empty in Phase 0.
class HistorySection extends ConsumerWidget {
  const HistorySection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final history = ref.watch(connectionHistoryProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Connection history', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        history.when(
          loading: () => const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Text(
            'Could not load history.',
            style: TextStyle(color: theme.colorScheme.error),
          ),
          data: (rows) {
            if (rows.isEmpty) {
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(Icons.history_rounded,
                          color: theme.colorScheme.onSurfaceVariant),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'No connections yet. Paired devices will appear here.',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
            return Card(
              child: Column(
                children: [
                  for (final r in rows)
                    ListTile(
                      minTileHeight: 56,
                      leading: Icon(r.connectionType == 'online'
                          ? Icons.cloud_outlined
                          : Icons.wifi_rounded),
                      title: Text(r.controllerName),
                      subtitle: Text(r.controllerAddress ?? r.connectionType),
                    ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }
}
