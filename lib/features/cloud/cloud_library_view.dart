import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/widgets/default_art.dart';
import '../../core/widgets/playback_widgets.dart' show formatDuration;
import '../music/music_source.dart' show friendlyError;
import 'cloud_config_store.dart';
import 'cloud_models.dart';
import 'r2_client.dart';

/// Plays or queues a cloud song: [audioUrl] is its public link, [imageUrl] its cover. Throws on
/// failure; the screen shows the reason.
typedef CloudTrackAction = Future<void> Function(CloudSong song, String audioUrl, String? imageUrl, {required bool queue});

/// The Cloud Library: your own songs in your own R2 bucket. Browse, search by words, filter by genre,
/// play on this phone (or on the Player when controlling another phone), queue, and delete if this
/// phone has the keys. Songs are put up from the Library (select songs, then Upload to cloud).
class CloudLibraryView extends ConsumerStatefulWidget {
  const CloudLibraryView({super.key, required this.onTrack, this.enabled = true, this.onOpenSettings});

  final CloudTrackAction onTrack;

  /// False while the Controller is reconnecting.
  final bool enabled;

  /// Opens the Cloud Library settings (null: not offered, for example in the browser).
  final VoidCallback? onOpenSettings;

  /// How many rows are drawn at once (a search narrows the rest).
  static const maxRows = 300;

  /// The free R2 storage, for the "used" line.
  static const freeBytes = 10 * 1024 * 1024 * 1024;

  @override
  ConsumerState<CloudLibraryView> createState() => _CloudLibraryViewState();
}

class _CloudLibraryViewState extends ConsumerState<CloudLibraryView> {
  final _search = TextEditingController();
  CloudCatalog? _catalog;
  bool _loading = false;
  String? _error;
  String _query = '';
  String? _genre;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final config = await ref.read(cloudConfigProvider.future);
    if (!mounted) return;
    if (!config.canRead) {
      setState(() {
        _catalog = null;
        _error = null;
      });
      return;
    }
    final gen = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final catalog = await (await ref.read(cloudServiceProvider.future)).fetchCatalog();
      if (!mounted || gen != _generation) return;
      setState(() {
        _catalog = catalog;
        _loading = false;
        if (_genre != null && !catalog.genres.any((g) => g.name == _genre)) _genre = null;
      });
    } on R2Exception catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = 'Something went wrong. Try again.';
        _loading = false;
      });
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _act(CloudSong s, {required bool queue}) async {
    final config = ref.read(cloudConfigProvider).valueOrNull;
    if (config == null) return;
    try {
      await widget.onTrack(s, config.urlFor(s.audioKey), s.artKey == null ? null : config.urlFor(s.artKey!), queue: queue);
      _snack(queue ? 'Added to the queue' : 'Playing "${s.title}"');
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  /// The first plays, the rest are queued.
  Future<void> _playAll(List<CloudSong> songs) async {
    final config = ref.read(cloudConfigProvider).valueOrNull;
    if (config == null || songs.isEmpty) return;
    try {
      for (var i = 0; i < songs.length; i++) {
        final s = songs[i];
        await widget.onTrack(s, config.urlFor(s.audioKey), s.artKey == null ? null : config.urlFor(s.artKey!), queue: i > 0);
      }
      _snack('Playing ${songs.length} song${songs.length == 1 ? '' : 's'}');
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  Future<void> _queueAll(List<CloudSong> songs) async {
    final config = ref.read(cloudConfigProvider).valueOrNull;
    if (config == null || songs.isEmpty) return;
    try {
      for (final s in songs) {
        await widget.onTrack(s, config.urlFor(s.audioKey), s.artKey == null ? null : config.urlFor(s.artKey!), queue: true);
      }
      _snack('Added ${songs.length} song${songs.length == 1 ? '' : 's'} to the queue');
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  Future<void> _delete(CloudSong s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${s.title}" from the cloud?'),
        content: const Text('The song and its listing are removed from your bucket. The copy on this phone (if any) stays.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(key: const Key('cloud-delete-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await (await ref.read(cloudServiceProvider.future)).remove([s]);
      _snack('Deleted from the cloud.');
      await _refresh();
    } on R2Exception catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack("It couldn't be deleted. Try again.");
    }
  }

  static String _size(int bytes) {
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    // New settings (just saved) load the catalog again.
    ref.listen(cloudConfigProvider, (a, b) {
      if (a?.valueOrNull?.publicUrl != b.valueOrNull?.publicUrl) _refresh();
    });
    final config = ref.watch(cloudConfigProvider).valueOrNull;
    if (config == null) return const Center(child: CircularProgressIndicator());
    if (!config.canRead) return _setup(theme, muted);

    final catalog = _catalog;
    final shown = catalog?.search(_query, genre: _genre) ?? const <CloudSong>[];
    final rows = shown.take(CloudLibraryView.maxRows).toList();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  catalog == null
                      ? 'Your cloud songs'
                      : '${catalog.songs.length} song${catalog.songs.length == 1 ? '' : 's'}'
                          '${catalog.totalBytes > 0 ? ' · ${_size(catalog.totalBytes)} of ${_size(CloudLibraryView.freeBytes)} free' : ''}',
                  key: const Key('cloud-summary'),
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton(
                key: const Key('cloud-refresh'),
                tooltip: 'Refresh',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: _loading ? null : _refresh,
              ),
              if (widget.onOpenSettings != null)
                IconButton(tooltip: 'Cloud Library settings', icon: const Icon(Icons.settings_outlined), onPressed: widget.onOpenSettings),
            ],
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(child: _body(theme, muted, config, catalog, shown, rows)),
      ],
    );
  }

  Widget _setup(ThemeData theme, TextStyle? muted) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_outlined, size: 40, color: theme.colorScheme.primary),
              const SizedBox(height: 12),
              Text('Your own songs in the cloud', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'Put the public address of your Cloudflare R2 bucket in Settings > Lyrics and online > Cloud Library, '
                'and your songs show up here.',
                textAlign: TextAlign.center,
                style: muted,
              ),
              if (widget.onOpenSettings != null) ...[
                const SizedBox(height: 12),
                FilledButton(key: const Key('cloud-open-settings'), onPressed: widget.onOpenSettings, child: const Text('Open the settings')),
              ],
            ],
          ),
        ),
      );

  Widget _body(ThemeData theme, TextStyle? muted, CloudConfig config, CloudCatalog? catalog, List<CloudSong> shown, List<CloudSong> rows) {
    if (_error != null && catalog == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center, key: const Key('cloud-error')),
              const SizedBox(height: 12),
              OutlinedButton(key: const Key('cloud-retry'), onPressed: _refresh, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (catalog == null) return const SizedBox.shrink();
    if (catalog.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Nothing is in the cloud yet. In your Library, long-press songs to select them, then tap Upload to cloud.',
            textAlign: TextAlign.center,
            style: muted,
          ),
        ),
      );
    }
    final genres = catalog.genres;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: TextField(
            key: const Key('cloud-search'),
            controller: _search,
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.search_rounded),
              hintText: 'Search title, artist, album, genre',
              suffixIcon: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear search',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() {
                        _search.clear();
                        _query = '';
                      }),
                    ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        if (genres.isNotEmpty)
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: [
                ChoiceChip(
                  key: const Key('cloud-genre-all'),
                  label: const Text('All'),
                  selected: _genre == null,
                  onSelected: (_) => setState(() => _genre = null),
                ),
                for (final g in genres) ...[
                  const SizedBox(width: 8),
                  ChoiceChip(
                    key: ValueKey('cloud-genre-${g.name}'),
                    label: Text('${g.name} (${g.count})'),
                    selected: _genre == g.name,
                    onSelected: (_) => setState(() => _genre = _genre == g.name ? null : g.name),
                  ),
                ],
              ],
            ),
          ),
        if (shown.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
            child: Row(
              children: [
                TextButton.icon(
                  key: const Key('cloud-play-all'),
                  onPressed: widget.enabled ? () => _playAll(shown.take(200).toList()) : null,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: Text('Play all (${shown.length > 200 ? '200' : shown.length})'),
                ),
                TextButton.icon(
                  key: const Key('cloud-queue-all'),
                  onPressed: widget.enabled ? () => _queueAll(shown.take(200).toList()) : null,
                  icon: const Icon(Icons.queue_music_rounded),
                  label: const Text('Add all'),
                ),
              ],
            ),
          ),
        Expanded(
          child: shown.isEmpty
              ? Center(child: Text('No songs match.', style: muted))
              : ListView.builder(
                  itemCount: rows.length + (shown.length > rows.length ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= rows.length) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('Showing the first ${rows.length} of ${shown.length}. Search to narrow it down.',
                            textAlign: TextAlign.center, style: muted),
                      );
                    }
                    return _row(theme, config, rows[i]);
                  },
                ),
        ),
      ],
    );
  }

  Widget _row(ThemeData theme, CloudConfig config, CloudSong s) {
    final art = s.artKey == null ? null : config.urlFor(s.artKey!);
    return ListTile(
      key: ValueKey('cloud-song-${s.id}'),
      minTileHeight: 64,
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 44,
          height: 44,
          child: art == null
              ? DefaultArt.albumAvatar(radius: 22)
              : Image.network(
                  art,
                  fit: BoxFit.cover,
                  cacheWidth: 132,
                  errorBuilder: (_, __, ___) => DefaultArt.albumAvatar(radius: 22),
                ),
        ),
      ),
      title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [if (s.artist.isNotEmpty) s.artist, if (s.album.isNotEmpty) s.album].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (s.durationSeconds > 0) Text(formatDuration(s.durationSeconds), style: theme.textTheme.bodySmall),
          PopupMenuButton<String>(
            tooltip: 'More for ${s.title}',
            onSelected: (a) => a == 'play'
                ? _act(s, queue: false)
                : a == 'queue'
                    ? _act(s, queue: true)
                    : _delete(s),
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'play', child: Text('Play')),
              const PopupMenuItem(value: 'queue', child: Text('Add to queue')),
              if (config.canWrite) const PopupMenuItem(value: 'delete', child: Text('Delete from the cloud')),
            ],
          ),
        ],
      ),
      onTap: widget.enabled ? () => _act(s, queue: false) : null,
      onLongPress: widget.enabled ? () => _act(s, queue: true) : null,
    );
  }
}
