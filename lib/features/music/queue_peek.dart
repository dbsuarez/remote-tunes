import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../core/protocol/library_models.dart';
import '../../core/widgets/playback_widgets.dart';
import 'music_source.dart';
import 'song_art.dart';

/// A sheet that rests along the bottom of Now Playing showing what is playing
/// and what comes next, and slides up to show the whole queue. Not a page: the
/// player stays visible behind it.
///
/// Three resting heights: just the song playing, the song and the next three,
/// and nearly the whole screen. Tap a row to jump to it.
///
/// Shows nothing if the queue is empty or cannot be read.
class QueuePeekSheet extends StatefulWidget {
  const QueuePeekSheet({
    super.key,
    required this.source,
    required this.revision,
    required this.currentIndex,
    this.enabled = true,
    this.controller,
  });

  /// Lets the screen open or close the sheet (e.g. from an edge swipe).
  final DraggableScrollableController? controller;

  final MusicSource source;

  /// Changes whenever the queue does, so it is read again.
  final int revision;

  /// Position of the current song in the queue.
  final int currentIndex;
  final bool enabled;

  /// The resting sheet is just its handle: this many pixels tall.
  static const double handleHeight = 30;

  /// Heights when slid up, as a fraction of the space it sits in.
  static const double midSize = 0.46;
  static const double fullSize = 0.88;

  @override
  State<QueuePeekSheet> createState() => _QueuePeekSheetState();
}

class _QueuePeekSheetState extends State<QueuePeekSheet> {
  List<RemoteQueueItem> _items = const [];
  int _loadGeneration = 0;
  final DraggableScrollableController _own = DraggableScrollableController();

  DraggableScrollableController get _controller => widget.controller ?? _own;

  @override
  void dispose() {
    _own.dispose();
    super.dispose();
  }

  /// Tapping the handle slides the queue up (and back down when it is up).
  void _toggle() {
    if (!_controller.isAttached) return;
    final up = _controller.size > QueuePeekSheet.midSize - 0.05;
    _controller.animateTo(
      up ? _controller.pixelsToSize(QueuePeekSheet.handleHeight) : QueuePeekSheet.midSize,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(QueuePeekSheet old) {
    super.didUpdateWidget(old);
    if (old.revision != widget.revision || (!old.enabled && widget.enabled)) _load();
  }

  Future<void> _load() async {
    final gen = ++_loadGeneration;
    try {
      final snap = await widget.source.loadQueue();
      if (!mounted || gen != _loadGeneration) return;
      setState(() => _items = snap.items);
    } catch (_) {
      // No queue to show right now: the sheet just stays out of the way.
      if (!mounted || gen != _loadGeneration) return;
      setState(() => _items = const []);
    }
  }

  Future<void> _play(RemoteQueueItem item) async {
    Haptics.selection();
    try {
      await widget.source.playQueueItem(item.queueItemId);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final cur = widget.currentIndex.clamp(0, _items.length - 1);
    // The song playing first, then what comes after it.
    final upcoming = _items.sublist(cur);

    return IgnorePointer(
      ignoring: !widget.enabled,
      child: LayoutBuilder(builder: (context, box) {
        // Resting height = the handle only.
        final rest = (QueuePeekSheet.handleHeight / box.maxHeight).clamp(0.01, 0.3);
        return DraggableScrollableSheet(
        controller: _controller,
        initialChildSize: rest,
        minChildSize: rest,
        maxChildSize: QueuePeekSheet.fullSize,
        snap: true,
        snapSizes: const [QueuePeekSheet.midSize],
        builder: (context, controller) {
          return DecoratedBox(
            decoration: BoxDecoration(
              // Partly see-through, so the player is still there behind it.
              color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.95),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border(
                top: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.55)),
              ),
              boxShadow: const [
                BoxShadow(color: Color(0x66000000), blurRadius: 18, offset: Offset(0, -4)),
              ],
            ),
            child: ListView.builder(
              controller: controller,
              padding: EdgeInsets.zero,
              itemCount: upcoming.length + 1,
              itemBuilder: (context, i) {
                if (i == 0) {
                  return _Header(
                    count: _items.length,
                    remaining: upcoming.length - 1,
                    onTapHandle: _toggle,
                  );
                }
                final item = upcoming[i - 1];
                return _Row(
                  source: widget.source,
                  item: item,
                  isCurrent: i == 1,
                  onTap: () => _play(item),
                );
              },
            ),
          );
        },
        );
      }),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.count, required this.remaining, required this.onTapHandle});

  final int count;
  final int remaining;
  final VoidCallback onTapHandle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // The handle: all that shows until the sheet is slid up. Tap or drag it.
        InkWell(
          onTap: onTapHandle,
          child: SizedBox(
            height: QueuePeekSheet.handleHeight,
            width: double.infinity,
            child: Center(
              child: Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Row(
            children: [
              Text('Up next', style: theme.textTheme.titleSmall),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  remaining <= 0 ? 'Last song' : '$remaining more · $count in queue',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.source,
    required this.item,
    required this.isCurrent,
    required this.onTap,
  });

  final MusicSource source;
  final RemoteQueueItem item;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final song = item.song;
    return ListTile(
      dense: true,
      minTileHeight: 56,
      selected: isCurrent,
      onTap: onTap,
      leading: SongArt(
        source: source,
        songId: song.id,
        radius: 18,
        overlayIcon: isCurrent ? Icons.graphic_eq_rounded : null,
      ),
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        song.available ? '${song.artist} · ${song.album}' : 'File missing from the Player',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: song.durationSeconds > 0
          ? Text(formatDuration(song.durationSeconds), style: theme.textTheme.bodySmall)
          : null,
    );
  }
}
