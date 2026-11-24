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
  });

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
  List<RemoteQueueItem> _items = const [];
  bool _loaded = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant QueueView old) {
    super.didUpdateWidget(old);
    if (old.revision != widget.revision || (!old.enabled && widget.enabled)) {
      _load();
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
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final c = TextEditingController(text: 'Queue ${now.day} ${months[now.month - 1]}');
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
            TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.of(ctx).pop(c.text),
                child: const Text('Save')),
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
        ..showSnackBar(SnackBar(content: Text('Saved $songs as "${name.trim()}"$left')));
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
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: widget.shuffle ? 'Shuffle is on' : 'Shuffle is off',
                    isSelected: widget.shuffle,
                    icon: const Icon(Icons.shuffle_rounded),
                    selectedIcon: Icon(Icons.shuffle_on_rounded,
                        color: theme.colorScheme.primary),
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
                        () => widget.source.setRepeat(_nextRepeat(widget.repeat))),
                  ),
                  const Spacer(),
                  Text('${_items.length} in queue',
                      style: theme.textTheme.bodySmall),
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
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }

    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      itemCount: _items.length,
      onReorder: _onReorder,
      itemBuilder: (context, i) {
        final item = _items[i];
        final song = item.song;
        final isCurrent = i == widget.currentIndex;
        return ListTile(
          key: ValueKey(item.queueItemId),
          minTileHeight: 64,
          selected: isCurrent,
          selectedTileColor: theme.colorScheme.primary.withValues(alpha: 0.10),
          leading: SongArt(
            source: widget.source,
            songId: song.id,
            overlayIcon: !song.available
                ? Icons.error_outline_rounded
                : isCurrent
                    ? Icons.graphic_eq_rounded
                    : null,
            overlayColor: !song.available ? theme.colorScheme.error : null,
          ),
          title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(
            song.available ? song.artist : 'File missing from the Player',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          onTap: () => _run(() => widget.source.playQueueItem(item.queueItemId)),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (song.durationSeconds > 0)
                Text(formatDuration(song.durationSeconds),
                    style: theme.textTheme.bodySmall),
              IconButton(
                tooltip: 'Remove from queue',
                icon: const Icon(Icons.close_rounded),
                onPressed: () =>
                    _run(() => widget.source.removeQueueItem(item.queueItemId)),
              ),
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
      },
    );
  }
}
