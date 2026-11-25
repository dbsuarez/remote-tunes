import '../../core/haptics.dart';
import 'playlist_picker.dart';
import 'package:flutter/material.dart';

import '../../core/models/enums.dart';
import '../../core/protocol/library_models.dart';
import '../../core/widgets/playback_widgets.dart';
import 'music_source.dart';
import 'song_art.dart';

/// The play queue: tap to jump, drag the handle to reorder, remove entries,
/// clear, shuffle and repeat. Used on both phones through [MusicSource].
class QueueView extends StatefulWidget {
  const QueueView({
    super.key,
    required this.source,
    required this.revision,
    required this.currentIndex,
    required this.shuffle,
    required this.repeat,
    this.enabled = true,
    this.scrollToCurrent = false,
    this.scrollToken = 0,
  });

  /// When [scrollToken] changes (the Queue was opened), scroll to the song
  /// playing, if this is on.
  final bool scrollToCurrent;
  final int scrollToken;

  final MusicSource source;

  /// Changes whenever the queue contents change; triggers a reload.
  final int revision;

  /// Index of the playing entry (from the playback state).
  final int currentIndex;
  final bool shuffle;
  final RepeatMode repeat;
  final bool enabled;

  @override
  State<QueueView> createState() => _QueueViewState();
}

class _QueueViewState extends State<QueueView> {
  /// Every row is this tall, so the song playing can be found without measuring.
  static const _rowHeight = 72.0;

  final ScrollController _scroll = ScrollController();

  /// How many songs were swiped away (part of every row's key).
  int _swipes = 0;

  /// Rows picked with a long-press (queue entry numbers). While some are picked, taps pick
  /// instead of playing, and swiping and dragging are off.
  final Set<int> _selected = {};

  bool get _selecting => _selected.isNotEmpty;

  void _toggleSelected(int queueItemId) => setState(() {
    if (!_selected.remove(queueItemId)) _selected.add(queueItemId);
  });
  bool _scrollPending = false;
  List<RemoteQueueItem> _items = const [];
  bool _loaded = false;
  Object? _error;

  /// The search box above the list (matches title, artist and album).
  bool _searchOpen = false;
  String _query = '';
  final TextEditingController _search = TextEditingController();

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Scrolls so the song playing is in the middle (once the list is there).
  void _scrollToCurrent({int attempts = 6}) {
    if (!mounted) return;
    final index = widget.currentIndex;
    if (index < 0 || index >= _items.length || _query.trim().isNotEmpty) return;
    if (!_scroll.hasClients || !_scroll.position.hasContentDimensions) {
      if (attempts > 0) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _scrollToCurrent(attempts: attempts - 1),
        );
      }
      return;
    }
    final view = _scroll.position.viewportDimension;
    final target = (index * _rowHeight - view / 2 + _rowHeight / 2).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  bool _matches(RemoteQueueItem item) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return true;
    final s = item.song;
    return s.title.toLowerCase().contains(q) ||
        s.artist.toLowerCase().contains(q) ||
        s.album.toLowerCase().contains(q);
  }

  @override
  void initState() {
    super.initState();
    _scrollPending = widget.scrollToCurrent && widget.scrollToken > 0;
    _load();
  }

  @override
  void didUpdateWidget(covariant QueueView old) {
    super.didUpdateWidget(old);
    if (old.revision != widget.revision || (!old.enabled && widget.enabled)) {
      _load();
    }
    if (widget.scrollToCurrent && old.scrollToken != widget.scrollToken) {
      // The Queue was opened: go to the song playing (after the list is drawn).
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
    }
  }

  Future<void> _load() async {
    try {
      final snap = await widget.source.loadQueue();
      if (!mounted) return;
      setState(() {
        _items = snap.items;
        _loaded = true;
        _error = null;
      });
      if (_scrollPending) {
        _scrollPending = false;
        WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToCurrent());
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _loaded = true;
      });
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      _snack(friendlyError(e));
    }
    await _load();
  }

  Future<void> _onReorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;
    final moved = _items[oldIndex];
    // Optimistic: show the new order immediately, then confirm with the Player.
    setState(() {
      final copy = [..._items];
      copy.removeAt(oldIndex);
      copy.insert(newIndex, moved);
      _items = copy;
    });
    await _run(() => widget.source.moveQueueItem(moved.queueItemId, newIndex));
  }

  /// Asks for a name, then saves the queue as a new playlist.
  Future<void> _saveAsPlaylist() async {
    final now = DateTime.now();
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController(
          text: 'Queue ${now.day} ${months[now.month - 1]}',
        );
        c.selection = TextSelection(baseOffset: 0, extentOffset: c.text.length);
        return AlertDialog(
          title: const Text('Save queue as a playlist'),
          content: TextField(
            controller: c,
            autofocus: true,
            maxLength: 60,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(hintText: 'Playlist name'),
            onSubmitted: (v) => Navigator.of(ctx).pop(v),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(c.text),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (name == null || !mounted) return;
    try {
      final r = await widget.source.saveQueueAsPlaylist(name);
      if (!mounted) return;
      final songs = '${r.added} song${r.added == 1 ? '' : 's'}';
      final left = r.skipped == 0
          ? ''
          : ' (${r.skipped} internet track${r.skipped == 1 ? '' : 's'} left out)';
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text('Saved $songs as "${name.trim()}"$left')),
        );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  RepeatMode _nextRepeat(RepeatMode m) => switch (m) {
    RepeatMode.off => RepeatMode.queue,
    RepeatMode.queue => RepeatMode.one,
    RepeatMode.one => RepeatMode.off,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return IgnorePointer(
      ignoring: !widget.enabled,
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.5,
        child: Column(
          children: [
            if (_selecting) _selectionBar(theme),
            if (!_selecting)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: widget.shuffle
                          ? 'Shuffle is on'
                          : 'Shuffle is off',
                      isSelected: widget.shuffle,
                      icon: const Icon(Icons.shuffle_rounded),
                      selectedIcon: Icon(
                        Icons.shuffle_on_rounded,
                        color: theme.colorScheme.primary,
                      ),
                      onPressed: () =>
                          _run(() => widget.source.setShuffle(!widget.shuffle)),
                    ),
                    IconButton(
                      tooltip: 'Repeat: ${widget.repeat.label}',
                      isSelected: widget.repeat != RepeatMode.off,
                      icon: const Icon(Icons.repeat_rounded),
                      selectedIcon: Icon(
                        widget.repeat == RepeatMode.one
                            ? Icons.repeat_one_on_rounded
                            : Icons.repeat_on_rounded,
                        color: theme.colorScheme.primary,
                      ),
                      onPressed: () => _run(
                        () =>
                            widget.source.setRepeat(_nextRepeat(widget.repeat)),
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${_items.length} in queue',
                      style: theme.textTheme.bodySmall,
                    ),
                    IconButton(
                      tooltip: _searchOpen
                          ? 'Close search'
                          : 'Search the queue',
                      isSelected: _searchOpen,
                      icon: const Icon(Icons.search_rounded),
                      selectedIcon: Icon(
                        Icons.search_off_rounded,
                        color: theme.colorScheme.primary,
                      ),
                      onPressed: _items.isEmpty
                          ? null
                          : () => setState(() {
                              _searchOpen = !_searchOpen;
                              if (!_searchOpen) {
                                _search.clear();
                                _query = '';
                              }
                            }),
                    ),
                    IconButton(
                      tooltip: 'Save queue as a playlist',
                      icon: const Icon(Icons.playlist_add_rounded),
                      onPressed: _items.isEmpty ? null : _saveAsPlaylist,
                    ),
                    TextButton(
                      onPressed: _items.isEmpty
                          ? null
                          : () => _run(widget.source.clearQueue),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              ),
            if (_searchOpen)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
                child: TextField(
                  controller: _search,
                  autofocus: true,
                  onChanged: (v) => setState(() => _query = v),
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: 'Search the queue',
                    prefixIcon: const Icon(Icons.search_rounded),
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
                ),
              ),
            Expanded(child: _body(theme)),
          ],
        ),
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(friendlyError(_error!), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _load, child: const Text('Try again')),
            ],
          ),
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'The queue is empty. Add songs from the Library.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }

    final filtering = _query.trim().isNotEmpty;
    if (filtering) {
      final matches = [
        for (var i = 0; i < _items.length; i++)
          if (_matches(_items[i])) i,
      ];
      if (matches.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'No matches in the queue.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }
      // While searching the list is not reorderable (positions would be
      // confusing); tap plays, the cross removes.
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '${matches.length} of ${_items.length}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: matches.length,
              itemBuilder: (context, k) =>
                  _tile(theme, matches[k], draggable: false),
            ),
          ),
        ],
      );
    }

    return ReorderableListView.builder(
      scrollController: _scroll,
      itemExtent: _rowHeight,
      buildDefaultDragHandles: false,
      itemCount: _items.length,
      onReorder: _onReorder,
      itemBuilder: (context, i) => _tile(theme, i, draggable: true),
    );
  }

  /// What the bar offers while rows are picked.
  Widget _selectionBar(ThemeData theme) {
    final n = _selected.length;
    // Only songs of the library can go into a playlist (not links).
    final songIds = [
      for (final i in _items)
        if (_selected.contains(i.queueItemId) && i.song.id > 0) i.song.id,
    ];
    return Material(
      color: theme.colorScheme.secondaryContainer,
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
              child: Text(
                '$n selected',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: 'Select all',
              icon: const Icon(Icons.select_all_rounded),
              onPressed: () => setState(
                () => _selected.addAll([for (final i in _items) i.queueItemId]),
              ),
            ),
            IconButton(
              tooltip: 'Add selected to a playlist',
              icon: const Icon(Icons.playlist_add_rounded),
              onPressed: songIds.isEmpty
                  ? null
                  : () async {
                      if (await addSongsToPlaylistFlow(
                            context,
                            widget.source,
                            songIds,
                          ) &&
                          mounted) {
                        setState(_selected.clear);
                      }
                    },
            ),
            IconButton(
              tooltip: 'Remove selected from the queue',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: _removeSelected,
            ),
          ],
        ),
      ),
    );
  }

  /// Takes every picked song out of the queue (one message says how many).
  Future<void> _removeSelected() async {
    final ids = _selected.toList();
    setState(() {
      _swipes++;
      _selected.clear();
    });
    for (final id in ids) {
      try {
        await widget.source.removeQueueItem(id);
      } catch (e) {
        _snack(friendlyError(e));
        break;
      }
    }
    _snack(
      'Removed ${ids.length} song${ids.length == 1 ? '' : 's'} from the queue',
    );
    await _load();
  }

  /// Takes the song out of the queue (it was swiped away) and offers to put it back where
  /// it was.
  Future<void> _removeWithUndo(RemoteQueueItem item, int index) async {
    final song = item.song;
    // Gone from the screen at once; the Player is told. (A new number in the rows' keys, so a
    // row that has to come back is a fresh one, not the swiped-away one.)
    setState(() {
      _swipes++;
      _items = [..._items]
        ..removeWhere((x) => x.queueItemId == item.queueItemId);
    });
    try {
      await widget.source.removeQueueItem(item.queueItemId);
    } catch (e) {
      _snack(friendlyError(e));
      await _load();
      return;
    }
    if (!mounted) return;
    // A song in the library can be put back (a link from the Online Library cannot).
    final canUndo = song.id > 0;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Removed "${song.title}"'),
          duration: const Duration(seconds: 5),
          action: canUndo
              ? SnackBarAction(
                  label: 'Undo',
                  onPressed: () => _undoRemove(song, index),
                )
              : null,
        ),
      );
    await _load();
  }

  Future<void> _undoRemove(RemoteSong song, int index) async {
    try {
      await widget.source.queueSongs([song.id]);
      // It was added at the end: move it back to its place.
      final snap = await widget.source.loadQueue();
      if (snap.items.isNotEmpty) {
        final added = snap.items.last;
        final target = index.clamp(0, snap.items.length - 1);
        if (added.song.id == song.id && target != snap.items.length - 1) {
          await widget.source.moveQueueItem(added.queueItemId, target);
        }
      }
    } catch (e) {
      _snack(friendlyError(e));
    }
    await _load();
  }

  Widget _tile(ThemeData theme, int i, {required bool draggable}) {
    final item = _items[i];
    // Swipe left to remove (with Undo in the message that follows); swipe right to add to a
    // playlist (the row stays where it is). A link from the Online Library is not a library
    // song, so it cannot go in a playlist: it only swipes left.
    final inLibrary = item.song.id > 0;
    return Dismissible(
      key: ValueKey('swipe-${item.queueItemId}-$_swipes'),
      direction: _selecting
          ? DismissDirection.none
          : (inLibrary
                ? DismissDirection.horizontal
                : DismissDirection.endToStart),
      // Left to right: the playlist.
      background: Container(
        color: theme.colorScheme.primaryContainer,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 24),
        child: Icon(
          Icons.playlist_add_rounded,
          color: theme.colorScheme.onPrimaryContainer,
        ),
      ),
      // Right to left: remove.
      secondaryBackground: Container(
        color: theme.colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(
          Icons.delete_outline_rounded,
          color: theme.colorScheme.onErrorContainer,
        ),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          // Ask which playlist; the row never leaves.
          await addSongsToPlaylistFlow(context, widget.source, [item.song.id]);
          return false;
        }
        return true;
      },
      onDismissed: (_) => _removeWithUndo(item, i),
      child: _row(theme, i, draggable: draggable),
    );
  }

  Widget _row(ThemeData theme, int i, {required bool draggable}) {
    final item = _items[i];
    final song = item.song;
    final isCurrent = i == widget.currentIndex;
    return ListTile(
      key: ValueKey(item.queueItemId),
      minTileHeight: 64,
      selected: isCurrent || _selected.contains(item.queueItemId),
      selectedTileColor: theme.colorScheme.primary.withValues(
        alpha: _selected.contains(item.queueItemId) ? 0.18 : 0.10,
      ),
      leading: SongArt(
        source: widget.source,
        songId: song.id,
        overlayIcon: _selected.contains(item.queueItemId)
            ? Icons.check_rounded
            : !song.available
            ? Icons.error_outline_rounded
            : isCurrent
            ? Icons.graphic_eq_rounded
            : null,
        overlayColor: !song.available ? theme.colorScheme.error : null,
      ),
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        song.available
            ? '${song.artist} · ${song.album}'
            : 'File missing from the Player',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _selecting
          ? _toggleSelected(item.queueItemId)
          : _run(() => widget.source.playQueueItem(item.queueItemId)),
      onLongPress: () {
        Haptics.medium();
        _toggleSelected(item.queueItemId);
      },
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (song.durationSeconds > 0)
            Text(
              formatDuration(song.durationSeconds),
              style: theme.textTheme.bodySmall,
            ),
          if (draggable && !_selecting)
            ReorderableDragStartListener(
              index: i,
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Icon(Icons.drag_handle_rounded),
              ),
            ),
        ],
      ),
    );
  }
}
