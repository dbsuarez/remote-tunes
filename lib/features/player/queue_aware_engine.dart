import '../../core/models/enums.dart';
import '../../core/protocol/library_models.dart';
import 'playback_engine.dart';
import 'queue/playable_song.dart';

/// A [PlaybackEngine] with a managed queue (Phase 2). The Phase 1 simulated
/// engine is not queue-aware, so the server checks for this interface before
/// accepting queue commands.
abstract class QueueAwareEngine implements PlaybackEngine {
  /// Replaces the queue and starts playing [songs] at [startIndex].
  Future<void> playSongs(List<PlayableSong> songs, {int startIndex = 0});

  /// Plays an internet audio URL now, replacing the queue. Throws a
  /// [PlaybackException] with a plain-language reason if the link can't work.
  Future<void> playUrl(String url, {String? title});

  /// Appends songs (or inserts them after the current one). Does not start
  /// playback.
  Future<void> enqueue(List<PlayableSong> songs, {bool playNext = false});

  Future<void> removeQueueItem(int queueItemId);
  Future<void> moveQueueItem(int queueItemId, int newIndex);
  Future<void> clearQueue();
  Future<void> playQueueItem(int queueItemId);
  Future<void> setRepeatMode(RepeatMode mode);
  Future<void> setShuffle(bool enabled);

  QueueSnapshot queueSnapshot();
}
