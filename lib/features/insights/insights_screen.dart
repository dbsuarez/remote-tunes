import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/playback_widgets.dart' show formatTotalTime;
import '../../providers/providers.dart';
import 'insights_data.dart';

/// What the library says about itself (read on the phone, sent nowhere).
final insightsProvider = FutureProvider.autoDispose<LibraryInsights>(
  (ref) => loadInsights(ref.watch(databaseProvider)),
);

/// The Insights screen: totals, what is in the library (genres, artists, songs added by month) and
/// what is listened to (most played, most skipped, recently played).
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insights = ref.watch(insightsProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Insights'),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: () => ref.invalidate(insightsProvider),
          ),
        ],
      ),
      body: insights.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text("Couldn't read the library.")),
        data: (d) => InsightsView(insights: d),
      ),
    );
  }
}

/// The content of the screen (apart so it can be tested without a database).
class InsightsView extends StatelessWidget {
  const InsightsView({super.key, required this.insights});

  final LibraryInsights insights;

  static String _size(int bytes) {
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final d = insights;
    if (d.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Nothing to show yet. Add your music and the numbers appear here.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final hours = d.seconds / 3600;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Stat('Songs', '${d.songs}'),
            _Stat('Play time', formatTotalTime(d.seconds), note: '${hours.toStringAsFixed(1)} hours'),
            _Stat('Size', d.bytes > 0 ? _size(d.bytes) : '-'),
            _Stat('Artists', '${d.artists}'),
            _Stat('Albums', '${d.albums}'),
            _Stat('Favorites', '${d.favorites}'),
            _Stat('Never played', '${d.neverPlayed}'),
            _Stat('Played this week', '${d.playedThisWeek}'),
          ],
        ),
        _Section('Genres', d.genres, empty: 'No genres yet. In Settings, "Update tags from files" reads them.', unit: 'song'),
        _Section('Top artists', d.topArtists, empty: 'No artists yet.', unit: 'song'),
        _Months(d.addedByMonth),
        _Listening(d.playLog),
        _Section('Most played', d.mostPlayed, empty: 'Nothing played yet.', unit: 'play', showDetail: true),
        _Section('Most skipped', d.mostSkipped, empty: 'Nothing skipped yet.', unit: 'skip', showDetail: true),
        _Section('Recently played', d.recentlyPlayed, empty: 'Nothing played yet.', unit: '', showDetail: true, bars: false),
        _Section('Recently added', d.recentlyAdded, empty: 'No songs yet.', unit: '', showDetail: true, bars: false),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.note = ''});
  final String label;
  final String value;
  final String note;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 150,
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value, style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary)),
              Text(label, style: theme.textTheme.bodySmall),
              if (note.isNotEmpty)
                Text(note, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A titled list of rows, each with a bar as long as its number compared with the biggest.
class _Section extends StatelessWidget {
  const _Section(
    this.title,
    this.items, {
    required this.empty,
    required this.unit,
    this.showDetail = false,
    this.bars = true,
  });

  final String title;
  final List<InsightItem> items;
  final String empty;
  final String unit;
  final bool showDetail;
  final bool bars;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final biggest = items.fold<int>(1, (m, i) => i.value > m ? i.value : m);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Text(empty, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          for (final i in items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(i.label, maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if (unit.isNotEmpty)
                        Text('${i.value} $unit${i.value == 1 || unit == 'min' ? '' : 's'}',
            style: theme.textTheme.labelMedium),
                    ],
                  ),
                  if (showDetail && i.detail.isNotEmpty)
                    Text(i.detail,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  if (bars)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          key: ValueKey('bar-$title-${i.label}'),
                          value: i.value / biggest,
                          minHeight: 6,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Songs added in each of the last twelve months, as upright bars.
class _Months extends StatelessWidget {
  const _Months(this.months, {this.title = 'Songs added, last 12 months', this.unit = 'song', this.keyPrefix = 'month'});
  final List<InsightItem> months;
  final String title;
  final String unit;
  final String keyPrefix;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final biggest = months.fold<int>(1, (m, i) => i.value > m ? i.value : m);
    final total = months.fold<int>(0, (s, i) => s + i.value);
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('$total $unit${total == 1 ? '' : 's'}',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 8),
          SizedBox(
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final m in months)
                  Expanded(
                    child: Tooltip(
                      message: '${m.label}: ${m.value}',
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (m.value > 0) Text('${m.value}', style: const TextStyle(fontSize: 10)),
                          Container(
                            key: ValueKey('$keyPrefix-${m.label}'),
                            height: 4 + 70 * (m.value / biggest),
                            margin: const EdgeInsets.symmetric(horizontal: 2),
                            decoration: BoxDecoration(
                              color: m.value == 0
                                  ? theme.colorScheme.surfaceContainerHighest
                                  : theme.colorScheme.primary,
                              borderRadius: BorderRadius.circular(3),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(m.label.length >= 7 ? m.label.substring(5) : m.label.substring(m.label.length - 2),
                              style: TextStyle(fontSize: 10, color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// What the play log says: time listened, plays per day, and where the time went.
class _Listening extends StatelessWidget {
  const _Listening(this.log);
  final PlayLogInsights log;

  static String _hm(int seconds) {
    final m = (seconds / 60).round();
    return m >= 60 ? '${m ~/ 60} h ${m % 60} min' : '$m min';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (log.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Listening', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Nothing recorded yet. From now on each song you play is noted (when it started, how long you '
              'heard it, how it ended), and this fills in. It stays on this phone; Settings can switch it off or clear it.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }
    final ended = log.finished + log.skipped;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 8),
          child: Text('Listening', style: theme.textTheme.titleMedium),
        ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Stat('This week', _hm(log.weekSeconds), note: '${log.weekPlays} plays'),
            _Stat('Recorded', _hm(log.totalSeconds), note: '${log.plays} plays'),
            if (ended > 0) _Stat('Played to the end', '${(100 * log.finished / ended).round()}%', note: '${log.skipped} skipped'),
          ],
        ),
        _Months(log.playsByDay, title: 'Plays, last 14 days', unit: 'play', keyPrefix: 'plays'),
        _Months(log.minutesByDay, title: 'Minutes listened, last 14 days', unit: 'minute', keyPrefix: 'minutes'),
        _Section('Listening by genre', log.minutesByGenre, empty: 'No genres yet.', unit: 'min'),
        _Section('Most listened artists', log.minutesByArtist, empty: 'No artists yet.', unit: 'min'),
      ],
    );
  }
}
