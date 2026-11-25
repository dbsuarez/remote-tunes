import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'update_controller.dart';
import 'update_service.dart';

/// What changed in each version (the release notes from GitHub).
class ChangelogScreen extends ConsumerStatefulWidget {
  const ChangelogScreen({super.key});

  @override
  ConsumerState<ChangelogScreen> createState() => _ChangelogScreenState();
}

class _ChangelogScreenState extends ConsumerState<ChangelogScreen> {
  late Future<List<ReleaseNote>> _releases = _load();

  Future<List<ReleaseNote>> _load() => ref.read(updateCheckerProvider).recentReleases();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final installed = ref.watch(updateProvider).installed;
    return Scaffold(
      appBar: AppBar(title: const Text("What's new")),
      body: SafeArea(
        child: FutureBuilder<List<ReleaseNote>>(
          future: _releases,
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        snap.error is UpdateException
                            ? (snap.error as UpdateException).message
                            : "Couldn't load the release notes.",
                        textAlign: TextAlign.center,
                      ),
                      TextButton(
                        onPressed: () => setState(() => _releases = _load()),
                        child: const Text('Try again'),
                      ),
                    ],
                  ),
                ),
              );
            }
            final items = snap.data!;
            if (items.isEmpty) {
              return const Center(child: Text('No releases yet.'));
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 32),
              itemBuilder: (context, i) {
                final r = items[i];
                final date = r.published == null
                    ? ''
                    : ' · ${r.published!.year}-${r.published!.month.toString().padLeft(2, '0')}-${r.published!.day.toString().padLeft(2, '0')}';
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text('Version ${r.version}', style: theme.textTheme.titleMedium),
                        if (r.version == installed) ...[
                          const SizedBox(width: 8),
                          Chip(
                            label: const Text('installed'),
                            visualDensity: VisualDensity.compact,
                            backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.2),
                          ),
                        ],
                      ],
                    ),
                    Text(
                      '${r.title.isEmpty ? '' : r.title}$date',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 8),
                    Text(r.notes.isEmpty ? 'No notes for this version.' : r.notes),
                  ],
                );
              },
            );
          },
        ),
      ),
    );
  }
}
