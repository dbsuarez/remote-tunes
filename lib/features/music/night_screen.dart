import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/screen_awake.dart';
import '../../core/session/playback_session.dart';

/// A nearly black screen for a dark room while music plays: the time, the song, what is left of the
/// sleep timer, and (after a tap) the play buttons. The screen stays on and as dim as the phone allows.
class MusicNightScreen extends StatefulWidget {
  const MusicNightScreen({super.key, required this.session, this.now});

  /// The player as it is now (a new one each time something changes).
  final ValueListenable<PlaybackSession> session;
  final DateTime Function()? now;

  @override
  State<MusicNightScreen> createState() => _MusicNightScreenState();
}

class _MusicNightScreenState extends State<MusicNightScreen> {
  static const _dim = Color(0x55FFFFFF);

  final _leaving = Completer<void>();
  Timer? _clock;
  Timer? _hide;
  bool _buttons = false;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    unawaited(ScreenAwake.during(() => _leaving.future));
    unawaited(ScreenDim.set(0.01));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
  }

  @override
  void dispose() {
    _clock?.cancel();
    _hide?.cancel();
    _leaving.complete();
    unawaited(ScreenDim.set(null));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  /// Shows the buttons for a few seconds.
  void _wake() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _buttons = false);
    });
    setState(() => _buttons = true);
  }

  Future<void> _do(Future<void> Function() action) async {
    _wake();
    try {
      await action();
    } catch (_) {
      // Nothing to show on a dark screen; Now Playing says why.
    }
  }

  Widget _button(String key, String tip, IconData icon, VoidCallback? onPressed, {double size = 36}) => IconButton(
        key: Key(key),
        tooltip: tip,
        color: _dim,
        iconSize: size,
        icon: Icon(icon),
        onPressed: onPressed,
      );

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay.fromDateTime((widget.now ?? DateTime.now)()).format(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        key: const Key('night-screen'),
        behavior: HitTestBehavior.opaque,
        onTap: _wake,
        child: SafeArea(
          child: Center(
            child: ValueListenableBuilder<PlaybackSession>(
              valueListenable: widget.session,
              builder: (context, session, _) {
                final p = session.state;
                final song = [p.title, if (p.artist.isNotEmpty) p.artist].where((t) => t.isNotEmpty).join(' · ');
                final left = p.sleepTimerSeconds;
                final timer = p.sleepAfterSong
                    ? 'Pauses after this song'
                    : (left > 0 ? 'Sleep timer: ${(left / 60).ceil()} min left' : null);
                final can = session.enabled;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(time, key: const Key('night-time'), style: const TextStyle(color: _dim, fontSize: 64)),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(song.isEmpty ? 'Nothing playing' : song,
                          key: const Key('night-line'),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: _dim)),
                    ),
                    if (timer != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(timer, key: const Key('night-timer'), style: const TextStyle(color: _dim, fontSize: 12)),
                      ),
                    const SizedBox(height: 32),
                    SizedBox(
                      height: 120,
                      child: !_buttons
                          ? const Text('Tap for controls', style: TextStyle(color: Color(0x22FFFFFF), fontSize: 12))
                          : Column(
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    _button('night-previous', 'Previous', Icons.skip_previous_rounded,
                                        can ? () => _do(session.previous) : null),
                                    const SizedBox(width: 24),
                                    _button('night-play', p.isPlaying ? 'Pause' : 'Play',
                                        p.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                        can ? () => _do(session.toggle) : null,
                                        size: 44),
                                    const SizedBox(width: 24),
                                    _button('night-next', 'Next', Icons.skip_next_rounded,
                                        can ? () => _do(session.next) : null),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                _button('night-leave', 'Leave the night screen', Icons.close_rounded,
                                    () => Navigator.of(context).pop(),
                                    size: 28),
                              ],
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
