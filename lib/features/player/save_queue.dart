import '../../core/protocol/library_models.dart';
import '../../core/protocol/protocol.dart';
import 'playback_engine.dart';

/// What saving the queue as a playlist did.
class SavedQueue {
  const SavedQueue({required this.playlistId, required this.added, required this.skipped});

  final int playlistId;

  /// Songs in the new playlist (a song queued twice is listed once).
  final int added;

  /// Internet tracks left out: a playlist holds library songs only.
  final int skipped;
}

/// Turns the queue into a new playlist, in queue order. Library songs only;
/// internet tracks (Jamendo, links) are counted and left out. If the playlist
/// cannot be filled it is removed again, so no empty playlist is left behind.
Future<SavedQueue> saveQueueAsPlaylist({
  required QueueSnapshot queue,
  required String name,
  required Future<int> Function(String name) createPlaylist,
  required Future<int?> Function(int playlistId, List<int> songIds) addToPlaylist,
  required Future<bool> Function(int playlistId) deletePlaylist,
}) async {
  final ids = [
    for (final i in queue.items)
      if (i.song.id > 0) i.song.id, // internet tracks have id 0
  ];
  final skipped = queue.items.length - ids.length;
  if (ids.isEmpty) {
    throw PlaybackException(
      ErrorCodes.invalidAction,
      queue.items.isEmpty
          ? 'The queue is empty, so there is nothing to save.'
          : 'The queue has only internet tracks. A playlist holds songs from '
              'your library.',
    );
  }
  // Checks the name too (empty, too long) before anything is changed.
  final playlistId = await createPlaylist(name);
  try {
    final added = await addToPlaylist(playlistId, ids);
    if (added == null) {
      throw PlaybackException(
          ErrorCodes.invalidAction, "The playlist couldn't be filled.");
    }
    return SavedQueue(playlistId: playlistId, added: added, skipped: skipped);
  } catch (_) {
    await deletePlaylist(playlistId);
    rethrow;
  }
}
