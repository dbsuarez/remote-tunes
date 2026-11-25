import 'package:flutter/material.dart';

import 'music_source.dart';
import 'playlist_picker.dart';

/// Every song id of a group (an artist, an album, a genre, a year, an album artist
/// or a composer), up to what one command can carry.
Future<List<int>> songIdsOf(
  MusicSource source, {
  String? artist,
  String? album,
  String? groupKind,
  String? groupValue,
}) async {
  final ids = <int>[];
  var offset = 0;
  while (ids.length < 2000) {
    final page = await source.songs(
      artist: artist,
      album: album,
      groupKind: groupKind,
      groupValue: groupValue,
      offset: offset,
      limit: 100,
    );
    ids.addAll([for (final s in page.items) s.id]);
    offset += page.items.length;
    if (!page.hasMore || page.items.isEmpty) break;
  }
  return ids;
}

void _say(ScaffoldMessengerState messenger, String text) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));
}

enum _Do { play, playNext, queue, playlist }

/// The little menu on a row of songs (in search, in the folder tree): play next, add to
/// the queue, add to a playlist.
class SongMenuButton extends StatelessWidget {
  const SongMenuButton({super.key, required this.source, required this.songId, this.title = ''});

  final MusicSource source;
  final int songId;

  /// For the button's label.
  final String title;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_Do>(
      tooltip: title.isEmpty ? 'More' : 'More for $title',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (d) async {
        final messenger = ScaffoldMessenger.of(context);
        try {
          switch (d) {
            case _Do.playNext:
              await source.queueSongs([songId], playNext: true);
              _say(messenger, 'Will play next');
            case _Do.queue:
              await source.queueSongs([songId]);
              _say(messenger, 'Added to queue');
            case _Do.playlist:
              if (!context.mounted) return;
              await addSongsToPlaylistFlow(context, source, [songId]);
            case _Do.play:
              await source.playSongs([songId], keepQueue: true);
          }
        } catch (e) {
          _say(messenger, friendlyError(e));
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: _Do.playNext, child: Text('Play next')),
        PopupMenuItem(value: _Do.queue, child: Text('Add to queue')),
        PopupMenuItem(value: _Do.playlist, child: Text('Add to playlist')),
      ],
    );
  }
}

/// The little menu on a row that stands for several songs (an album, an artist, a genre...):
/// play them, add them to the queue, add them to a playlist.
class GroupMenuButton extends StatelessWidget {
  const GroupMenuButton({
    super.key,
    required this.source,
    required this.name,
    required this.loadIds,
  });

  final MusicSource source;
  final String name;
  final Future<List<int>> Function() loadIds;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_Do>(
      tooltip: 'More for $name',
      icon: const Icon(Icons.more_vert_rounded),
      onSelected: (d) async {
        final messenger = ScaffoldMessenger.of(context);
        try {
          final ids = await loadIds();
          if (ids.isEmpty) {
            _say(messenger, 'There are no songs in it.');
            return;
          }
          switch (d) {
            case _Do.play:
              await source.playSongs(ids);
            case _Do.queue:
              await source.queueSongs(ids);
              _say(messenger, 'Added ${ids.length} song${ids.length == 1 ? '' : 's'} to the queue');
            case _Do.playlist:
              if (!context.mounted) return;
              await addSongsToPlaylistFlow(context, source, ids);
            case _Do.playNext:
              await source.queueSongs(ids, playNext: true);
              _say(messenger, 'Will play next');
          }
        } catch (e) {
          _say(messenger, friendlyError(e));
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem(value: _Do.play, child: Text('Play')),
        PopupMenuItem(value: _Do.queue, child: Text('Add to queue')),
        PopupMenuItem(value: _Do.playlist, child: Text('Add to playlist')),
      ],
    );
  }
}
