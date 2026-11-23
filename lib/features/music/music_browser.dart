import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/protocol/library_models.dart';
import '../../core/widgets/playback_widgets.dart';
import 'music_source.dart';

enum _Scope { songs, artists, albums }

class _Drill {
  const _Drill({required this.title, this.artist, this.album});

  final String title;
  final String? artist;
  final String? album;
}

/// Library browser used on both phones: search, Songs/Artists/Albums filter
/// chips, lazily loaded lists, and drill-down into an artist or album.
class MusicBrowser extends StatefulWidget {
  const MusicBrowser({
    super.key,
    required this.source,
    this.enabled = true,
    this.refreshToken = 0,
    this.onRemoveSong,
    this.emptyMessage = 'No songs yet.',
  });

  final MusicSource source;

  /// False disables interaction (e.g. while the Controller is reconnecting).
  final bool enabled;

  /// Change this value to reload the lists (e.g. after an import).
  final int refreshToken;

  /// Player only: shows "Remove from library" in the song menu.
  final Future<void> Function(RemoteSong song)? onRemoveSong;
  final String emptyMessage;

  @override
  State<MusicBrowser> createState() => _MusicBrowserState();
}

class _MusicBrowserState extends State<MusicBrowser> {
  _Scope _scope = _Scope.songs;
  _Drill? _drill;
  String _query = '';
  int _generation = 0;
  Timer? _debounce;
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    super.dispose();
  }

  void _onQueryChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted && text.trim() != _query) setState(() => _query = text.trim());
    });
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action, {String? done}) async {
    try {
      await action();
      if (done != null) _snack(done);
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  /// Every song id for the current artist/album (bounded by the Player's
  /// per-command limit).
  Future<List<int>> _allSongIds(_Drill d) async {
    final ids = <int>[];
    var offset = 0;
    while (ids.length < 2000) {
      final page = await widget.source
          .songs(query: _query, artist: d.artist, album: d.album, offset: offset, limit: 100);
      ids.addAll([for (final s in page.items) s.id]);
      offset += page.items.length;
      if (!page.hasMore || page.items.isEmpty) break;
    }
    return ids;
  }

  @override
  Widget build(BuildContext context) {
    final drill = _drill;
    final key = ValueKey('$_scope|$_query|${drill?.artist}|${drill?.album}|'
        '${widget.refreshToken}|$_generation');

    return IgnorePointer(
      ignoring: !widget.enabled,
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.5,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: TextField(
                controller: _search,
                onChanged: _onQueryChanged,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: drill == null ? 'Search your music' : 'Search in ${drill.title}',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'Clear search',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () {
                            _search.clear();
                            setState(() => _query = '');
                          },
                        ),
                ),
              ),
            ),
            if (drill == null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    for (final s in _Scope.values) ...[
                      ChoiceChip(
                        label: Text(switch (s) {
                          _Scope.songs => 'Songs',
                          _Scope.artists => 'Artists',
                          _Scope.albums => 'Albums',
                        }),
                        selected: _scope == s,
                        onSelected: (_) => setState(() => _scope = s),
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              )
            else
              _DrillHeader(
                title: drill.title,
                onBack: () => setState(() => _drill = null),
                onPlayAll: () => _run(() async {
                  final ids = await _allSongIds(drill);
                  if (ids.isEmpty) return;
                  await widget.source.playSongs(ids);
                }),
                onQueueAll: () => _run(() async {
                  final ids = await _allSongIds(drill);
                  if (ids.isEmpty) return;
                  await widget.source.queueSongs(ids);
                }, done: 'Added to queue'),
              ),
            Expanded(
              child: switch (drill != null ? _Scope.songs : _scope) {
                _Scope.songs => _PagedList<RemoteSong>(
                    key: key,
                    emptyMessage: _query.isEmpty ? widget.emptyMessage : 'No matches.',
                    load: (offset, limit) => widget.source.songs(
                      query: _query,
                      artist: drill?.artist,
                      album: drill?.album,
                      offset: offset,
                      limit: limit,
                    ),
                    itemBuilder: (context, song) => _SongTile(
                      song: song,
                      onTap: () => _run(() async {
                        if (!song.available) {
                          _snack("This song's file is missing from the Player.");
                          return;
                        }
                        if (drill != null) {
                          // Play the whole album/artist starting here.
                          await widget.source
                              .playSongs(await _allSongIds(drill), startSongId: song.id);
                        } else {
                          await widget.source.playSongs([song.id]);
                        }
                      }),
                      onPlayNext: () => _run(
                        () => widget.source.queueSongs([song.id], playNext: true),
                        done: 'Will play next',
                      ),
                      onAddToQueue: () => _run(
                        () => widget.source.queueSongs([song.id]),
                        done: 'Added to queue',
                      ),
                      onRemove: widget.onRemoveSong == null
                          ? null
                          : () => _run(() async {
                                await widget.onRemoveSong!(song);
                                if (mounted) setState(() => _generation++);
                              }, done: 'Removed from library'),
                    ),
                  ),
                _Scope.artists => _PagedList<RemoteArtist>(
                    key: key,
                    emptyMessage: _query.isEmpty ? widget.emptyMessage : 'No matches.',
                    load: (offset, limit) => widget.source
                        .artists(query: _query, offset: offset, limit: limit),
                    itemBuilder: (context, a) => ListTile(
                      minTileHeight: 64,
                      leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
                      title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${a.songCount} song${a.songCount == 1 ? '' : 's'} · '
                          '${a.albumCount} album${a.albumCount == 1 ? '' : 's'}'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => setState(() {
                        _search.clear();
                        _query = '';
                        _drill = _Drill(title: a.name, artist: a.name);
                      }),
                    ),
                  ),
                _Scope.albums => _PagedList<RemoteAlbum>(
                    key: key,
                    emptyMessage: _query.isEmpty ? widget.emptyMessage : 'No matches.',
                    load: (offset, limit) => widget.source
                        .albums(query: _query, offset: offset, limit: limit),
                    itemBuilder: (context, a) => ListTile(
                      minTileHeight: 64,
                      leading: const CircleAvatar(child: Icon(Icons.album_rounded)),
                      title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${a.artist} · ${a.songCount} song${a.songCount == 1 ? '' : 's'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => setState(() {
                        _search.clear();
                        _query = '';
                        _drill = _Drill(title: a.name, artist: a.artist, album: a.name);
                      }),
                    ),
                  ),
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _DrillHeader extends StatelessWidget {
  const _DrillHeader({
    required this.title,
    required this.onBack,
    required this.onPlayAll,
    required this.onQueueAll,
  });

  final String title;
  final VoidCallback onBack;
  final VoidCallback onPlayAll;
  final VoidCallback onQueueAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: onBack,
          ),
          Expanded(
            child: Text(title,
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          TextButton.icon(
            onPressed: onPlayAll,
            icon: const Icon(Icons.play_arrow_rounded),
            label: const Text('Play all'),
          ),
          IconButton(
            tooltip: 'Add all to queue',
            icon: const Icon(Icons.queue_music_rounded),
            onPressed: onQueueAll,
          ),
        ],
      ),
    );
  }
}

enum _SongAction { playNext, addToQueue, remove }

class _SongTile extends StatelessWidget {
  const _SongTile({
    required this.song,
    required this.onTap,
    required this.onPlayNext,
    required this.onAddToQueue,
    this.onRemove,
  });

  final RemoteSong song;
  final VoidCallback onTap;
  final VoidCallback onPlayNext;
  final VoidCallback onAddToQueue;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = !song.available;
    final subtitle = dim
        ? 'File missing from the Player'
        : '${song.artist} · ${song.album}';

    return ListTile(
      minTileHeight: 64,
      enabled: true,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        child: Icon(
          dim ? Icons.error_outline_rounded : Icons.music_note_rounded,
          color: dim ? theme.colorScheme.error : theme.colorScheme.primary,
        ),
      ),
      title: Text(song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: dim
              ? TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.5))
              : null),
      subtitle: Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (song.durationSeconds > 0)
            Text(formatDuration(song.durationSeconds),
                style: theme.textTheme.bodySmall),
          PopupMenuButton<_SongAction>(
            tooltip: 'More',
            onSelected: (a) => switch (a) {
              _SongAction.playNext => onPlayNext(),
              _SongAction.addToQueue => onAddToQueue(),
              _SongAction.remove => onRemove?.call(),
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                  value: _SongAction.playNext, child: Text('Play next')),
              const PopupMenuItem(
                  value: _SongAction.addToQueue, child: Text('Add to queue')),
              if (onRemove != null)
                const PopupMenuItem(
                    value: _SongAction.remove, child: Text('Remove from library')),
            ],
          ),
        ],
      ),
      onTap: onTap,
    );
  }
}

/// A lazily loaded, paged list. Recreate it (change its key) to reload.
class _PagedList<T> extends StatefulWidget {
  const _PagedList({
    super.key,
    required this.load,
    required this.itemBuilder,
    required this.emptyMessage,
  });

  final Future<LibraryPage<T>> Function(int offset, int limit) load;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final String emptyMessage;

  @override
  State<_PagedList<T>> createState() => _PagedListState<T>();
}

class _PagedListState<T> extends State<_PagedList<T>> {
  static const _pageSize = 50;

  final List<T> _items = [];
  final ScrollController _scroll = ScrollController();
  int _total = 0;
  bool _loading = false;
  bool _initialDone = false;
  Object? _error;

  bool get _hasMore => !_initialDone || _items.length < _total;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.hasClients && _scroll.position.extentAfter < 400) _loadMore();
    });
    _loadMore();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore || _error != null && _initialDone) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final page = await widget.load(_items.length, _pageSize);
      if (!mounted) return;
      setState(() {
        _items.addAll(page.items);
        _total = page.total;
        _initialDone = true;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // A failed *first* page must stay "not loaded" so Try again can retry.
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  void _retry() {
    setState(() => _error = null);
    _loadMore();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (!_initialDone && _loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _error != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(friendlyError(_error!), textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: _retry, child: const Text('Try again')),
                  ],
                )
              : Text(
                  widget.emptyMessage,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
        ),
      );
    }
    final footer = _loading || _error != null || _items.length < _total;
    return ListView.builder(
      controller: _scroll,
      itemCount: _items.length + (footer ? 1 : 0),
      itemBuilder: (context, i) {
        if (i < _items.length) return widget.itemBuilder(context, _items[i]);
        if (_error != null) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: OutlinedButton(
                  onPressed: _retry, child: const Text('Try again')),
            ),
          );
        }
        return const Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        );
      },
    );
  }
}
