import 'group_menu.dart';
import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../core/protocol/library_models.dart';
import 'music_source.dart';
import 'song_art.dart';

/// Your music as folders inside folders. Tap a folder to go into it, the arrow
/// to go up. A folder's own songs are listed under its sub-folders.
class FolderTreeView extends StatefulWidget {
  const FolderTreeView({super.key, required this.source});

  final MusicSource source;

  @override
  State<FolderTreeView> createState() => _FolderTreeViewState();
}

class _FolderTreeViewState extends State<FolderTreeView> {
  /// From the top folder down to the one open now.
  final List<RemoteFolder> _path = [];
  RemoteFolder? _root;
  bool _loading = true;
  String? _error;

  List<RemoteFolder> _children = const [];
  List<RemoteSong> _songs = const [];

  /// The folder opened last when going up, so it can be marked.
  int? _lastOpened;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final root = await widget.source.folderRoot();
      if (!mounted) return;
      if (root == null) {
        setState(() {
          _loading = false;
          _root = null;
        });
        return;
      }
      _root = root;
      _path
        ..clear()
        ..add(root);
      await _open();
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  RemoteFolder get _here => _path.last;

  /// Reads the folders and songs of the folder that is open.
  Future<void> _open() async {
    final req = ++_request;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final kids = await widget.source.folderChildren(parentId: _here.id, limit: 100);
      final songs = await widget.source.songs(folderId: _here.id, limit: 100);
      if (!mounted || req != _request) return;
      setState(() {
        _children = kids.items;
        _songs = songs.items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || req != _request) return;
      setState(() {
        _loading = false;
        _error = friendlyError(e);
      });
    }
  }

  void _into(RemoteFolder f) {
    Haptics.selection();
    _path.add(f);
    _lastOpened = null;
    _open();
  }

  void _up() {
    if (_path.length <= 1) return;
    Haptics.selection();
    _lastOpened = _path.removeLast().id;
    _open();
  }

  Future<void> _playFrom(RemoteSong song) async {
    if (!song.available) return;
    try {
      await widget.source.playSongs([for (final s in _songs) s.id], startSongId: song.id);
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
    if (_loading && _root == null) return const Center(child: CircularProgressIndicator());
    if (_error != null && _root == null) {
      return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)));
    }
    if (_root == null) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No music from files yet.\nAdd songs or a folder first.',
              textAlign: TextAlign.center),
        ),
      );
    }
    final canGoUp = _path.length > 1;
    return Column(
      children: [
        // Where you are, and the way up.
        Material(
          color: theme.colorScheme.surfaceContainerHigh,
          child: SizedBox(
            height: 52,
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Up one folder',
                  icon: const Icon(Icons.arrow_upward_rounded),
                  onPressed: canGoUp ? _up : null,
                ),
                Expanded(
                  child: Text(
                    [for (final f in _path) f.name].join(' › '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textDirection: TextDirection.ltr,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (_songs.isNotEmpty)
                  TextButton.icon(
                    onPressed: () => _playFrom(_songs.firstWhere((s) => s.available, orElse: () => _songs.first)),
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Play'),
                  ),
              ],
            ),
          ),
        ),
        if (_loading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: _error != null
              ? Center(child: Text(_error!))
              : (_children.isEmpty && _songs.isEmpty && !_loading)
                  ? const Center(child: Text('Nothing in this folder.'))
                  : ListView(
                      children: [
                        for (final f in _children)
                          ListTile(
                            minTileHeight: 60,
                            tileColor: _lastOpened == f.id
                                ? theme.colorScheme.primary.withValues(alpha: 0.10)
                                : null,
                            leading: CircleAvatar(
                              child: Icon(f.hasChildren
                                  ? Icons.folder_copy_rounded
                                  : Icons.folder_rounded),
                            ),
                            title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text('${f.songCount} song${f.songCount == 1 ? '' : 's'}'),
                            trailing: const Icon(Icons.chevron_right_rounded),
                            onTap: () => _into(f),
                          ),
                        if (_children.isNotEmpty && _songs.isNotEmpty) const Divider(),
                        for (final s in _songs)
                          ListTile(
                            leading: SongArt(source: widget.source, songId: s.id, radius: 20),
                            title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              s.available ? '${s.artist} · ${s.album}' : 'File missing from the Player',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: SongMenuButton(
                                source: widget.source, songId: s.id, title: s.title),
                            onTap: () => _playFrom(s),
                          ),
                      ],
                    ),
        ),
      ],
    );
  }
}
