import 'package:flutter_riverpod/flutter_riverpod.dart';

/// "Start remote playback" is on: this phone lets other phones control it (the
/// Player server runs). Off until the user presses the button (or chooses to
/// start it automatically in Settings).
final remotePlaybackProvider = StateProvider<bool>((ref) => false);

/// The music player is showing (and controlling) another phone's player
/// instead of this phone's own music.
final controlRemoteProvider = StateProvider<bool>((ref) => false);
