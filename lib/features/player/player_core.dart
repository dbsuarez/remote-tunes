import 'audiobook_tracker.dart';
import '../external/control_mode_engine.dart';
import 'audio/player_audio_handler.dart';
import 'eq/equalizer_controller.dart';
import 'queue_playback_engine.dart';
import 'server/player_library.dart';
import 'sleep_timer.dart';

/// What plays this phone's own music, whether or not other phones may control
/// it: the audio engine, the library, the media notification and the sleep
/// timer. The Player server (remote playback) is built on top of it and can be
/// started and stopped without touching the music.
class PlayerCore {
  PlayerCore({
    required this.engine,
    required this.localEngine,
    required this.library,
    required this.sleepTimer,
    required this.equalizer,
    this.audioHandler,
    this.audiobooks,
  });

  /// Which songs are audiobooks and where they were left (null in tests).
  final AudiobookTracker? audiobooks;

  /// The engine everything talks to (RemoteTunes' own player, or another music
  /// app when External App Control is on).
  final ControlModeEngine engine;

  /// RemoteTunes' own player inside [engine].
  final QueuePlaybackEngine localEngine;
  final RepositoryPlayerLibrary library;
  final SleepTimerService sleepTimer;

  /// The equalizer of this phone's own player.
  final EqualizerController equalizer;
  final RemoteTunesAudioHandler? audioHandler;

  Future<void> dispose() async {
    audioHandler?.detach();
    sleepTimer.dispose();
    equalizer.dispose();
    await engine.dispose();
  }
}
