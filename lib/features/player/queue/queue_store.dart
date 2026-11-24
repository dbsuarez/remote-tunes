import 'playable_song.dart';

/// Where the Player keeps its queue so it survives a restart.
///
/// Only songs from the library are kept. Internet links are one-off and are
/// left out.
abstract class QueueStore {
  /// Replaces the saved queue. [currentIndex] is the position of the current
  /// song within [songs] (clamped on load).
  ///
  /// [positionSeconds] is how far into the current song it was, so playing
  /// again carries on from there.
  Future<void> save(List<PlayableSong> songs, int currentIndex,
      {int positionSeconds = 0});

  Future<({List<PlayableSong> songs, int currentIndex, int positionSeconds})> load();
}
