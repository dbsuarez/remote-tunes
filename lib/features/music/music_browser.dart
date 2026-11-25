import '../library/lookup_models.dart';
import 'group_menu.dart';
import '../../core/widgets/default_art.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../core/protocol/library_models.dart';
import '../../core/song_list_look.dart';
import '../../core/song_list_style.dart';
import 'list_options_sheet.dart';
import '../../core/widgets/playback_widgets.dart';
import 'music_source.dart';
import 'song_art.dart';
import 'song_info_dialog.dart';

enum _Scope {
  songs,
  artists,
  albums,
  favorites,
  recent,
  playlists,
  top,
  skipped,
  never,
  newest,
  folders,
  albumArtists,
  genres,
  years,
  composers,
}

class _Drill {
  const _Drill({
    required this.title,
    this.artist,
    this.album,
    this.playlistId,
    this.folderId,
    this.groupKind,
    this.groupValue,
  });

  /// A genre, a year or an album artist ([GroupKind]) and which one.
  final String? groupKind;
  final String? groupValue;

  final String title;
  final String? artist;
  final String? album;
  final int? playlistId;
  final int? folderId;
}

/// An extra row on the Library list (for example the Online Library) that opens
/// its own page.
class LibraryExtra {
  const LibraryExtra({
    required this.title,
    required this.icon,
    required this.color,
    required this.builder,
  });

  final String title;
  final IconData icon;
  final Color color;
  final WidgetBuilder builder;
}

/// Something to open straight away in the browser (an album, an artist or a
/// folder), used by the search screen.
class LibraryTarget {
  const LibraryTarget({
    required this.title,
    this.artist,
    this.album,
    this.folderId,
    this.groupKind,
    this.groupValue,
  });

  /// A genre, a year or an album artist ([GroupKind]) and which one.
  final String? groupKind;
  final String? groupValue;

  final String title;
  final String? artist;
  final String? album;
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
    this.onEditSong,
    this.canWriteTags = false,
    this.onEditSongs,
    this.songLookup,
    this.looks = const {},
    this.onLook,
    this.emptyMessage = 'No songs yet.',
    this.size = SongListSize.small,
    this.homeList = false,
    this.onSearch,
    this.initialTarget,
    this.extraCategories = const [],
    this.startOnPlaylists = false,
  });

  /// Open straight on the playlists (the menu's Playlists shortcut).
  final bool startOnPlaylists;

  /// More rows for the category list (home-list mode only).
  final List<LibraryExtra> extraCategories;

  /// Start on a list of categories (All Songs, Folders, Albums...) instead of
  /// the row of filter chips. Opening one shows it with a back arrow.
  final bool homeList;

  /// Shows a search button on the category list.
  final VoidCallback? onSearch;

  /// Opens this album / artist / folder at once; going back leaves the screen.
  final LibraryTarget? initialTarget;

  /// Text size of the song rows.
  final SongListSize size;

  final MusicSource source;

  /// False disables interaction (e.g. while the Controller is reconnecting).
  final bool enabled;

  /// Change this value to reload the lists (e.g. after an import).
  final int refreshToken;

  /// Player only: shows "Remove from library" in the song menu.
  final Future<void> Function(RemoteSong song)? onRemoveSong;

  /// Player only: shows "Edit info" in the song menu (title, artist, album and
  /// track number, in this library only).
  final Future<bool> Function(RemoteSong song, SongInfoEdit edit)? onEditSong;

  /// Offer to write the tags into the music file too (this phone's own library).
  final bool canWriteTags;

  /// Edit info for the songs picked with Select (null: not offered, e.g. for another phone's
  /// library). Returns true if anything changed.
  final Future<bool> Function(BuildContext context, List<int> ids)? onEditSongs;

  /// Looks a song up on the internet from Edit info (this phone's library only).
  final SongLookupService? songLookup;

  /// How each kind of song list is drawn, and how to remember a change (null: no List options,
  /// e.g. on the web Controller).
  final Map<String, ListLook> looks;
  final void Function(String kind, ListLook look)? onLook;
  final String emptyMessage;

  @override
  State<MusicBrowser> createState() => _MusicBrowserState();
}

class _MusicBrowserState extends State<MusicBrowser> {
  late _Scope _scope = widget.startOnPlaylists ? _Scope.playlists : _Scope.songs;
  late _Drill? _drill = widget.initialTarget == null
      ? null
      : _Drill(
          title: widget.initialTarget!.title,
          artist: widget.initialTarget!.artist,
          album: widget.initialTarget!.album,
          folderId: widget.initialTarget!.folderId,
          groupKind: widget.initialTarget!.groupKind,
          groupValue: widget.initialTarget!.groupValue,
        );

  /// Folders picked for a bulk action (long-press a folder to start).
  final Set<int> _selectedFolders = {};

  /// What the search box said before a list was opened (restored on Back).
  String _savedQuery = '';
  String _savedText = '';

  /// The last item opened from a list; it is marked when you come back.
  String? _lastOpened;

  /// The search text the lists behind an opened item were filtered with.
  String get _listQuery => _drill == null ? _query : _savedQuery;

  /// Opens an item of a list. The list is kept (scroll position, what was
  /// loaded) and [mark] says which row to highlight on return.
  void _openDrill(_Drill d, String mark) {
    setState(() {
      _savedQuery = _query;
      _savedText = _search.text;
      _search.clear();
      _query = '';
      _selectedFolders.clear();
      _lastOpened = mark;
      _drill = d;
    });
  }

  /// Back from an opened item to the list it came from.
  void _closeDrill() {
    setState(() {
      _drill = null;
      _search.text = _savedText;
      _query = _savedQuery;
    });
  }

  /// A quiet tint for the row that was opened last.
  Color? _markColor(String mark) => _lastOpened == mark
      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.10)
      : null;

  @override
  void initState() {
    super.initState();
    _loadCounts();
  }

  @override
  void didUpdateWidget(MusicBrowser old) {
    super.didUpdateWidget(old);
    // The library changed (songs added or removed): the numbers are stale.
    if (old.refreshToken != widget.refreshToken) _loadCounts(force: true);
  }

  /// How many there are in each category, for the Library list (null: not known yet).
  Map<_Scope, int> _counts = const {};
  DateTime? _countsAt;
  bool _countsBusy = false;

  /// Asks the source for the size of every category (one tiny request each).
  Future<void> _loadCounts({bool force = false}) async {
    if (!widget.homeList || _countsBusy) return;
    final at = _countsAt;
    if (!force && at != null && DateTime.now().difference(at) < const Duration(seconds: 15)) {
      return;
    }
    _countsBusy = true;
    final s = widget.source;
    Future<int?> total<T>(Future<LibraryPage<T>> f) async {
      try {
        return (await f).total;
      } catch (_) {
        return null;
      }
    }

    final scopes = <_Scope, Future<int?>>{
      _Scope.songs: total(s.songs(limit: 1)),
      _Scope.folders: total(s.folders(limit: 1)),
      _Scope.albums: total(s.albums(limit: 1)),
      _Scope.artists: total(s.artists(limit: 1)),
      _Scope.albumArtists: total(s.groups(kind: GroupKind.albumArtist, limit: 1)),
      _Scope.genres: total(s.groups(kind: GroupKind.genre, limit: 1)),
      _Scope.years: total(s.groups(kind: GroupKind.year, limit: 1)),
      _Scope.composers: total(s.groups(kind: GroupKind.composer, limit: 1)),
      _Scope.favorites: total(s.songs(view: LibraryView.favorites, limit: 1)),
      _Scope.recent: total(s.songs(view: LibraryView.recent, limit: 1)),
      _Scope.top: total(s.songs(view: LibraryView.top, limit: 1)),
      _Scope.skipped: total(s.songs(view: LibraryView.skipped, limit: 1)),
      _Scope.never: total(s.songs(view: LibraryView.never, limit: 1)),
      _Scope.newest: total(s.songs(view: LibraryView.newest, limit: 1)),
      _Scope.playlists: total(s.playlists(limit: 1)),
    };
    final got = <_Scope, int>{};
    for (final e in scopes.entries) {
      final n = await e.value;
      if (n != null) got[e.key] = n;
    }
    _countsBusy = false;
    if (!mounted) return;
    setState(() {
      _counts = got;
      _countsAt = DateTime.now();
    });
  }

  /// Showing the list of categories (only with [MusicBrowser.homeList]).
  late bool _home =
      widget.homeList && widget.initialTarget == null && !widget.startOnPlaylists;

  static String _scopeTitle(_Scope s) => switch (s) {
        _Scope.songs => 'All Songs',
        _Scope.artists => 'Artists',
        _Scope.albums => 'Albums',
        _Scope.folders => 'Folders',
        _Scope.favorites => 'Favorites',
        _Scope.recent => 'Recent',
        _Scope.top => 'Most played',
        _Scope.skipped => 'Most skipped',
        _Scope.never => 'Never played',
        _Scope.newest => 'New',
        _Scope.playlists => 'Playlists',
        _Scope.albumArtists => 'Album Artists',
        _Scope.genres => 'Genres',
        _Scope.years => 'Years',
        _Scope.composers => 'Composers',
      };
  String _query = '';
  int _generation = 0;

  /// How many songs, and how long, each song list holds (by its kind), for the header.
  final Map<String, (int, int)> _totals = {};

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
          groupKind: d.groupKind,
          groupValue: d.groupValue,
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
          groupKind: drill?.groupKind,
          groupValue: drill?.groupValue,
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

  /// Every song in the picked folders (bounded, like the other bulk actions).
  Future<List<int>> _songIdsOfFolders(Iterable<int> folderIds) async {
    final ids = <int>[];
    for (final f in folderIds) {
      var offset = 0;
      while (ids.length < 2000) {
        final page = await widget.source.songs(folderId: f, offset: offset, limit: 100);
        ids.addAll([for (final s in page.items) s.id]);
        offset += page.items.length;
        if (!page.hasMore || page.items.isEmpty) break;
      }
    }
    return ids;
  }

  Widget _folderSelectionBar() {
    final n = _selectedFolders.length;
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: SizedBox(
        height: 56,
        child: Row(
          children: [
            IconButton(
              tooltip: 'Cancel selection',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => setState(_selectedFolders.clear),
            ),
            Expanded(
              child: Text('$n folder${n == 1 ? '' : 's'} selected',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
            ),
            IconButton(
              tooltip: 'Select all folders',
              icon: const Icon(Icons.select_all_rounded),
              onPressed: () => _run(() async {
                final all = <int>[];
                var offset = 0;
                while (all.length < 2000) {
                  final page = await widget.source
                      .folders(query: _listQuery, offset: offset, limit: 100);
                  all.addAll([for (final f in page.items) f.id]);
                  offset += page.items.length;
                  if (!page.hasMore || page.items.isEmpty) break;
                }
                if (mounted) setState(() => _selectedFolders.addAll(all));
              }),
            ),
            IconButton(
              tooltip: 'Add selected folders to queue',
              icon: const Icon(Icons.queue_music_rounded),
              onPressed: () => _run(() async {
                final ids = await _songIdsOfFolders(_selectedFolders);
                if (ids.isEmpty) return;
                await widget.source.queueSongs(ids);
                if (mounted) setState(_selectedFolders.clear);
              }, done: 'Added to queue'),
            ),
            IconButton(
              tooltip: 'Add selected folders to playlist',
              icon: const Icon(Icons.playlist_add_rounded),
              onPressed: () async {
                List<int> ids = const [];
                await _run(() async => ids = await _songIdsOfFolders(_selectedFolders));
                if (ids.isEmpty) return;
                if (await _addIdsToPlaylist(ids) && mounted) {
                  setState(_selectedFolders.clear);
                }
              },
            ),
          ],
        ),
      ),
    );
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
            // Edit info for all the picked songs (only what they can share).
            if (widget.onEditSongs != null)
              IconButton(
                tooltip: 'Edit info of the selected songs',
                icon: const Icon(Icons.edit_note_rounded),
                onPressed: () async {
                  final ids = _selected.toList();
                  final done = await widget.onEditSongs!(context, ids);
                  if (done && mounted) {
                    setState(() {
                      _selected.clear();
                      _generation++;
                    });
                  }
                },
              ),
            // Inside a playlist: take the picked songs out of it (the songs stay in
            // the library).
            if (drill?.playlistId != null)
              IconButton(
                tooltip: 'Remove selected from the playlist',
                icon: const Icon(Icons.playlist_remove_rounded),
                onPressed: () => _run(() async {
                  final ids = _selected.toList();
                  for (final id in ids) {
                    await widget.source.removeFromPlaylist(drill!.playlistId!, id);
                  }
                  if (mounted) {
                    setState(() {
                      _selected.clear();
                      _generation++;
                    });
                  }
                }, done: 'Removed from the playlist'),
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

  /// A list of genres, years or album artists; opening one lists its songs.
  Widget _groupList(String kind, IconData icon) {
    final key = ValueKey('$_scope|$_listQuery|${widget.refreshToken}|$_generation');
    return _PagedList<RemoteGroup>(
      key: key,
      emptyMessage: _listQuery.isNotEmpty
          ? 'No matches.'
          : switch (kind) {
              GroupKind.genre => 'No genres yet. In Settings, "Update tags from files" reads them.',
              GroupKind.year => 'No years yet. In Settings, "Update tags from files" reads them.',
              GroupKind.composer =>
                'No composers yet. In Settings, "Update tags from files" reads them (MP3, FLAC, Ogg and APE files that have the tag).',
              _ => 'No album artists yet. In Settings, "Update tags from files" reads them.',
            },
      load: (offset, limit) =>
          widget.source.groups(kind: kind, query: _listQuery, offset: offset, limit: limit),
      itemBuilder: (context, g) => ListTile(
        minTileHeight: 64,
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${g.songCount} song${g.songCount == 1 ? '' : 's'}'),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GroupMenuButton(
              source: widget.source,
              name: g.name,
              loadIds: () => songIdsOf(widget.source, groupKind: kind, groupValue: g.name),
            ),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
        tileColor: _markColor('group:$kind:${g.name}'),
        onTap: () => _openDrill(
            _Drill(title: g.name, groupKind: kind, groupValue: g.name), 'group:$kind:${g.name}'),
      ),
    );
  }

  /// Which kind of list this is, for remembering its look.
  String _kindOf(_Drill? drill, String? view) {
    if (drill != null) {
      if (drill.playlistId != null) return 'playlist';
      if (drill.folderId != null) return 'folder';
      if (drill.groupValue != null) return 'group';
      if (drill.album != null) return 'album';
      if (drill.artist != null) return 'artist';
    }
    return switch (view) {
      LibraryView.favorites => 'favorites',
      LibraryView.recent => 'recent',
      LibraryView.top => 'top',
      LibraryView.skipped => 'skipped',
      LibraryView.never => 'never',
      LibraryView.newest => 'newest',
      _ => 'songs',
    };
  }

  Widget _songList(_Drill? drill, {String? view}) {
    final kind = _kindOf(drill, view);
    final look = widget.looks[kind] ?? ListLook.standard;
    final list = _songListBody(drill, view, look);
    if (widget.onLook == null) return list;
    final totals = _totals[kind];
    return Column(
      children: [
        Row(
          children: [
            if (totals != null)
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text(
                  key: const Key('list-count'),
                  '${totals.$1} song${totals.$1 == 1 ? '' : 's'}'
                  '${totals.$2 > 0 ? ' | ${formatTotalTime(totals.$2)}' : ''}',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
              ),
            const Spacer(),
            IconButton(
            key: const Key('list-options'),
            tooltip: 'List options',
            visualDensity: VisualDensity.compact,
            icon: Icon(Icons.tune_rounded,
                color: look.isStandard ? null : Theme.of(context).colorScheme.primary),
            onPressed: () => showListOptions(
              context,
              kind: kind,
              look: widget.looks[kind] ?? ListLook.standard,
              onChanged: (l) => widget.onLook!(kind, l),
            ),
          ),
          ],
        ),
        Expanded(child: list),
      ],
    );
  }

  Widget _songListBody(_Drill? drill, String? view, ListLook look) {
    final key = ValueKey('$_scope|$_query|${drill?.artist}|${drill?.album}|'
        '${drill?.playlistId}|${drill?.folderId}|${drill?.groupValue}|${widget.refreshToken}|$_generation');
    return _PagedList<RemoteSong>(
      key: key,
      grid: look.view == SongListView.grid,
      titlesOnly: look.titlesOnly,
      onTotals: widget.onLook == null
          ? null
          : (total, seconds) {
              final k = _kindOf(drill, view);
              if (_totals[k] != (total, seconds) && mounted) {
                setState(() => _totals[k] = (total, seconds));
              }
            },
      emptyMessage: _query.isNotEmpty
          ? 'No matches.'
          : switch (view) {
              LibraryView.favorites => 'No favorites yet. Tap the heart on a song.',
              LibraryView.recent => 'Nothing played yet.',
              LibraryView.top => 'Nothing played yet. Your most played songs show up here.',
              LibraryView.skipped =>
                'No skipped songs yet. A song counts as skipped when you move on or pick another within its first 30 seconds.',
              LibraryView.never => 'Every song has been played at least once.',
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
        groupKind: drill?.groupKind,
        groupValue: drill?.groupValue,
        offset: offset,
        limit: limit,
      ),
      itemBuilder: (context, song) => _SongTile(
        song: song,
        source: widget.source,
        countView: view == LibraryView.top || view == LibraryView.skipped ? view : null,
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
        look: look,
        selecting: _selected.isNotEmpty,
        selected: _selected.contains(song.id),
        onSelect: () => _toggleSelected(song.id),
        onRemoveFromPlaylist: drill?.playlistId == null
            ? null
            : () => _run(() async {
                  await widget.source.removeFromPlaylist(drill!.playlistId!, song.id);
                  if (mounted) setState(() => _generation++);
                }, done: 'Removed from playlist'),
        onEdit: widget.onEditSong == null
            ? null
            : () async {
                final edit = await showSongInfoDialog(context, song,
                    canWriteFile: widget.canWriteTags, lookup: widget.songLookup);
                if (edit == null) return;
                await _run(() async {
                  if (!await widget.onEditSong!(song, edit)) {
                    throw StateError('could not save');
                  }
                  if (mounted) setState(() => _generation++);
                }, done: edit.fileNote ?? 'Saved');
              },
        onRemove: widget.onRemoveSong == null
            ? null
            : () => _run(() async {
                  await widget.onRemoveSong!(song);
                  if (mounted) setState(() => _generation++);
                }, done: 'Removed from library'),
      ),
    );
  }

  /// The list of the chosen kind (songs, artists, albums, folders...). It stays built,
  /// just hidden, while one of its items is open, so Back finds it as it was.
  Widget _scopeView(ValueKey<String> scopeKey) {
    return switch (_scope) {
                _Scope.songs => _songList(null),
                _Scope.favorites => _songList(null, view: LibraryView.favorites),
                _Scope.recent => _songList(null, view: LibraryView.recent),
                _Scope.top => _songList(null, view: LibraryView.top),
                _Scope.skipped => _songList(null, view: LibraryView.skipped),
                _Scope.never => _songList(null, view: LibraryView.never),
                _Scope.newest => _songList(null, view: LibraryView.newest),
                _Scope.albumArtists => _groupList(GroupKind.albumArtist, Icons.mic_rounded),
                _Scope.genres => _groupList(GroupKind.genre, Icons.piano_rounded),
                _Scope.years => _groupList(GroupKind.year, Icons.calendar_month_rounded),
                _Scope.composers => _groupList(GroupKind.composer, Icons.edit_note_rounded),
                _Scope.folders => _PagedList<RemoteFolder>(
                    key: scopeKey,
                    emptyMessage: _listQuery.isEmpty ? widget.emptyMessage : 'No matches.',
                    load: (offset, limit) => widget.source
                        .folders(query: _listQuery, offset: offset, limit: limit),
                    itemBuilder: (context, f) {
                      final picked = _selectedFolders.contains(f.id);
                      return ListTile(
                        minTileHeight: 64,
                        selected: picked,
                        selectedTileColor:
                            Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                        tileColor: _markColor('folder:${f.id}'),
                        leading: CircleAvatar(
                            child: Icon(picked ? Icons.check_rounded : Icons.folder_rounded)),
                        title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            '${f.parent.isEmpty ? '' : '${f.parent} · '}'
                            '${f.songCount} song${f.songCount == 1 ? '' : 's'}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        trailing: _selectedFolders.isEmpty
                            ? const Icon(Icons.chevron_right_rounded)
                            : null,
                        onLongPress: () {
                          Haptics.medium();
                          setState(() => picked
                              ? _selectedFolders.remove(f.id)
                              : _selectedFolders.add(f.id));
                        },
                        onTap: () {
                          if (_selectedFolders.isNotEmpty) {
                            Haptics.selection();
                            setState(() => picked
                                ? _selectedFolders.remove(f.id)
                                : _selectedFolders.add(f.id));
                          } else {
                            _openDrill(_Drill(title: f.name, folderId: f.id), 'folder:${f.id}');
                          }
                        },
                      );
                    },
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
                          key: scopeKey,
                          emptyMessage: _listQuery.isEmpty
                              ? 'No playlists yet. Make one with New playlist.'
                              : 'No matches.',
                          load: (offset, limit) => widget.source
                              .playlists(query: _listQuery, offset: offset, limit: limit),
                          itemBuilder: (context, l) => ListTile(
                            minTileHeight: 64,
                            leading: const CircleAvatar(
                                child: Icon(Icons.queue_music_rounded)),
                            title: Text(l.name,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                                '${l.songCount} song${l.songCount == 1 ? '' : 's'}'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            tileColor: _markColor('playlist:${l.id}'),
                            onTap: () =>
                                _openDrill(_Drill(title: l.name, playlistId: l.id), 'playlist:${l.id}'),
                          ),
                        ),
                      ),
                    ],
                  ),
                _Scope.artists => _PagedList<RemoteArtist>(
                    key: scopeKey,
                    emptyMessage: _listQuery.isEmpty ? widget.emptyMessage : 'No matches.',
                    load: (offset, limit) => widget.source
                        .artists(query: _listQuery, offset: offset, limit: limit),
                    itemBuilder: (context, a) => ListTile(
                      minTileHeight: 64,
                      leading: DefaultArt.artistAvatar(),
                      title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${a.songCount} song${a.songCount == 1 ? '' : 's'} · '
                          '${a.albumCount} album${a.albumCount == 1 ? '' : 's'}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GroupMenuButton(
                            source: widget.source,
                            name: a.name,
                            loadIds: () => songIdsOf(widget.source, artist: a.name),
                          ),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                      tileColor: _markColor('artist:${a.name}'),
                      onTap: () => _openDrill(_Drill(title: a.name, artist: a.name), 'artist:${a.name}'),
                    ),
                  ),
                _Scope.albums => _PagedList<RemoteAlbum>(
                    key: scopeKey,
                    emptyMessage: _listQuery.isEmpty ? widget.emptyMessage : 'No matches.',
                    load: (offset, limit) => widget.source
                        .albums(query: _listQuery, offset: offset, limit: limit),
                    itemBuilder: (context, a) => ListTile(
                      minTileHeight: 64,
                      leading: const CircleAvatar(child: Icon(Icons.album_rounded)),
                      title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                          '${a.artist} · ${a.songCount} song${a.songCount == 1 ? '' : 's'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GroupMenuButton(
                            source: widget.source,
                            name: a.name,
                            loadIds: () =>
                                songIdsOf(widget.source, artist: a.artist, album: a.name),
                          ),
                          const Icon(Icons.chevron_right_rounded),
                        ],
                      ),
                      tileColor: _markColor('album:${a.artist}|${a.name}'),
                      onTap: () => _openDrill(
                          _Drill(title: a.name, artist: a.artist, album: a.name),
                          'album:${a.artist}|${a.name}'),
                    ),
                  ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final drill = _drill;
    final scopeKey = ValueKey('$_scope|$_listQuery|${widget.refreshToken}|$_generation');
    // Moving to another list drops the selection.
    final ctx =
        '$_scope|${drill?.artist}|${drill?.album}|${drill?.playlistId}|${drill?.folderId}|${drill?.groupValue}';
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
            _Scope.skipped => LibraryView.skipped,
            _Scope.never => LibraryView.never,
            _Scope.newest => LibraryView.newest,
            _ => null,
          };
    final songsShown = drill != null ||
        _scope == _Scope.songs ||
        _scope == _Scope.favorites ||
        _scope == _Scope.recent ||
        _scope == _Scope.top ||
        _scope == _Scope.skipped ||
        _scope == _Scope.never ||
        _scope == _Scope.newest;

    if (_home) {
      return IgnorePointer(
        ignoring: !widget.enabled,
        child: Opacity(
          opacity: widget.enabled ? 1 : 0.5,
          child: _CategoryList(
            counts: _counts,
            extras: widget.extraCategories,
            onSearch: widget.onSearch,
            onPick: (s) {
              Haptics.selection();
              setState(() {
                _home = false;
                _scope = s;
                _selectedFolders.clear();
                _lastOpened = null;
                _search.clear();
                _query = '';
              });
            },
          ),
        ),
      );
    }

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
            else if (_selectedFolders.isNotEmpty && drill == null && _scope == _Scope.folders)
              _folderSelectionBar()
            else if (drill == null && widget.homeList)
              _CategoryHeader(
                title: _scopeTitle(_scope),
                onBack: () => setState(() {
                  _home = true;
                  _loadCounts();
                  _search.clear();
                  _query = '';
                }),
              )
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
                          _Scope.top => 'Most played',
                          _Scope.skipped => 'Most skipped',
                          _Scope.never => 'Never played',
                          _Scope.newest => 'New',
                          _Scope.folders => 'Folders',
                          _Scope.playlists => 'Playlists',
                          _Scope.albumArtists => 'Album Artists',
                          _Scope.genres => 'Genres',
                          _Scope.years => 'Years',
                          _Scope.composers => 'Composers',
                        }),
                        selected: _scope == s,
                        onSelected: (_) {
                          Haptics.selection();
                          setState(() {
                            _scope = s;
                            _selectedFolders.clear();
                            _lastOpened = null;
                          });
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
                onBack: () {
                  if (widget.initialTarget != null) {
                    Navigator.of(context).maybePop();
                  } else {
                    _closeDrill();
                  }
                },
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
                onPlaylistAll: () => _run(() async {
                  final ids = await _allSongIds(drill);
                  if (ids.isEmpty) return;
                  await _addIdsToPlaylist(ids);
                }),
              ),
            Expanded(
              child: Stack(
                children: [
                  if (widget.initialTarget == null)
                    Offstage(
                      offstage: drill != null,
                      child: TickerMode(
                        enabled: drill == null,
                        child: _scopeView(scopeKey),
                      ),
                    ),
                  if (drill != null) _songList(drill),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The list of categories shown first when the browser is in home-list mode.
class _CategoryList extends StatelessWidget {
  const _CategoryList({
    required this.onPick,
    this.onSearch,
    this.extras = const [],
    this.counts = const {},
  });

  final ValueChanged<_Scope> onPick;

  /// How many in each category (a category with no entry shows nothing).
  final Map<_Scope, int> counts;
  final VoidCallback? onSearch;
  final List<LibraryExtra> extras;

  static const _items = <(_Scope, IconData, Color)>[
    (_Scope.songs, Icons.music_note_rounded, Color(0xFF22E5D0)),
    (_Scope.folders, Icons.folder_rounded, Color(0xFF4FC3F7)),
    (_Scope.albums, Icons.album_rounded, Color(0xFF7C6CFF)),
    (_Scope.artists, Icons.person_rounded, Color(0xFFB388FF)),
    (_Scope.albumArtists, Icons.mic_rounded, Color(0xFFCE93D8)),
    (_Scope.genres, Icons.piano_rounded, Color(0xFFFFD54F)),
    (_Scope.years, Icons.calendar_month_rounded, Color(0xFFFF8A65)),
    (_Scope.composers, Icons.edit_note_rounded, Color(0xFF81C784)),
    (_Scope.favorites, Icons.favorite_rounded, Color(0xFFFF6B8B)),
    (_Scope.recent, Icons.history_rounded, Color(0xFFFFB74D)),
    (_Scope.top, Icons.trending_up_rounded, Color(0xFFFF8A65)),
    (_Scope.skipped, Icons.skip_next_rounded, Color(0xFFE57373)),
    (_Scope.never, Icons.visibility_off_outlined, Color(0xFF90A4AE)),
    (_Scope.newest, Icons.new_releases_rounded, Color(0xFFAED581)),
    (_Scope.playlists, Icons.queue_music_rounded, Color(0xFF4DB6AC)),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 8, 8),
          child: Row(
            children: [
              Expanded(child: Text('Library', style: theme.textTheme.headlineSmall)),
              if (onSearch != null)
                IconButton(
                  tooltip: 'Search',
                  icon: const Icon(Icons.search_rounded),
                  onPressed: onSearch,
                ),
            ],
          ),
        ),
        for (final (scope, icon, color) in _items)
          ListTile(
            minTileHeight: 60,
            leading: CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.18),
              child: Icon(icon, color: color),
            ),
            title: Text(_MusicBrowserState._scopeTitle(scope),
                style: theme.textTheme.titleMedium),
            trailing: counts[scope] == null
                ? null
                : Text(formatCount(counts[scope]!),
                    key: ValueKey('count-${scope.name}'),
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            onTap: () => onPick(scope),
          ),
        for (final e in extras)
          ListTile(
            minTileHeight: 60,
            leading: CircleAvatar(
              backgroundColor: e.color.withValues(alpha: 0.18),
              child: Icon(e.icon, color: e.color),
            ),
            title: Text(e.title, style: theme.textTheme.titleMedium),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () {
              Haptics.selection();
              Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (ctx) => Scaffold(
                  appBar: AppBar(title: Text(e.title)),
                  body: SafeArea(child: e.builder(ctx)),
                ),
              ));
            },
          ),
      ],
    );
  }
}

/// Back arrow and the name of the opened category.
class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader({required this.title, required this.onBack});

  final String title;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back to the Library',
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: onBack,
          ),
          Expanded(
            child: Text(title,
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
        ],
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
    required this.onPlaylistAll,
    this.onRename,
    this.onDelete,
  });

  final String title;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;
  final VoidCallback onBack;
  final VoidCallback onPlayAll;
  final VoidCallback onQueueAll;
  final VoidCallback onPlaylistAll;

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
          IconButton(
            tooltip: 'Add all to a playlist',
            icon: const Icon(Icons.playlist_add_rounded),
            onPressed: onPlaylistAll,
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

enum _SongAction { playNext, addToQueue, addToPlaylist, removeFromPlaylist, edit, remove }

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
    required this.look,
    required this.selecting,
    required this.selected,
    required this.onSelect,
    this.countView,
    this.onRemoveFromPlaylist,
    this.onEdit,
    this.onRemove,
  });

  /// In Most played / Most skipped: which number to show, big, at the right.
  final String? countView;

  final SongListSize size;
  final ListLook look;

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
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dim = !song.available;
    final subtitle = dim
        ? 'File missing from the Player'
        : '${song.artist} · ${song.album}'
            // The other number, small, in the second line.
            '${countView == LibraryView.top && song.skips > 0 ? ' · ${song.skips} skip${song.skips == 1 ? '' : 's'}' : ''}'
            '${countView == LibraryView.skipped && song.plays > 0 ? ' · ${song.plays} play${song.plays == 1 ? '' : 's'}' : ''}';
    // The number the list is about, bold at the right.
    final countText = switch (countView) {
      LibraryView.top when song.plays > 0 => '${song.plays} play${song.plays == 1 ? '' : 's'}',
      LibraryView.skipped when song.skips > 0 => '${song.skips} skip${song.skips == 1 ? '' : 's'}',
      _ => null,
    };

    final view = look.view;
    if (view == SongListView.grid) return _gridCell(context, theme, dim);
    final k = size.scale *
        switch (view) {
          SongListView.listSmall => 0.85,
          SongListView.listCompact => 0.8,
          SongListView.oneLine => 0.85,
          _ => 1.0,
        };
    final showArt = view != SongListView.noImages;
    final tight = view == SongListView.listCompact || view == SongListView.oneLine;
    final oneLine = view == SongListView.oneLine;
    return ListTile(
      minTileHeight: (tight ? 48 : 64) * k,
      dense: k < 1,
      enabled: true,
      selected: selected,
      selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.12),
      leading: !showArt
          ? (selected ? const Icon(Icons.check_rounded) : null)
          : SongArt(
        source: source,
        songId: song.id,
        radius: (tight ? 14 : 20) * k,
        overlayIcon: selected
            ? Icons.check_rounded
            : dim
                ? Icons.error_outline_rounded
                : null,
        overlayColor: dim && !selected ? theme.colorScheme.error : null,
      ),
      title: Text(
          oneLine && !look.titlesOnly && !dim ? '${song.title} · ${song.artist}' : song.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 16 * k,
            color: dim ? theme.colorScheme.onSurface.withValues(alpha: 0.5) : null,
          )),
      subtitle: look.titlesOnly || oneLine
          ? null
          : Text(subtitle,
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
          if (countText != null)
            Text(countText,
                key: const Key('song-count'),
                style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary, fontWeight: FontWeight.w700))
          else if (song.durationSeconds > 0)
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
              _SongAction.edit => onEdit?.call(),
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
              if (onEdit != null)
                const PopupMenuItem(value: _SongAction.edit, child: Text('Edit info')),
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

  /// One cell of the grid view: the cover, the title and (unless titles only) the artist. A tap
  /// plays it, a long-press picks it (the song menu is in the list views).
  Widget _gridCell(BuildContext context, ThemeData theme, bool dim) {
    final muted = theme.colorScheme.onSurfaceVariant;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      onLongPress: () {
        Haptics.medium();
        onSelect();
      },
      child: Container(
        margin: const EdgeInsets.all(3),
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: selected ? theme.colorScheme.primary.withValues(alpha: 0.18) : null,
        ),
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) => Center(
                  child: SongArt(
                    source: source,
                    songId: song.id,
                    radius: (box.biggest.shortestSide / 2).clamp(16.0, 80.0),
                    overlayIcon: selected
                        ? Icons.check_rounded
                        : dim
                            ? Icons.error_outline_rounded
                            : null,
                    overlayColor: dim && !selected ? theme.colorScheme.error : null,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(song.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                    fontSize: 13,
                    color: dim ? theme.colorScheme.onSurface.withValues(alpha: 0.5) : null)),
            if (!look.titlesOnly)
              Text(song.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 11, color: muted)),
          ],
        ),
      ),
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
    this.grid = false,
    this.titlesOnly = false,
    this.onTotals,
  });

  /// Told how many items the list has and how long they play (after each page).
  final void Function(int total, int seconds)? onTotals;

  /// Cells side by side instead of rows (the item builder then returns a grid cell).
  final bool grid;
  final bool titlesOnly;
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
      widget.onTotals?.call(page.total, page.totalSeconds);
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
    if (widget.grid) {
      return GridView.builder(
        controller: _scroll,
        padding: const EdgeInsets.all(8),
        gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 150,
          childAspectRatio: widget.titlesOnly ? 0.85 : 0.72,
        ),
        itemCount: _items.length,
        itemBuilder: (context, i) => widget.itemBuilder(context, _items[i]),
      );
    }
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
