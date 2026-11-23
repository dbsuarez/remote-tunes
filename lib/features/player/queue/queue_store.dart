import 'playable_song.dart';

/// Where the Player keeps its queue so it survives a restart.
///
/// Only songs from the library are kept. Internet links are one-off and are
/// left out.
abstract class QueueStore {
  /// Replaces the saved queue. [currentIndex] is the position of the current
  /// song within [songs] (clamped on load).
  Future<void> save(List<PlayableSong> songs, int currentIndex);

  Future<({List<PlayableSong> songs, int currentIndex})> load();
}
