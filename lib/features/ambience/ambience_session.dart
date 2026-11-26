import 'dart:async';

import '../player/audio/player_audio_handler.dart';
import '../player/playback_engine.dart';
import 'ambience_controller.dart';

/// What the notification says under "RemoteTunes Ambience".
String ambienceSubtitle(AmbienceController ambience) {
  final s = ambience.state;
  final count = s.active.length;
  final left = s.secondsLeft;
  return [
    s.mixName ?? '$count sound${count == 1 ? '' : 's'}',
    if (!s.playing) 'paused' else if (left != null) '${(left / 60).ceil()} min left',
  ].join(' · ');
}

/// Joins ambience to the rest of the Player: music starting stops it, and while it plays (or is paused)
/// the notification and headset buttons are its own. Returns a function that undoes this.
void Function() connectAmbience(AmbienceController ambience, PlaybackEngine music, RemoteTunesAudioHandler? handler) {
  var wasPlaying = music.state.isPlaying;
  final sub = music.states.listen((s) {
    // Only the moment music begins: ambience pauses it on its own way in.
    if (s.isPlaying && !wasPlaying) unawaited(ambience.musicStarted());
    wasPlaying = s.isPlaying;
  });

  String? shown;
  void show() {
    if (handler == null) return;
    final next = ambience.holding ? '${ambience.state.playing}|${ambienceSubtitle(ambience)}' : null;
    if (next == shown) return;
    shown = next;
    handler.ambience = next == null
        ? null
        : AmbienceNotice(
            subtitle: ambienceSubtitle(ambience),
            playing: ambience.state.playing,
            play: ambience.play,
            pause: ambience.pause,
            stop: ambience.stop,
          );
  }

  ambience.addListener(show);
  return () {
    sub.cancel();
    ambience.removeListener(show);
  };
}
