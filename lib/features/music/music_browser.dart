import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../core/protocol/library_models.dart';
import '../../core/song_list_style.dart';
import '../../core/widgets/playback_widgets.dart';
import 'music_source.dart';
import 'song_art.dart';

enum _Scope { songs, artists, albums, favorites, recent, playlists, top, newest, folders }

class _Drill {
  const _Drill(
      {required this.title, this.artist, this.album, this.playlistId, this.folderId});

  final String title;
  final String? artist;
  final String? album;
  final int? playlistId;
  final int? folderId;
}

/// Library browser used on both phones: search, filter chips (Songs, Artists,
/// Albums, Favorites, Recent, Playlists), lazily loaded lists, and drill-down
/// into an artist, album or playlist.
class MusicBrowser extends StatefulWidget {
  const MusicBrowser({
    super.key,
    required this.source,
    this.enabled = true,
    this.refreshToken = 0,
    this.onRemoveSong,
    this.emptyMessage = 'No songs yet.',
    this.size = SongListSize.small,
  });

  /// Text size of the song rows.
  final SongListSize size;

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

  /// Songs picked for a bulk action (long-press a song to start).
  final Set<int> _selected = {};
  String _selectionContext = '';
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
      final page = await widget.source.songs(
          query: _query,
          artist: d.artist,
          album: d.album,
          playlistId: d.playlistId,
          folderId: d.folderId,
          offset: offset,
          limit: 100);
      ids.addAll([for (final s in page.items) s.id]);
      offset += page.items.length;
      if (!page.hasMore || page.items.isEmpty) break;
    }
    return ids;
  }

  /// Every song id in a whole view (Favorites or Recent), for Play all.
  Future<List<int>> _allViewIds(String view) async {
    final ids = <int>[];
    var offset = 0;
    while (ids.length < 2000) {
      final page = await widget.source
          .songs(query: _query, view: view, offset: offset, limit: 100);
      ids.addAll([for (final s in page.items) s.id]);
      offset += page.items.length;
      if (!page.hasMore || page.items.isEmpty) break;
    }
    return ids;
  }

  /// Ids of every song in what is on screen (for Select all).
  Future<List<int>> _idsOnScreen(_Drill? drill, String? view) async {
    final ids = <int>[];
    var offset = 0;
    while (ids.length < 2000) {
      final page = await widget.source.songs(
          query: _query,
          artist: drill?.artist,
          album: drill?.album,
          view: view,
          playlistId: drill?.playlistId,
          folderId: drill?.folderId,
          offset: offset,
          limit: 100);
      ids.addAll([for (final s in page.items) s.id]);
      offset += page.items.length;
      if (!page.hasMore || page.items.isEmpty) break;
    }
    return ids;
  }

  void _toggleSelected(int id) {
    Haptics.selection();
    setState(() {
      if (!_selected.remove(id)) _selected.add(id);
    });
  }

  Widget _selectionBar(_Drill? drill, String? view) {
    final n = _selected.length;
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Cancel selection',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(_selected.clear),
            ),
            Expanded(
              child: Text('$n selected',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              tooltip: 'Select all',
              icon: const Icon(Icons.select_all_rounded),
              onPressed: () => _run(() async {
                final ids = await _idsOnScreen(drill, view);
                if (mounted) setState(() => _selected.addAll(ids));
              }),
            ),
            IconButton(
              tooltip: 'Add selected to queue',
              icon: const Icon(Icons.queue_music_rounded),
              onPressed: () => _run(() async {
                await widget.source.queueSongs(_selected.toList());
                if (mounted) setState(_selected.clear);
              }, done: 'Added to queue'),
            ),
            IconButton(
              tooltip: 'Add selected to playlist',
              icon: const Icon(Icons.playlist_add_rounded),
              onPressed: () async {
                final ids = _selected.toList();
                if (await _addIdsToPlaylist(ids) && mounted) {
                  setState(_selected.clear);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<String?> _askName(String title, {String initial = ''}) {
    final c = TextEditingController(text: initial);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: c,
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Playlist name'),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(c.text),
              child: const Text('Save')),
        ],
      ),
    );
  }

  Future<void> _newPlaylist() async {
    final name = await _askName('New playlist');
    if (name == null) return;
    await _run(() async {
      await widget.source.createPlaylist(name);
      if (mounted) setState(() => _generation++);
    }, done: 'Playlist created');
  }

  /// Asks which playlist, then adds [ids]. True if songs were sent to a playlist.
  Future<bool> _addIdsToPlaylist(List<int> ids) async {
    final List<RemotePlaylist> lists;
    try {
      lists = (await widget.source.playlists(limit: 100)).items;
    } catch (e) {
      _snack(friendlyError(e));
      return false;
    }
    if (!mounted) return false;
    final choice = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.add_rounded),
              title: const Text('New playlist'),
              onTap: () => Navigator.of(ctx).pop('new'),
            ),
            for (final l in lists)
              ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(l.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text('${l.songCount} song${l.songCount == 1 ? '' : 's'}'),
                onTap: () => Navigator.of(ctx).pop(l),
              ),
          ],
        ),
      ),
    );
    if (choice == null || !mounted) return false;
    var ok = false;
    await _run(() async {
      int id;
      String name;
      if (choice == 'new') {
        final n = await _askName('New playlist');
        if (n == null) return;
        id = await widget.source.createPlaylist(n);
        name = n.trim();
      } else {
        final l = choice as RemotePlaylist;
        id = l.id;
        name = l.name;
      }
      final added = await widget.source.addToPlaylist(id, ids);
      ok = true;
      _snack(added == 0
          ? (ids.length == 1 ? 'Already in "$name"' : 'All of them are already in "$name"')
          : (ids.length == 1
              ? 'Added to "$name"'
              : 'Added $added song${added == 1 ? '' : 's'} to "$name"'));
    });
    return ok;
  }

  Future<void> _renamePlaylist(_Drill d) async {
    final name = await _askName('Rename playlist', initial: d.title);
    if (name == null) return;
    await _run(() async {
      await widget.source.renamePlaylist(d.playlistId!, name);
      if (mounted) {
        setState(() => _drill = _Drill(
            title: name.trim(), playlistId: d.playlistId));
      }
    });
  }

  Future<void> _deletePlaylist(_Drill d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${d.title}"?'),
        content: const Text('The songs stay in your library.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    await _run(() async {
      await widget.source.deletePlaylist(d.playlistId!);
      if (mounted) {
        setState(() {
          _drill = null;
          _generation++;
        });
      }
    }, done: 'Playlist deleted');
  }

  Widget _songList(_Drill? drill, {String? view}) {
    final key = ValueKey('$_scope|$_query|${drill?.artist}|${drill?.album}|'
        '${drill?.playlistId}|${drill?.folderId}|${widget.refreshToken}|$_generation');
    return _PagedList<RemoteSong>(
      key: key,
      emptyMessage: _query.isNotEmpty
          ? 'No matches.'
          : switch (view) {
              LibraryView.favorites => 'No favorites yet. Tap the heart on a song.',
              LibraryView.recent => 'Nothing played yet.',
              LibraryView.top => 'Nothing played yet. Your most played songs show up here.',
              LibraryView.newest => 'No songs yet.',
              _ => drill?.playlistId != null
                  ? 'This playlist is empty. Use a song\'s menu to add songs.'
                  : widget.emptyMessage,
            },
      load: (offset, limit) => widget.source.songs(
        query: _query,
        artist: drill?.artist,
        album: drill?.album,
        view: view,
        playlistId: drill?.playlistId,
        folderId: drill?.folderId,
        offset: offset,
        limit: limit,
      ),
      itemBuilder: (context, song) => _SongTile(
        song: song,
        source: widget.source,
        onTap: () => _selected.isNotEmpty
            ? _toggleSelected(song.id)
            : _run(() async {
          if (!song.available) {
            _snack("This song's file is missing from the Player.");
            return;
          }
          if (drill != null) {
            // Play the whole album/artist/playlist starting here.
            await widget.source
                .playSongs(await _allSongIds(drill), startSongId: song.id);
          } else if (view != null) {
            await widget.source
                .playSongs(await _allViewIds(view), startSongId: song.id);
          } else {
            // A single song: play it now but keep the queue.
            await widget.source.playSongs([song.id], keepQueue: true);
          }
        }),
        onFavorite: (fav) => widget.source.setFavorite(song.id, fav),
        onPlayNext: () => _run(
          () => widget.source.queueSongs([song.id], playNext: true),
          done: 'Will play next',
        ),
        onAddToQueue: () => _run(
          () => widget.source.queueSongs([song.id]),
          done: 'Added to queue',
        ),
        onAddToPlaylist: () => _addIdsToPlaylist([song.id]),
        size: widget.size,
        selecting: _selected.isNotEmpty,
        selected: _selected.contains(song.id),
        onSelect: () => _toggleSelected(song.id),
        onRemoveFromPlaylist: drill?.playlistId == null
            ? null
            : () => _run(() async {
                  await widget.source.removeFromPlaylist(drill!.playlistId!, song.id);
                  if (mounted) setState(() => _generation++);
                }, done: 'Removed from playlist'),
        onRemove: widget.onRemoveSong == null
            ? null
            : () => _run(() async {
                  await widget.onRemoveSong!(song);
                  if (mounted) setState(() => _generation++);
                }, done: 'Removed from library'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final drill = _drill;
    final key = ValueKey('$_scope|$_query|${drill?.artist}|${drill?.album}|'
        '${drill?.playlistId}|${widget.refreshToken}|$_generation');
    // Moving to another list drops the selection.
    final ctx = '$_scope|${drill?.artist}|${drill?.album}|${drill?.playlistId}|${drill?.folderId}';
    if (ctx != _selectionContext) {
      _selectionContext = ctx;
      _selected.clear();
    }
    final String? viewName = drill != null
        ? null
        : switch (_scope) {
            _Scope.favorites => LibraryView.favorites,
            _Scope.recent => LibraryView.recent,
            _Scope.top => LibraryView.top,
            _Scope.newest => LibraryView.newest,
            _ => null,
          };
    final songsShown = drill != null ||
        _scope == _Scope.songs ||
        _scope == _Scope.favorites ||
        _scope == _Scope.recent ||
        _scope == _Scope.top ||
        _scope == _Scope.newest;

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
            if (_selected.isNotEmpty && songsShown)
              _selectionBar(drill, viewName)
            else if (drill == null)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    for (final s in _Scope.values) ...[
                      ChoiceChip(
                        label: Text(switch (s) {
                          _Scope.songs => 'Songs',
                          _Scope.artists => 'Artists',
                          _Scope.albums => 'Albums',
                          _Scope.favorites => 'Favorites',
                          _Scope.recent => 'Recent',
                          _Scope.top => 'Top',
                          _Scope.newest => 'New',
                          _Scope.folders => 'Folders',
                          _Scope.playlists => 'Playlists',
                        }),
                        selected: _scope == s,
                        onSelected: (_) {
                          Haptics.selection();
                          setState(() => _scope = s);
                        },
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
                onRename: drill.playlistId == null ? null : () => _renamePlaylist(drill),
                onDelete: drill.playlistId == null ? null : () => _deletePlaylist(drill),
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
                _Scope.songs => _songList(drill),
                _Scope.favorites => _songList(null, view: LibraryView.favorites),
                _Scope.recent => _songList(null, view: LibraryView.recent),
                _Scope.top => _songList(null, view: LibraryView.top),
                _Scope.newest => _songList(null, view: LibraryView.newest),
                _Scope.folders => _PagedList<RemoteFolder>(
                    key: key,
                    emptyMessage: _query.isEmpty ? widget.emptyMessage : 'No matches.',
                    load: (offset, limit) => widget.source
                        .folders(query: _query, offset: offset, limit: limit),
                    itemBuilder: (context, f) => ListTile(
                      minTileHeight: 64,
                      leading: const CircleAvatar(child: Icon(Icons.folder_rounded)),
                      title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${f.parent.isEmpty ? '' : '${f.parent} · '}'
                          '${f.songCount} song${f.songCount == 1 ? '' : 's'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => setState(() {
                        _search.clear();
                        _query = '';
                        _drill = _Drill(title: f.name, folderId: f.id);
                      }),
                    ),
                  ),
                _Scope.playlists => Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton.icon(
                            onPressed: _newPlaylist,
                            icon: const Icon(Icons.add_rounded),
                            label: const Text('New playlist'),
                          ),
                        ),
                      ),
                      Expanded(
                        child: _PagedList<RemotePlaylist>(
                          key: key,
                          emptyMessage: _query.isEmpty
                              ? 'No playlists yet. Make one with New playlist.'
                              : 'No matches.',
                          load: (offset, limit) => widget.source
                              .playlists(query: _query, offset: offset, limit: limit),
                          itemBuilder: (context, l) => ListTile(
                            minTileHeight: 64,
                            leading: const CircleAvatar(
                                child: Icon(Icons.queue_music_rounded)),
                            title: Text(l.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                                '${l.songCount} song${l.songCount == 1 ? '' : 's'}'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => setState(() {
                              _search.clear();
                              _query = '';
                              _drill = _Drill(title: l.name, playlistId: l.id);
                            }),
                          ),
                        ),
                      ),
                    ],
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
    this.onRename,
    this.onDelete,
  });

  final String title;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
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
          if (onRename != null || onDelete != null)
            PopupMenuButton<bool>(
              tooltip: 'Playlist options',
              onSelected: (rename) => rename ? onRename?.call() : onDelete?.call(),
              itemBuilder: (context) => const [
                PopupMenuItem(value: true, child: Text('Rename')),
                PopupMenuItem(value: false, child: Text('Delete playlist')),
              ],
            ),
        ],
      ),
    );
  }
}

enum _SongAction { playNext, addToQueue, addToPlaylist, removeFromPlaylist, remove }

class _SongTile extends StatelessWidget {
  const _SongTile({
    required this.song,
    required this.source,
    required this.onTap,
    required this.onPlayNext,
    required this.onAddToQueue,
    required this.onFavorite,
    required this.onAddToPlaylist,
    required this.size,
    required this.selecting,
    required this.selected,
    required this.onSelect,
    this.onRemoveFromPlaylist,
    this.onRemove,
  });

  final SongListSize size;

  /// Some songs are picked: show check marks, hide per-song buttons.
  final bool selecting;
  final bool selected;

  /// Starts or toggles selection (long-press).
  final VoidCallback onSelect;

  final RemoteSong song;
  final MusicSource source;
  final VoidCallback onTap;
  final VoidCallback onPlayNext;
  final VoidCallback onAddToQueue;
  final VoidCallback onAddToPlaylist;
  final VoidCallback? onRemoveFromPlaylist;
  final Future<void> Function(bool favorite) onFavorite;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = !song.available;
    final subtitle = dim
        ? 'File missing from the Player'
        : '${song.artist} · ${song.album}';

    final k = size.scale;
    return ListTile(
      minTileHeight: 64 * k,
      dense: k < 1,
      enabled: true,
      selected: selected,
      selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.12),
      leading: SongArt(
        source: source,
        songId: song.id,
        radius: 20 * k,
        overlayIcon: selected
            ? Icons.check_rounded
            : dim
                ? Icons.error_outline_rounded
                : null,
        overlayColor: dim && !selected ? theme.colorScheme.error : null,
      ),
      title: Text(song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 16 * k,
            color: dim ? theme.colorScheme.onSurface.withValues(alpha: 0.5) : null,
          )),
      subtitle: Text(subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 14 * k)),
      onLongPress: () {
        Haptics.medium(); // starting a selection feels like picking something up
        onSelect();
      },
      trailing: selecting
          ? null
          : Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (song.durationSeconds > 0)
            Text(formatDuration(song.durationSeconds),
                style: theme.textTheme.bodySmall?.copyWith(fontSize: 12 * k)),
          _FavoriteButton(initial: song.favorite, onChanged: onFavorite),
          PopupMenuButton<_SongAction>(
            tooltip: 'More',
            onSelected: (a) => switch (a) {
              _SongAction.playNext => onPlayNext(),
              _SongAction.addToQueue => onAddToQueue(),
              _SongAction.addToPlaylist => onAddToPlaylist(),
              _SongAction.removeFromPlaylist => onRemoveFromPlaylist?.call(),
              _SongAction.remove => onRemove?.call(),
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                  value: _SongAction.playNext, child: Text('Play next')),
              const PopupMenuItem(
                  value: _SongAction.addToQueue, child: Text('Add to queue')),
              const PopupMenuItem(
                  value: _SongAction.addToPlaylist, child: Text('Add to playlist')),
              if (onRemoveFromPlaylist != null)
                const PopupMenuItem(
                    value: _SongAction.removeFromPlaylist,
                    child: Text('Remove from playlist')),
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

/// Heart toggle for a song. Updates at once and goes back if the Player says no.
class _FavoriteButton extends StatefulWidget {
  const _FavoriteButton({required this.initial, required this.onChanged});

  final bool initial;
  final Future<void> Function(bool favorite) onChanged;

  @override
  State<_FavoriteButton> createState() => _FavoriteButtonState();
}

class _FavoriteButtonState extends State<_FavoriteButton> {
  late bool _fav = widget.initial;

  Future<void> _toggle() async {
    Haptics.selection();
    final next = !_fav;
    setState(() => _fav = next);
    try {
      await widget.onChanged(next);
    } catch (e) {
      if (!mounted) return;
      setState(() => _fav = !next);
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: _fav ? 'Remove from favorites' : 'Add to favorites',
      icon: Icon(
        _fav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
        color: _fav ? Theme.of(context).colorScheme.primary : null,
      ),
      onPressed: _toggle,
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
