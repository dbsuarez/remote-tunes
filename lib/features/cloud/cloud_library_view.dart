import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/album_name.dart';
import '../../core/utils/shuffle_start.dart';
import '../../core/widgets/default_art.dart';
import '../../core/widgets/playback_widgets.dart' show formatDuration;
import '../music/music_source.dart' show friendlyError;
import 'cloud_config_store.dart';
import 'cloud_history.dart';
import 'cloud_models.dart';
import 'cloud_pickers.dart';
import 'cloud_service.dart';
import 'r2_client.dart';

/// Plays or queues a cloud song: [audioUrl] is its public link, [imageUrl] its cover. Throws on
/// failure; the screen shows the reason.
typedef CloudTrackAction = Future<void> Function(CloudSong song, String audioUrl, String? imageUrl, {required bool queue});

enum _Tab { songs, artists, albums, playlists }

enum _PageKind { artist, album, playlist }

/// A page opened from a list: one artist, one album or one playlist.
class _Page {
  const _Page(this.kind, this.key, this.title);
  final _PageKind kind;
  final String key;
  final String title;
}

/// The Cloud Library: your own songs in your own R2 bucket. Browse by song, artist, album or playlist,
/// search by words, filter by genre, play on this phone (or on the Player when controlling another phone)
/// and queue; sort the songs, or list the ones started here lately; pick several at once. A device with the
/// keys can also edit songs' details and covers, make and reorder playlists, and delete songs.
/// Songs are put up from the Library (select songs, then Upload to cloud) or from the web page.
class CloudLibraryView extends ConsumerStatefulWidget {
  const CloudLibraryView(
      {super.key, required this.onTrack, this.enabled = true, this.onOpenSettings, this.onUpload, this.shuffleOn});

  /// Whether the player is shuffling now (then *Play all* and *Add all* start on any song).
  final bool Function()? shuffleOn;

  /// Starts an upload of songs picked here (the web page; the phone uploads from the Library). Null: not offered.
  final Future<void> Function()? onUpload;

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
  _Tab _tab = _Tab.songs;
  _Page? _page;
  int _generation = 0;
  CloudSort _sort = CloudSort.title;
  List<String> _recent = const [];

  /// The ids of the songs picked, while picking several; null otherwise.
  Set<String>? _selected;

  /// The new order of a playlist's songs, while reordering it; null otherwise.
  List<String>? _order;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
    _remembered();
  }

  Future<void> _remembered() async {
    final store = ref.read(cloudHistoryStoreProvider);
    final sort = await store.sort();
    final recent = await store.recent();
    if (!mounted) return;
    setState(() {
      _sort = sort;
      // Songs started while this was being read come first.
      _recent = [..._recent, ...recent.where((id) => !_recent.contains(id))];
    });
  }

  /// Notes that [s] was started from this screen.
  void _noteStarted(CloudSong s) {
    if (!mounted) return;
    final next = CloudHistoryStore.played(_recent, s.id);
    setState(() => _recent = next);
    ref.read(cloudHistoryStoreProvider).saveRecent(next);
  }

  /// Leaves a page, picking or reordering.
  void _show({_Tab? tab, _Page? page}) => setState(() {
        if (tab != null) _tab = tab;
        _page = page;
        _selected = null;
        _order = null;
      });

  /// One step back: out of picking or reordering first, then out of the page.
  void _back() {
    if (_selected != null || _order != null) {
      setState(() {
        _selected = null;
        _order = null;
      });
    } else {
      setState(() => _page = null);
    }
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

  /// Runs a change to the catalog (needs the keys) and shows the result. False if it failed (the reason
  /// is shown).
  Future<bool> _change(Future<CloudCatalog> Function(CloudLibraryService service) run, {String? done}) async {
    try {
      final next = await run(await ref.read(cloudServiceProvider.future));
      if (!mounted) return false;
      setState(() {
        // A reload that started earlier must not put the old list back.
        _generation++;
        _loading = false;
        _catalog = next;
        if (_genre != null && !next.genres.any((g) => g.name == _genre)) _genre = null;
      });
      if (done != null) _snack(done);
      return true;
    } on R2Exception catch (e) {
      _snack(e.message);
    } catch (_) {
      _snack("That couldn't be saved. Try again.");
    }
    return false;
  }

  // ------------------------------------------------------------------ playing

  Future<void> _act(CloudSong s, {required bool queue}) async {
    final config = ref.read(cloudConfigProvider).valueOrNull;
    if (config == null) return;
    try {
      await widget.onTrack(s, config.urlFor(s.audioKey), s.artKey == null ? null : config.urlFor(s.artKey!), queue: queue);
      if (!queue) _noteStarted(s);
      _snack(queue ? 'Added to the queue' : 'Playing "${s.title}"');
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  List<CloudSong> _ordered(List<CloudSong> songs) => startAnywhere(songs, shuffle: widget.shuffleOn?.call() ?? false);

  /// The first plays (any song with shuffle on), the rest are queued.
  Future<void> _playAll(List<CloudSong> list) async {
    final songs = _ordered(list);
    final config = ref.read(cloudConfigProvider).valueOrNull;
    if (config == null || songs.isEmpty) return;
    try {
      for (var i = 0; i < songs.length; i++) {
        final s = songs[i];
        await widget.onTrack(s, config.urlFor(s.audioKey), s.artKey == null ? null : config.urlFor(s.artKey!), queue: i > 0);
        if (i == 0) _noteStarted(s);
      }
      _snack('Playing ${songs.length} song${songs.length == 1 ? '' : 's'}');
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  Future<void> _queueAll(List<CloudSong> list) async {
    final songs = _ordered(list);
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

  // ------------------------------------------------------------------ editing

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

  Future<void> _editInfo(CloudSong s) async {
    final edited = await showDialog<CloudSong>(context: context, builder: (_) => _EditSongDialog(song: s));
    if (edited == null || !mounted) return;
    await _change((service) => service.updateSong(edited), done: 'Saved');
  }

  Future<void> _editSeveral(List<CloudSong> songs) async {
    final changes = await showDialog<_Shared>(context: context, builder: (_) => _EditSeveralDialog(count: songs.length));
    if (changes == null || !mounted) return;
    final saved = await _change(
      (service) => service.updateSongs([for (final s in songs) s.id],
          artist: changes.artist, album: changes.album, genre: changes.genre, year: changes.year),
      done: 'Saved ${_count(songs.length, 'song')}',
    );
    if (saved && mounted) setState(() => _selected = null);
  }

  Future<void> _changeCover(CloudSong s) async {
    final pick = ref.read(cloudCoverPickerProvider);
    final catalog = _catalog;
    if (pick == null || catalog == null) return;
    final Uint8List? bytes;
    try {
      bytes = await pick();
    } catch (_) {
      _snack("That picture couldn't be opened.");
      return;
    }
    if (bytes == null || !mounted) return;
    if (CloudLibraryService.coverType(bytes) == null) {
      _snack('Pick a JPG or PNG picture.');
      return;
    }
    // The other songs of its album (a song with no album has none).
    final album = isRealAlbum(s.album)
        ? catalog.songsOfAlbum(CloudAlbum(title: s.album, artist: s.artist, songs: 0))
        : <CloudSong>[s];
    final ids = await showDialog<List<String>>(
      context: context,
      builder: (_) => _CoverDialog(bytes: bytes!, song: s, albumIds: [for (final x in album) x.id]),
    );
    if (ids == null || !mounted) return;
    await _change((service) => service.setCover(ids, bytes!), done: 'Cover changed');
  }

  Future<void> _saveOrder(CloudPlaylist p) async {
    final order = _order;
    if (order == null) return;
    final saved = await _change((service) => service.reorderPlaylist(p.id, order), done: 'Order saved');
    if (saved && mounted) setState(() => _order = null);
  }

  Future<String?> _askName(String title, {String initial = ''}) => showDialog<String>(
        context: context,
        builder: (_) => _NameDialog(title: title, initial: initial),
      );

  Future<void> _newPlaylist() async {
    final name = await _askName('New playlist');
    if (name == null || !mounted) return;
    await _change((service) async => (await service.createPlaylist(name)).catalog, done: 'Playlist made');
  }

  /// Asks which playlist, then adds [songs] to it (or to a new one). True once they are in it.
  Future<bool> _addToPlaylist(List<CloudSong> songs) async {
    final catalog = _catalog;
    if (catalog == null || songs.isEmpty) return false;
    final choice = await showModalBottomSheet<({CloudPlaylist? playlist})>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              key: const Key('cloud-pl-new'),
              leading: const Icon(Icons.add_rounded),
              title: const Text('New playlist'),
              onTap: () => Navigator.pop(ctx, (playlist: null)),
            ),
            for (final p in catalog.playlists)
              ListTile(
                key: ValueKey('cloud-pl-pick-${p.id}'),
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(_count(catalog.songsOfPlaylist(p).length, 'song')),
                onTap: () => Navigator.pop(ctx, (playlist: p)),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return false;
    final ids = [for (final s in songs) s.id];
    final p = choice.playlist;
    if (p == null) {
      final name = await _askName('New playlist');
      if (name == null || !mounted) return false;
      return _change((service) async => (await service.createPlaylist(name, ids)).catalog, done: 'Added to "${name.trim()}"');
    }
    final already = ids.every(p.songIds.contains);
    return _change(
      (service) => service.addToPlaylist(p.id, ids),
      done: already ? 'Already in "${p.name}"' : 'Added to "${p.name}"',
    );
  }

  Future<void> _renamePlaylist(CloudPlaylist p) async {
    final name = await _askName('Rename playlist', initial: p.name);
    if (name == null || !mounted) return;
    await _change((service) => service.renamePlaylist(p.id, name));
  }

  Future<void> _deletePlaylist(CloudPlaylist p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete the playlist "${p.name}"?'),
        content: const Text('The songs stay in the cloud.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(key: const Key('cloud-pl-delete-confirm'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final gone = await _change((service) => service.deletePlaylist(p.id), done: 'Playlist deleted');
    if (gone && mounted) _show();
  }

  // -------------------------------------------------------------------- build

  static String _size(int bytes) {
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  static String _count(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

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
    // The phone's Back button closes an artist, album or playlist page first.
    return PopScope(
      canPop: _page == null && _selected == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && mounted) _back();
      },
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    catalog == null
                        ? 'Your cloud songs'
                        : '${_count(catalog.songs.length, 'song')}'
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
                if (widget.onUpload != null && config.canWrite)
                  IconButton(
                    key: const Key('cloud-upload'),
                    tooltip: 'Upload songs to the cloud',
                    icon: const Icon(Icons.cloud_upload_outlined),
                    onPressed: () async {
                      await widget.onUpload!();
                      if (mounted) await _refresh();
                    },
                  ),
                if (widget.onOpenSettings != null)
                  IconButton(tooltip: 'Cloud Library settings', icon: const Icon(Icons.settings_outlined), onPressed: widget.onOpenSettings),
              ],
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: _body(theme, muted, config, catalog)),
        ],
      ),
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

  Widget _message(String text, TextStyle? style) => Center(
        child: Padding(padding: const EdgeInsets.all(24), child: Text(text, textAlign: TextAlign.center, style: style)),
      );

  Widget _body(ThemeData theme, TextStyle? muted, CloudConfig config, CloudCatalog? catalog) {
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
      return _message(
        widget.onUpload != null
            ? 'Nothing is in the cloud yet. Tap the upload button above to put songs up.'
            : 'Nothing is in the cloud yet. In your Library, long-press songs to select them, then tap Upload to cloud.',
        muted,
      );
    }
    final page = _page;
    if (page != null) return _pageView(theme, muted, config, catalog, page);
    return Column(
      children: [
        SizedBox(
          height: 52,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                for (final t in _Tab.values) ...[
                  if (t != _Tab.songs) const SizedBox(width: 6),
                  ChoiceChip(
                    key: ValueKey('cloud-tab-${t.name}'),
                    // No tick and tight spacing, so all four fit across a phone.
                    showCheckmark: false,
                    visualDensity: VisualDensity.compact,
                    label: Text(switch (t) {
                      _Tab.songs => 'Songs',
                      _Tab.artists => 'Artists',
                      _Tab.albums => 'Albums',
                      _Tab.playlists => 'Playlists',
                    }),
                    selected: _tab == t,
                    onSelected: (_) => _show(tab: t),
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: switch (_tab) {
            _Tab.songs => _songsTab(theme, muted, config, catalog),
            _Tab.artists => _artistsTab(muted, catalog),
            _Tab.albums => _albumsTab(muted, config, catalog),
            _Tab.playlists => _playlistsTab(muted, config, catalog),
          },
        ),
      ],
    );
  }

  // ------------------------------------------------------------------- songs

  Widget _songsTab(ThemeData theme, TextStyle? muted, CloudConfig config, CloudCatalog catalog) {
    final genres = catalog.genres;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
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
        Expanded(
          child: _songList(
            theme,
            muted,
            config,
            sortCloudSongs(catalog.search(_query, genre: _genre), _sort, _recent),
            sortable: true,
            emptyText: _sort == CloudSort.recent && _query.isEmpty && _genre == null
                ? 'Nothing yet. Songs you start from this screen show up here.'
                : 'No songs match.',
          ),
        ),
      ],
    );
  }

  /// The buttons and the rows for [songs]. With a [playlist], rows can be taken out of it and reordered.
  /// [sortable]: the sort button is offered.
  Widget _songList(ThemeData theme, TextStyle? muted, CloudConfig config, List<CloudSong> songs,
      {required String emptyText, CloudPlaylist? playlist, bool sortable = false}) {
    final rows = songs.take(CloudLibraryView.maxRows).toList();
    final selected = _selected;
    return Column(
      children: [
        if (selected != null)
          _selectionBar(theme, config, songs, selected, playlist)
        else if (songs.isNotEmpty || sortable)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (songs.isNotEmpty) ...[
                    TextButton.icon(
                      key: const Key('cloud-play-all'),
                      onPressed: widget.enabled ? () => _playAll(songs.take(200).toList()) : null,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text('Play all (${songs.length > 200 ? '200' : songs.length})'),
                    ),
                    TextButton.icon(
                      key: const Key('cloud-queue-all'),
                      onPressed: widget.enabled ? () => _queueAll(songs.take(200).toList()) : null,
                      icon: const Icon(Icons.queue_music_rounded),
                      label: const Text('Add all'),
                    ),
                    if (config.canWrite && playlist == null)
                      TextButton.icon(
                        key: const Key('cloud-all-to-playlist'),
                        onPressed: () => _addToPlaylist(songs),
                        icon: const Icon(Icons.playlist_add_rounded),
                        label: const Text('To a playlist'),
                      ),
                    TextButton.icon(
                      key: const Key('cloud-select'),
                      onPressed: () => setState(() => _selected = {}),
                      icon: const Icon(Icons.checklist_rounded),
                      label: const Text('Select'),
                    ),
                    if (config.canWrite && playlist != null && songs.length > 1)
                      TextButton.icon(
                        key: const Key('cloud-reorder'),
                        onPressed: () => setState(() => _order = [for (final s in songs) s.id]),
                        icon: const Icon(Icons.swap_vert_rounded),
                        label: const Text('Reorder'),
                      ),
                  ],
                  if (sortable)
                    PopupMenuButton<CloudSort>(
                      key: const Key('cloud-sort'),
                      tooltip: 'Sort',
                      initialValue: _sort,
                      onSelected: (v) {
                        setState(() => _sort = v);
                        ref.read(cloudHistoryStoreProvider).saveSort(v);
                      },
                      itemBuilder: (_) => [
                        for (final v in CloudSort.values) PopupMenuItem(value: v, child: Text(v.label)),
                      ],
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sort_rounded, size: 18, color: theme.colorScheme.primary),
                            const SizedBox(width: 8),
                            Text(_sort.label, style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        Expanded(
          child: songs.isEmpty
              ? _message(emptyText, muted)
              : ListView.builder(
                  itemCount: rows.length + (songs.length > rows.length ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= rows.length) {
                      return Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text('Showing the first ${rows.length} of ${songs.length}. Search to narrow it down.',
                            textAlign: TextAlign.center, style: muted),
                      );
                    }
                    return _row(theme, config, rows[i], playlist: playlist);
                  },
                ),
        ),
      ],
    );
  }

  /// What can be done with the picked songs. They keep the order of the list.
  Widget _selectionBar(
      ThemeData theme, CloudConfig config, List<CloudSong> songs, Set<String> selected, CloudPlaylist? playlist) {
    final picked = [for (final s in songs) if (selected.contains(s.id)) s];
    final any = picked.isNotEmpty;
    void leave() => setState(() => _selected = null);
    Widget action(String key, IconData icon, String label, VoidCallback? onPressed) =>
        TextButton.icon(key: Key(key), onPressed: onPressed, icon: Icon(icon), label: Text(label));
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Column(
        children: [
          Row(
            children: [
              IconButton(key: const Key('cloud-select-done'), tooltip: 'Stop selecting', icon: const Icon(Icons.close_rounded), onPressed: leave),
              Expanded(child: Text('${picked.length} selected', key: const Key('cloud-select-count'), style: theme.textTheme.titleSmall)),
              TextButton(
                key: const Key('cloud-select-all'),
                onPressed: () => setState(() => _selected = picked.length == songs.length ? {} : {for (final s in songs) s.id}),
                child: Text(songs.isNotEmpty && picked.length == songs.length ? 'Select none' : 'Select all'),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Wrap(
                children: [
                  action('cloud-sel-play', Icons.play_arrow_rounded, 'Play', any && widget.enabled
                      ? () {
                          leave();
                          _playAll(picked.take(200).toList());
                        }
                      : null),
                  action('cloud-sel-queue', Icons.queue_music_rounded, 'Queue', any && widget.enabled
                      ? () {
                          leave();
                          _queueAll(picked.take(200).toList());
                        }
                      : null),
                  if (config.canWrite) ...[
                    action('cloud-sel-playlist', Icons.playlist_add_rounded, 'To a playlist', any
                        ? () async {
                            if (await _addToPlaylist(picked) && mounted) leave();
                          }
                        : null),
                    action('cloud-sel-edit', Icons.edit_rounded, 'Edit info', any ? () => _editSeveral(picked) : null),
                    if (playlist != null)
                      action('cloud-sel-unlist', Icons.playlist_remove_rounded, 'Remove', any
                          ? () async {
                              final done = await _change(
                                (service) => service.removeFromPlaylist(playlist.id, [for (final s in picked) s.id]),
                                done: 'Taken out of "${playlist.name}"',
                              );
                              if (done && mounted) leave();
                            }
                          : null),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// A playlist's songs with handles to drag them into a new order.
  Widget _reorderList(ThemeData theme, CloudConfig config, CloudCatalog catalog, CloudPlaylist playlist, List<String> order) {
    final songs = [
      for (final id in order)
        if (catalog.songById(id) case final s?) s,
    ];
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 8, 0),
          child: Row(
            children: [
              Expanded(child: Text('Drag the songs into order', style: theme.textTheme.bodySmall)),
              TextButton(key: const Key('cloud-order-cancel'), onPressed: () => setState(() => _order = null), child: const Text('Cancel')),
              FilledButton(key: const Key('cloud-order-save'), onPressed: () => _saveOrder(playlist), child: const Text('Save')),
            ],
          ),
        ),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            itemCount: songs.length,
            onReorder: (from, to) => setState(() {
              final ids = [for (final s in songs) s.id];
              final moved = ids.removeAt(from);
              ids.insert(to > from ? to - 1 : to, moved);
              _order = ids;
            }),
            itemBuilder: (context, i) {
              final s = songs[i];
              return ListTile(
                key: ValueKey('cloud-order-${s.id}'),
                minTileHeight: 64,
                leading: _cover(config, s.artKey),
                title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: s.artist.isEmpty ? null : Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
                trailing: ReorderableDragStartListener(
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Icon(Icons.drag_handle_rounded, key: ValueKey('cloud-drag-${s.id}')),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _cover(CloudConfig config, String? artKey) {
    Widget plain() => DefaultArt.albumAvatar(radius: 22);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 44,
        height: 44,
        child: artKey == null
            ? plain()
            : Image.network(
                config.urlFor(artKey),
                fit: BoxFit.cover,
                cacheWidth: 132,
                // The default picture shows while the cover loads (and if it cannot), so nothing flashes blank.
                loadingBuilder: (context, child, progress) => progress == null ? child : plain(),
                errorBuilder: (_, __, ___) => plain(),
              ),
      ),
    );
  }

  Widget _row(ThemeData theme, CloudConfig config, CloudSong s, {CloudPlaylist? playlist}) {
    final selected = _selected;
    if (selected != null) {
      final on = selected.contains(s.id);
      return ListTile(
        key: ValueKey('cloud-song-${s.id}'),
        minTileHeight: 64,
        selected: on,
        selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.12),
        leading: _cover(config, s.artKey),
        title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text([if (s.artist.isNotEmpty) s.artist, if (s.album.isNotEmpty) s.album].join(' · '),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: Icon(on ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
            color: on ? theme.colorScheme.primary : null),
        onTap: () => setState(() => _selected = on ? ({...selected}..remove(s.id)) : {...selected, s.id}),
      );
    }
    final canCover = ref.read(cloudCoverPickerProvider) != null;
    return ListTile(
      key: ValueKey('cloud-song-${s.id}'),
      minTileHeight: 64,
      leading: _cover(config, s.artKey),
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
            onSelected: (a) {
              switch (a) {
                case 'play':
                  _act(s, queue: false);
                case 'queue':
                  _act(s, queue: true);
                case 'playlist':
                  _addToPlaylist([s]);
                case 'unlist':
                  final from = playlist!;
                  _change((service) => service.removeFromPlaylist(from.id, [s.id]), done: 'Taken out of "${from.name}"');
                case 'edit':
                  _editInfo(s);
                case 'cover':
                  _changeCover(s);
                case 'delete':
                  _delete(s);
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(value: 'play', child: Text('Play')),
              const PopupMenuItem(value: 'queue', child: Text('Add to queue')),
              if (config.canWrite) ...[
                const PopupMenuItem(value: 'playlist', child: Text('Add to playlist')),
                if (playlist != null) const PopupMenuItem(value: 'unlist', child: Text('Remove from this playlist')),
                const PopupMenuItem(value: 'edit', child: Text('Edit info')),
                if (canCover) const PopupMenuItem(value: 'cover', child: Text('Change cover')),
                const PopupMenuItem(value: 'delete', child: Text('Delete from the cloud')),
              ],
            ],
          ),
        ],
      ),
      onTap: widget.enabled ? () => _act(s, queue: false) : null,
      onLongPress: widget.enabled ? () => _act(s, queue: true) : null,
    );
  }

  // --------------------------------------------------------- artists, albums

  Widget _artistsTab(TextStyle? muted, CloudCatalog catalog) {
    final artists = catalog.artists;
    if (artists.isEmpty) return _message('No artists yet. Songs with an artist are listed here.', muted);
    return ListView.builder(
      itemCount: artists.length,
      itemBuilder: (context, i) {
        final a = artists[i];
        return ListTile(
          key: ValueKey('cloud-artist-${a.name}'),
          minTileHeight: 60,
          leading: DefaultArt.artistAvatar(radius: 22),
          title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text([_count(a.songs, 'song'), if (a.albums > 0) _count(a.albums, 'album')].join(' · ')),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _show(page: _Page(_PageKind.artist, a.name, a.name)),
        );
      },
    );
  }

  Widget _albumsTab(TextStyle? muted, CloudConfig config, CloudCatalog catalog) {
    final albums = catalog.albums;
    if (albums.isEmpty) return _message('No albums yet. Songs with an album are listed here.', muted);
    return ListView.builder(
      itemCount: albums.length,
      itemBuilder: (context, i) {
        final a = albums[i];
        return ListTile(
          key: ValueKey('cloud-album-${a.key}'),
          minTileHeight: 64,
          leading: _cover(config, a.artKey),
          title: Text(a.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            [if (a.artist.isNotEmpty) a.artist, if (a.year != null) '${a.year}', _count(a.songs, 'song')].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _show(page: _Page(_PageKind.album, a.key, a.title)),
        );
      },
    );
  }

  // --------------------------------------------------------------- playlists

  Widget _playlistsTab(TextStyle? muted, CloudConfig config, CloudCatalog catalog) {
    return Column(
      children: [
        if (config.canWrite)
          Align(
            alignment: Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextButton.icon(
                key: const Key('cloud-new-playlist'),
                onPressed: _newPlaylist,
                icon: const Icon(Icons.add_rounded),
                label: const Text('New playlist'),
              ),
            ),
          ),
        Expanded(
          child: catalog.playlists.isEmpty
              ? _message(
                  config.canWrite
                      ? 'No playlists yet. Make one here, or open a song\'s menu and tap Add to playlist.'
                      : 'No playlists yet. They are made on a device that has the R2 keys.',
                  muted,
                )
              : ListView.builder(
                  itemCount: catalog.playlists.length,
                  itemBuilder: (context, i) {
                    final p = catalog.playlists[i];
                    return ListTile(
                      key: ValueKey('cloud-playlist-${p.id}'),
                      minTileHeight: 60,
                      leading: const CircleAvatar(radius: 22, child: Icon(Icons.queue_music_rounded)),
                      title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(_count(catalog.songsOfPlaylist(p).length, 'song')),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _show(page: _Page(_PageKind.playlist, p.id, p.name)),
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ------------------------------------------------------------------- pages

  Widget _pageView(ThemeData theme, TextStyle? muted, CloudConfig config, CloudCatalog catalog, _Page page) {
    var songs = const <CloudSong>[];
    var title = page.title;
    CloudPlaylist? playlist;
    switch (page.kind) {
      case _PageKind.artist:
        songs = catalog.songsOfArtist(page.key);
      case _PageKind.album:
        final album = catalog.albums.where((a) => a.key == page.key).firstOrNull;
        if (album != null) songs = catalog.songsOfAlbum(album);
      case _PageKind.playlist:
        playlist = catalog.playlists.where((p) => p.id == page.key).firstOrNull;
        if (playlist != null) {
          songs = catalog.songsOfPlaylist(playlist);
          title = playlist.name;
        }
    }
    final list = playlist;
    final order = _order;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            children: [
              IconButton(
                key: const Key('cloud-back'),
                tooltip: 'Back',
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => _show(),
              ),
              Expanded(
                child: Text(title,
                    key: const Key('cloud-page-title'), style: theme.textTheme.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (list != null && config.canWrite)
                PopupMenuButton<String>(
                  key: const Key('cloud-playlist-menu'),
                  tooltip: 'Playlist options',
                  onSelected: (a) => a == 'rename' ? _renamePlaylist(list) : _deletePlaylist(list),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'rename', child: Text('Rename')),
                    PopupMenuItem(value: 'delete', child: Text('Delete playlist')),
                  ],
                ),
            ],
          ),
        ),
        Expanded(
          child: list != null && order != null
              ? _reorderList(theme, config, catalog, list, order)
              : _songList(
                  theme,
                  muted,
                  config,
                  songs,
                  playlist: list,
                  emptyText: page.kind == _PageKind.playlist
                      ? 'This playlist is empty. Open a song\'s menu and tap Add to playlist.'
                      : 'No songs here any more.',
                ),
        ),
      ],
    );
  }
}

/// Asks for a playlist name (it owns its text field, so the field is let go only when the dialog is gone).
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, this.initial = ''});

  final String title;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _field = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _save() {
    if (_field.text.trim().isNotEmpty) Navigator.pop(context, _field.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          key: const Key('cloud-name-field'),
          controller: _field,
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Playlist name'),
          onSubmitted: (_) => _save(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(key: const Key('cloud-name-save'), onPressed: _save, child: const Text('Save')),
        ],
      );
}

/// Edits a cloud song's title, artist, album, genre, year and track.
class _EditSongDialog extends StatefulWidget {
  const _EditSongDialog({required this.song});

  final CloudSong song;

  @override
  State<_EditSongDialog> createState() => _EditSongDialogState();
}

class _EditSongDialogState extends State<_EditSongDialog> {
  late final _title = TextEditingController(text: widget.song.title);
  late final _artist = TextEditingController(text: widget.song.artist);
  late final _album = TextEditingController(text: widget.song.album);
  late final _genre = TextEditingController(text: widget.song.genre);
  late final _year = TextEditingController(text: widget.song.year?.toString() ?? '');
  late final _track = TextEditingController(text: widget.song.track?.toString() ?? '');
  String? _problem;

  @override
  void dispose() {
    for (final c in [_title, _artist, _album, _genre, _year, _track]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    final title = _title.text.trim();
    final yearText = _year.text.trim();
    final trackText = _track.text.trim();
    final year = int.tryParse(yearText);
    final track = int.tryParse(trackText);
    String? problem;
    if (title.isEmpty) {
      problem = 'A song needs a title.';
    } else if (yearText.isNotEmpty && (year == null || year < 1000 || year > 2999)) {
      problem = 'The year is four digits, like 1999.';
    } else if (trackText.isNotEmpty && (track == null || track < 1 || track > 999)) {
      problem = 'The track is a number from 1 to 999.';
    }
    if (problem != null) {
      setState(() => _problem = problem);
      return;
    }
    Navigator.pop(
      context,
      widget.song.copyWith(
        title: title,
        artist: _artist.text.trim(),
        album: _album.text.trim(),
        genre: _genre.text.trim(),
        year: year,
        track: track,
        clearYear: yearText.isEmpty,
        clearTrack: trackText.isEmpty,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    Widget field(String key, String label, TextEditingController c, {TextInputType? type}) => TextField(
          key: Key(key),
          controller: c,
          keyboardType: type,
          decoration: InputDecoration(labelText: label, isDense: true),
        );
    return AlertDialog(
      title: const Text('Edit info'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              field('cloud-edit-title', 'Title', _title),
              field('cloud-edit-artist', 'Artist', _artist),
              field('cloud-edit-album', 'Album', _album),
              field('cloud-edit-genre', 'Genre', _genre),
              Row(
                children: [
                  Expanded(child: field('cloud-edit-year', 'Year', _year, type: TextInputType.number)),
                  const SizedBox(width: 12),
                  Expanded(child: field('cloud-edit-track', 'Track', _track, type: TextInputType.number)),
                ],
              ),
              if (_problem != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(_problem!, key: const Key('cloud-edit-problem'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(key: const Key('cloud-edit-save'), onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// The details given to several songs at once (null: leave as it is).
typedef _Shared = ({String? artist, String? album, String? genre, int? year});

/// Edits what several songs can share. Only what is typed is changed.
class _EditSeveralDialog extends StatefulWidget {
  const _EditSeveralDialog({required this.count});

  final int count;

  @override
  State<_EditSeveralDialog> createState() => _EditSeveralDialogState();
}

class _EditSeveralDialogState extends State<_EditSeveralDialog> {
  final _artist = TextEditingController();
  final _album = TextEditingController();
  final _genre = TextEditingController();
  final _year = TextEditingController();
  String? _problem;

  @override
  void dispose() {
    for (final c in [_artist, _album, _genre, _year]) {
      c.dispose();
    }
    super.dispose();
  }

  void _save() {
    String? typed(TextEditingController c) => c.text.trim().isEmpty ? null : c.text.trim();
    final yearText = typed(_year);
    final year = yearText == null ? null : int.tryParse(yearText);
    if (yearText != null && (year == null || year < 1000 || year > 2999)) {
      setState(() => _problem = 'The year is four digits, like 1999.');
      return;
    }
    final changes = (artist: typed(_artist), album: typed(_album), genre: typed(_genre), year: year);
    if (changes.artist == null && changes.album == null && changes.genre == null && year == null) {
      setState(() => _problem = 'Type something to change.');
      return;
    }
    Navigator.pop(context, changes);
  }

  @override
  Widget build(BuildContext context) {
    Widget field(String key, String label, TextEditingController c, {TextInputType? type}) => TextField(
          key: Key(key),
          controller: c,
          keyboardType: type,
          decoration: InputDecoration(labelText: label, hintText: 'Unchanged', floatingLabelBehavior: FloatingLabelBehavior.always, isDense: true),
        );
    return AlertDialog(
      title: Text('Edit ${widget.count} song${widget.count == 1 ? '' : 's'}'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 8,
            children: [
              const Text('Only what you type is changed.'),
              field('cloud-many-artist', 'Artist', _artist),
              field('cloud-many-album', 'Album', _album),
              field('cloud-many-genre', 'Genre', _genre),
              field('cloud-many-year', 'Year', _year, type: TextInputType.number),
              if (_problem != null)
                Text(_problem!, key: const Key('cloud-many-problem'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(key: const Key('cloud-many-save'), onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

/// Shows the picked picture and asks who gets it: the whole album, or only the song. Gives their ids.
class _CoverDialog extends StatefulWidget {
  const _CoverDialog({required this.bytes, required this.song, required this.albumIds});

  final Uint8List bytes;
  final CloudSong song;
  final List<String> albumIds;

  @override
  State<_CoverDialog> createState() => _CoverDialogState();
}

class _CoverDialogState extends State<_CoverDialog> {
  late bool _wholeAlbum = widget.albumIds.length > 1;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Use this cover?'),
        content: SizedBox(
          width: 320,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 180,
                  height: 180,
                  child: Image.memory(widget.bytes, fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined)),
                ),
                if (widget.albumIds.length > 1)
                  CheckboxListTile(
                    key: const Key('cloud-cover-album'),
                    contentPadding: EdgeInsets.zero,
                    value: _wholeAlbum,
                    onChanged: (v) => setState(() => _wholeAlbum = v ?? false),
                    title: Text('All ${widget.albumIds.length} songs of "${widget.song.album}"'),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            key: const Key('cloud-cover-save'),
            onPressed: () => Navigator.pop(context, _wholeAlbum ? widget.albumIds : [widget.song.id]),
            child: const Text('Use it'),
          ),
        ],
      );
}
