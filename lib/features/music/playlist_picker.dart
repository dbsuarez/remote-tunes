import 'package:flutter/material.dart';

import '../../core/protocol/library_models.dart';
import 'music_source.dart';

/// Asks which playlist (or a new one) to add [ids] to, adds them, and says what
/// happened. Returns true if songs were added to a playlist.
Future<bool> addSongsToPlaylistFlow(
  BuildContext context,
  MusicSource source,
  List<int> ids,
) async {
  if (ids.isEmpty) return false;
  void snack(String text) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  final List<RemotePlaylist> lists;
  try {
    lists = (await source.playlists(limit: 100)).items;
  } catch (e) {
    snack(friendlyError(e));
    return false;
  }
  if (!context.mounted) return false;
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
  if (choice == null || !context.mounted) return false;
  try {
    final int id;
    final String name;
    if (choice == 'new') {
      final n = await _askName(context);
      if (n == null || n.trim().isEmpty) return false;
      id = await source.createPlaylist(n);
      name = n.trim();
    } else {
      final l = choice as RemotePlaylist;
      id = l.id;
      name = l.name;
    }
    final added = await source.addToPlaylist(id, ids);
    snack(added == 0
        ? (ids.length == 1 ? 'Already in "$name"' : 'All of them are already in "$name"')
        : (ids.length == 1
            ? 'Added to "$name"'
            : 'Added $added song${added == 1 ? '' : 's'} to "$name"'));
    return true;
  } catch (e) {
    snack(friendlyError(e));
    return false;
  }
}

Future<String?> _askName(BuildContext context) {
  final c = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('New playlist'),
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
        FilledButton(onPressed: () => Navigator.of(ctx).pop(c.text), child: const Text('Save')),
      ],
    ),
  );
}
