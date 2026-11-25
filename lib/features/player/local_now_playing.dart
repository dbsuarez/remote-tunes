import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/protocol/protocol.dart';
import '../music/now_playing_view.dart';
import 'local_session.dart';
import 'queue_aware_engine.dart';
import 'server/player_library.dart';
import 'sleep_timer.dart';

/// Now Playing for this phone's own music. It draws again whenever the song,
/// the sleep timer or a favorite changes.
class LocalNowPlaying extends StatefulWidget {
  const LocalNowPlaying({
    super.key,
    required this.engine,
    required this.library,
    required this.sleepTimer,
    this.header,
    this.extras,
    this.onOpenLibrary,
    this.lyricsRequests,
  });

  final Listenable? lyricsRequests;
  final QueueAwareEngine engine;
  final PlayerLibrary library;
  final SleepTimerService sleepTimer;
  final Widget? header;
  final Widget? extras;
  final VoidCallback? onOpenLibrary;

  @override
  State<LocalNowPlaying> createState() => _LocalNowPlayingState();
}

class _LocalNowPlayingState extends State<LocalNowPlaying> {
  late PlaybackState _playback = widget.engine.state;
  StreamSubscription<PlaybackState>? _playbackSub;
  StreamSubscription<int>? _sleepSub;

  @override
  void initState() {
    super.initState();
    _listen();
    // Favorites are read once, so the heart is right from the start.
    widget.library.preloadFavorites().then((_) {
      if (mounted) setState(() {});
    }).catchError((Object _) {});
  }

  @override
  void didUpdateWidget(LocalNowPlaying old) {
    super.didUpdateWidget(old);
    if (old.engine != widget.engine || old.sleepTimer != widget.sleepTimer) {
      _playbackSub?.cancel();
      _sleepSub?.cancel();
      _playback = widget.engine.state;
      _listen();
    }
  }

  void _listen() {
    _playbackSub = widget.engine.states.listen((s) {
      if (mounted) setState(() => _playback = s);
    });
    _sleepSub = widget.sleepTimer.changes.listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _playbackSub?.cancel();
    _sleepSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return NowPlayingView(
      session: LocalSession(
        engine: widget.engine,
        library: widget.library,
        sleepTimer: widget.sleepTimer,
        playback: _playback,
        onChanged: () {
          if (mounted) setState(() {});
        },
      ),
      header: widget.header,
      extras: widget.extras,
      onOpenLibrary: widget.onOpenLibrary,
      lyricsRequests: widget.lyricsRequests,
    );
  }
}
