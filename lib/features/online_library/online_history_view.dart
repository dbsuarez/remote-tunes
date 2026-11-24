import 'package:flutter/material.dart';

import '../../core/protocol/library_models.dart';
import '../music/music_source.dart' show friendlyError;
import 'jamendo_api.dart' show licenseLabelFor;
import 'online_history_source.dart';

/// What was played from the Online Library, kept on the Player. Play again,
/// add to the queue, remove one entry, clear all, or turn recording off.
class OnlineHistoryView extends StatefulWidget {
  const OnlineHistoryView({
    super.key,
    required this.source,
    required this.onBack,
    this.enabled = true,
    this.now,
  });

  final OnlineHistorySource source;
  final VoidCallback onBack;

  /// False while the Controller is reconnecting.
  final bool enabled;

  /// For tests: the current time.
  final DateTime? now;

  @override
  State<OnlineHistoryView> createState() => _OnlineHistoryViewState();
}

class _OnlineHistoryViewState extends State<OnlineHistoryView> {
  final List<RemoteHistoryItem> _items = [];
  int _total = 0;
  bool _recording = true;
  bool _loading = true;
  bool _loadedOnce = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    // The old list stays on screen until the new one arrives (no flicker).
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final r = await widget.source.load(offset: more ? _items.length : 0, limit: 100);
      if (!mounted) return;
      setState(() {
        if (!more) _items.clear();
        _items.addAll(r.page.items);
        _total = r.page.total;
        _recording = r.enabled;
        _loading = false;
        _loadedOnce = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = friendlyError(e);
        _loading = false;
      });
    }
  }

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _play(RemoteHistoryItem item, {required bool queue}) async {
    try {
      await widget.source.play(item, queue: queue);
      _snack(queue ? "Added to the Player's queue" : 'Playing on the Player');
      // Playing it again moves it to the top.
      if (!queue) await _load();
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  Future<void> _remove(RemoteHistoryItem item) async {
    try {
      await widget.source.remove(item);
      if (!mounted) return;
      setState(() {
        _items.removeWhere((e) => e.id == item.id);
        if (_total > 0) _total--;
      });
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear history?'),
        content: const Text(
            'This empties the list on the Player. Nothing else is deleted.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Clear')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.source.clear();
      if (!mounted) return;
      setState(() {
        _items.clear();
        _total = 0;
      });
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  Future<void> _setRecording(bool on) async {
    final before = _recording;
    setState(() => _recording = on);
    try {
      await widget.source.setEnabled(on);
    } catch (e) {
      if (mounted) setState(() => _recording = before);
      _snack(friendlyError(e));
    }
  }

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
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 0),
              child: Row(
                children: [
                  IconButton(
                    tooltip: 'Back to search',
                    icon: const Icon(Icons.arrow_back_rounded),
                    onPressed: widget.onBack,
                  ),
                  Expanded(
                    child: Text('History', style: theme.textTheme.titleMedium),
                  ),
                  TextButton(
                    onPressed: _items.isEmpty ? null : _clear,
                    child: const Text('Clear'),
                  ),
                ],
              ),
            ),
            SwitchListTile(
              dense: true,
              title: const Text('Keep history'),
              subtitle: const Text(
                  'Stored on the Player phone only. Never sent anywhere.'),
              value: _recording,
              onChanged: _setRecording,
            ),
            const Divider(height: 1),
            Expanded(child: _body(theme)),
          ],
        ),
      ),
    );
  }

  Widget _body(ThemeData theme) {
    if (_loading && !_loadedOnce) return const Center(child: CircularProgressIndicator());
    if (_error != null && _items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
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
            _recording
                ? 'Nothing here yet. Tracks you play from the Online Library '
                    'will show up here.'
                : 'History is off, so nothing is being remembered.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    final now = widget.now ?? DateTime.now();
    return ListView.builder(
      itemCount: _items.length + 1,
      itemBuilder: (context, i) {
        if (i < _items.length) {
          final e = _items[i];
          return _HistoryTile(
            item: e,
            when: playedLabel(now, e.playedAtSeconds),
            onPlay: () => _play(e, queue: false),
            onQueue: () => _play(e, queue: true),
            onRemove: () => _remove(e),
          );
        }
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: _loading
                ? const CircularProgressIndicator()
                : _items.length < _total
                    ? OutlinedButton(
                        onPressed: () => _load(more: true), child: const Text('Load more'))
                    : const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}

class _HistoryTile extends StatelessWidget {
  const _HistoryTile({
    required this.item,
    required this.when,
    required this.onPlay,
    required this.onQueue,
    required this.onRemove,
  });

  final RemoteHistoryItem item;
  final String when;
  final VoidCallback onPlay;
  final VoidCallback onQueue;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final art = item.imageUrl;
    final placeholder = Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(Icons.music_note_rounded, color: theme.colorScheme.primary),
    );
    return ListTile(
      minTileHeight: 72,
      onTap: onPlay,
      leading: art == null
          ? placeholder
          : ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                art,
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                cacheWidth: 156,
                errorBuilder: (_, __, ___) => placeholder,
                loadingBuilder: (c, child, p) => p == null ? child : placeholder,
              ),
            ),
      title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${item.artist} · ${item.album}', maxLines: 1, overflow: TextOverflow.ellipsis),
          Text(
            [
              if (when.isNotEmpty) when,
              if (item.licenseUrl != null) licenseLabelFor(item.licenseUrl),
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: muted),
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Play on Player',
            icon: const Icon(Icons.play_circle_fill_rounded),
            onPressed: onPlay,
          ),
          IconButton(
            tooltip: 'Add to queue',
            icon: const Icon(Icons.playlist_add_rounded),
            onPressed: onQueue,
          ),
          PopupMenuButton<bool>(
            tooltip: 'More',
            onSelected: (_) => onRemove(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: true, child: Text('Remove from history')),
            ],
          ),
        ],
      ),
    );
  }
}
