import 'package:flutter/material.dart';

import '../../core/protocol/library_models.dart';
import '../../data/repositories/library_repository.dart';
import 'backup_models.dart';

/// Lets the user say, for each song of a backup that was not found, which song of this library it
/// is. Returns the choices (backup index -> library song id), or null if cancelled.
Future<Map<int, int>?> showMatchByHand(
  BuildContext context, {
  required LibraryRepository library,
  required BackupData data,
  required List<int> indexes,
}) {
  return showDialog<Map<int, int>>(
    context: context,
    builder: (_) => MatchByHandDialog(library: library, data: data, indexes: indexes),
  );
}

class MatchByHandDialog extends StatefulWidget {
  const MatchByHandDialog({
    super.key,
    required this.library,
    required this.data,
    required this.indexes,
  });

  final LibraryRepository library;
  final BackupData data;

  /// The songs of the backup that were not found (indexes into [BackupData.songs]).
  final List<int> indexes;

  @override
  State<MatchByHandDialog> createState() => _MatchByHandDialogState();
}

class _MatchByHandDialogState extends State<MatchByHandDialog> {
  /// backup index -> chosen library song.
  final Map<int, RemoteSong> _picked = {};

  Future<void> _pick(int index) async {
    final song = await showDialog<RemoteSong>(
      context: context,
      builder: (_) => SongPickerDialog(
        library: widget.library,
        // Without a bracketed part like "(Live)", which the library's title may not have.
        initialQuery: widget.data.songs[index].title.replaceAll(RegExp(r'\s*[\(\[].*?[\)\]]'), '').trim(),
      ),
    );
    if (song != null && mounted) setState(() => _picked[index] = song);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Match by hand'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'For each song the backup knew but this phone did not find, pick the song here that it is. '
              'Its playlists, heart and counts then go to that song.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final i in widget.indexes)
                    ListTile(
                      key: ValueKey('hand-$i'),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(widget.data.songs[i].title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        _picked[i] == null
                            ? (widget.data.songs[i].artist.isEmpty ? 'Not matched' : '${widget.data.songs[i].artist} · not matched')
                            : 'is ${_picked[i]!.title} · ${_picked[i]!.artist}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _picked[i] == null ? null : theme.colorScheme.primary),
                      ),
                      trailing: _picked[i] == null
                          ? const Icon(Icons.search_rounded)
                          : IconButton(
                              tooltip: 'Clear',
                              icon: const Icon(Icons.close_rounded),
                              onPressed: () => setState(() => _picked.remove(i)),
                            ),
                      onTap: () => _pick(i),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          key: const Key('hand-apply'),
          onPressed: _picked.isEmpty
              ? null
              : () => Navigator.pop(context, {for (final e in _picked.entries) e.key: e.value.id}),
          child: Text(_picked.isEmpty ? 'Apply' : 'Apply (${_picked.length})'),
        ),
      ],
    );
  }
}

/// Search the library and pick one song.
class SongPickerDialog extends StatefulWidget {
  const SongPickerDialog({super.key, required this.library, this.initialQuery = ''});

  final LibraryRepository library;
  final String initialQuery;

  @override
  State<SongPickerDialog> createState() => _SongPickerDialogState();
}

class _SongPickerDialogState extends State<SongPickerDialog> {
  late final TextEditingController _query = TextEditingController(text: widget.initialQuery);
  List<RemoteSong> _songs = const [];
  bool _loading = true;
  int _token = 0;

  @override
  void initState() {
    super.initState();
    _search();
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final mine = ++_token;
    setState(() => _loading = true);
    final page = await widget.library.songs(query: _query.text.trim(), limit: 30);
    if (!mounted || mine != _token) return;
    setState(() {
      _songs = [for (final s in page.items) s.toRemote(available: true)];
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Which song is it?'),
      content: SizedBox(
        width: double.maxFinite,
        height: 360,
        child: Column(
          children: [
            TextField(
              key: const Key('picker-query'),
              controller: _query,
              autofocus: true,
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search your songs'),
              onChanged: (_) => _search(),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _songs.isEmpty
                      ? const Center(child: Text('No songs found.'))
                      : ListView(
                          children: [
                            for (final s in _songs)
                              ListTile(
                                key: ValueKey('pick-${s.id}'),
                                dense: true,
                                title: Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text('${s.artist} · ${s.album}', maxLines: 1, overflow: TextOverflow.ellipsis),
                                onTap: () => Navigator.pop(context, s),
                              ),
                          ],
                        ),
            ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
    );
  }
}
