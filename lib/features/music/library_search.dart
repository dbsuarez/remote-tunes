import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/haptics.dart';
import '../../core/protocol/library_models.dart';
import '../../core/search_history.dart';
import '../../core/song_list_style.dart';
import 'music_browser.dart';
import 'music_source.dart';
import 'song_art.dart';

enum _Where { all, songs, albums, artists, albumArtists, folders }

/// A full-screen search over songs, albums, artists and folders, with a
/// history of what was searched lately. Tapping an album, artist or folder opens
/// it; tapping a song plays it.
class LibrarySearchScreen extends ConsumerStatefulWidget {
  const LibrarySearchScreen({
    super.key,
    required this.source,
    this.size = SongListSize.small,
    this.embedded = false,
  });

  /// Shown as a tab (no back arrow, and no screen of its own).
  final bool embedded;

  final MusicSource source;
  final SongListSize size;

  @override
  ConsumerState<LibrarySearchScreen> createState() => _LibrarySearchScreenState();
}

class _LibrarySearchScreenState extends ConsumerState<LibrarySearchScreen> {
  static const _previewCount = 5;

  final TextEditingController _text = TextEditingController();
  final FocusNode _focus = FocusNode();
  Timer? _debounce;
  _Where _where = _Where.all;
  String _query = '';
  int _generation = 0;
  bool _loading = false;
  String? _error;

  List<RemoteSong> _songs = const [];
  List<RemoteAlbum> _albums = const [];
  List<RemoteArtist> _artists = const [];
  List<RemoteGroup> _albumArtists = const [];
  List<RemoteFolder> _folders = const [];

  @override
  void dispose() {
    _debounce?.cancel();
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _onChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(text));
    setState(() {}); // for the clear button
  }

  void _setQuery(String text) {
    _text.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _debounce?.cancel();
    _search(text);
  }

  Future<void> _search(String raw) async {
    final q = raw.trim();
    final gen = ++_generation;
    if (q.isEmpty) {
      setState(() {
        _query = '';
        _loading = false;
        _error = null;
        _songs = const [];
        _albums = const [];
        _artists = const [];
        _albumArtists = const [];
        _folders = const [];
      });
      return;
    }
    setState(() {
      _query = q;
      _loading = true;
      _error = null;
    });
    final s = widget.source;
    final all = _where == _Where.all;
    final n = all ? _previewCount : 50;
    try {
      Future<Object> maybe(bool on, Future<Object> Function() ask) =>
          on ? ask() : Future<Object>.value(0);
      final r = await Future.wait<Object>([
        maybe(all || _where == _Where.songs, () => s.songs(query: q, limit: n)),
        maybe(all || _where == _Where.albums, () => s.albums(query: q, limit: n)),
        maybe(all || _where == _Where.artists, () => s.artists(query: q, limit: n)),
        maybe(all || _where == _Where.albumArtists,
            () => s.groups(kind: GroupKind.albumArtist, query: q, limit: n)),
        maybe(all || _where == _Where.folders, () => s.folders(query: q, limit: n)),
      ]);
      if (!mounted || gen != _generation) return;
      setState(() {
        _songs = r[0] is LibraryPage<RemoteSong> ? (r[0] as LibraryPage<RemoteSong>).items : const [];
        _albums = r[1] is LibraryPage<RemoteAlbum> ? (r[1] as LibraryPage<RemoteAlbum>).items : const [];
        _artists = r[2] is LibraryPage<RemoteArtist> ? (r[2] as LibraryPage<RemoteArtist>).items : const [];
        _albumArtists =
            r[3] is LibraryPage<RemoteGroup> ? (r[3] as LibraryPage<RemoteGroup>).items : const [];
        _folders = r[4] is LibraryPage<RemoteFolder> ? (r[4] as LibraryPage<RemoteFolder>).items : const [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e);
      });
    }
  }

  void _remember() => ref.read(searchHistoryProvider.notifier).add(_query);

  void _open(LibraryTarget target) {
    _remember();
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        body: SafeArea(
          child: MusicBrowser(
            source: widget.source,
            size: widget.size,
            initialTarget: target,
          ),
        ),
      ),
    ));
  }

  /// Plays every song found (in order, or shuffled).
  Future<void> _playAll({required bool shuffle}) async {
    Haptics.selection();
    _remember();
    final songs = _songs.where((s) => s.available).toList();
    if (songs.isEmpty) return;
    if (shuffle) songs.shuffle();
    try {
      await widget.source.playSongs([for (final s in songs) s.id]);
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  Future<void> _play(RemoteSong song) async {
    Haptics.selection();
    _remember();
    if (!song.available) {
      _snack("This song's file is missing from the Player.");
      return;
    }
    try {
      await widget.source.playSongs([song.id], keepQueue: true);
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final content = Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(widget.embedded ? 12 : 4, 8, 12, 0),
              child: Row(
                children: [
                  if (!widget.embedded)
                    IconButton(
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back_rounded),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  Expanded(
                    child: TextField(
                      controller: _text,
                      focusNode: _focus,
                      autofocus: !widget.embedded,
                      textInputAction: TextInputAction.search,
                      onChanged: _onChanged,
                      onSubmitted: (v) {
                        _debounce?.cancel();
                        _search(v);
                        ref.read(searchHistoryProvider.notifier).add(v);
                      },
                      decoration: InputDecoration(
                        hintText: 'Search your music',
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _text.text.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                icon: const Icon(Icons.close_rounded),
                                onPressed: () {
                                  _text.clear();
                                  _search('');
                                  _focus.requestFocus();
                                },
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  for (final w in _Where.values) ...[
                    ChoiceChip(
                      label: Text(switch (w) {
                        _Where.all => 'All',
                        _Where.songs => 'Songs',
                        _Where.albums => 'Albums',
                        _Where.artists => 'Artists',
                        _Where.albumArtists => 'Album Artists',
                        _Where.folders => 'Folders',
                      }),
                      selected: _where == w,
                      onSelected: (_) {
                        Haptics.selection();
                        setState(() => _where = w);
                        _search(_text.text);
                      },
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            Expanded(child: _body(theme)),
          ],
        );
    if (widget.embedded) return content;
    return Scaffold(body: SafeArea(child: content));
  }

  Widget _body(ThemeData theme) {
    if (_query.isEmpty) return _history(theme);
    if (_error != null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)));
    }
    final nothing = _songs.isEmpty &&
        _albums.isEmpty &&
        _artists.isEmpty &&
        _albumArtists.isEmpty &&
        _folders.isEmpty;
    if (nothing) {
      return Center(
        child: _loading
            ? const CircularProgressIndicator(strokeWidth: 2)
            : Text('No matches for "$_query".', style: theme.textTheme.bodyMedium),
      );
    }
    final all = _where == _Where.all;
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        if (_songs.isNotEmpty) ...[
          if (all) _section(theme, 'Songs', _Where.songs),
          // Play or shuffle everything found.
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            child: Row(
              children: [
                TextButton.icon(
                  onPressed: () => _playAll(shuffle: false),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('Play'),
                ),
                TextButton.icon(
                  onPressed: () => _playAll(shuffle: true),
                  icon: const Icon(Icons.shuffle_rounded),
                  label: const Text('Shuffle'),
                ),
              ],
            ),
          ),
          for (final s in _songs)
            ListTile(
              leading: SongArt(source: widget.source, songId: s.id, radius: 20),
              title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${s.artist} · ${s.album}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: () => _play(s),
            ),
        ],
        if (_albums.isNotEmpty) ...[
          if (all) _section(theme, 'Albums', _Where.albums),
          for (final a in _albums)
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.album_rounded)),
              title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${a.artist} · ${a.songCount} song${a.songCount == 1 ? '' : 's'}',
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _open(LibraryTarget(title: a.name, artist: a.artist, album: a.name)),
            ),
        ],
        if (_artists.isNotEmpty) ...[
          if (all) _section(theme, 'Artists', _Where.artists),
          for (final a in _artists)
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_rounded)),
              title: Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${a.songCount} song${a.songCount == 1 ? '' : 's'}'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _open(LibraryTarget(title: a.name, artist: a.name)),
            ),
        ],
        if (_albumArtists.isNotEmpty) ...[
          if (all) _section(theme, 'Album Artists', _Where.albumArtists),
          for (final g in _albumArtists)
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.mic_rounded)),
              title: Text(g.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text('${g.songCount} song${g.songCount == 1 ? '' : 's'}'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _open(LibraryTarget(
                  title: g.name, groupKind: GroupKind.albumArtist, groupValue: g.name)),
            ),
        ],
        if (_folders.isNotEmpty) ...[
          if (all) _section(theme, 'Folders', _Where.folders),
          for (final f in _folders)
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.folder_rounded)),
              title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                  '${f.parent.isEmpty ? '' : '${f.parent} · '}${f.songCount} song${f.songCount == 1 ? '' : 's'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _open(LibraryTarget(title: f.name, folderId: f.id)),
            ),
        ],
      ],
    );
  }

  Widget _section(ThemeData theme, String title, _Where scope) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary)),
          ),
          TextButton(
            onPressed: () {
              setState(() => _where = scope);
              _search(_text.text);
            },
            child: const Text('See all'),
          ),
        ],
      ),
    );
  }

  Widget _history(ThemeData theme) {
    final history = ref.watch(searchHistoryProvider);
    if (history.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('Search songs, albums, artists and folders.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ),
      );
    }
    return ListView(
      children: [
        for (final h in history)
          ListTile(
            leading: const Icon(Icons.history_rounded),
            title: Text(h, maxLines: 1, overflow: TextOverflow.ellipsis),
            onTap: () => _setQuery(h),
            trailing: IconButton(
              tooltip: 'Remove "$h" from the history',
              icon: const Icon(Icons.close_rounded),
              onPressed: () => ref.read(searchHistoryProvider.notifier).remove(h),
            ),
          ),
        Center(
          child: TextButton(
            onPressed: () => ref.read(searchHistoryProvider.notifier).clear(),
            child: const Text('Clear search history'),
          ),
        ),
      ],
    );
  }
}
