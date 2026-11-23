import 'dart:async';

import 'package:remote_tunes/features/external/external_media.dart';

/// Stand-in for the Android side that controls other music apps.
class FakeExternalBridge implements ExternalMediaBridge {
  final _controller = StreamController<ExternalMediaSnapshot>.broadcast();

  /// Calls received, in order (e.g. `start`, `play`, `seekTo:42000`).
  final List<String> calls = [];

  bool accessGranted = true;
  int sdk = 34;
  ExternalMediaSnapshot snapshot = ExternalMediaSnapshot.empty;

  /// Make the next command fail like the real bridge would.
  ExternalMediaException? failWith;

  static ExternalTrack track({
    String package = 'com.spotify.music',
    String label = 'Spotify',
    String title = 'Blue Song',
    String artist = 'The Band',
    String album = 'Blue Album',
    int durationMs = 200000,
    int positionMs = 10000,
    bool isPlaying = true,
    bool canSeek = true,
    bool canNext = true,
    bool canPrevious = true,
  }) =>
      ExternalTrack(
        package: package,
        label: label,
        title: title,
        artist: artist,
        album: album,
        durationMs: durationMs,
        positionMs: positionMs,
        isPlaying: isPlaying,
        canSeek: canSeek,
        canNext: canNext,
        canPrevious: canPrevious,
      );

  /// A snapshot with one playing app.
  static ExternalMediaSnapshot playing({ExternalTrack? t, double volume = 0.5}) =>
      ExternalMediaSnapshot(
        accessGranted: true,
        sessions: [
          ExternalSession(
              package: (t ?? track()).package,
              label: (t ?? track()).label,
              isPlaying: (t ?? track()).isPlaying,
              title: (t ?? track()).title),
        ],
        current: t ?? track(),
        volume: volume,
      );

  /// Pushes a live update, like Android reporting a change.
  void push(ExternalMediaSnapshot s) {
    snapshot = s;
    _controller.add(s);
  }

  @override
  Stream<ExternalMediaSnapshot> get snapshots => _controller.stream;

  @override
  Future<bool> isAccessGranted() async => accessGranted;

  @override
  Future<ExternalMediaSnapshot> start() async {
    calls.add('start');
    return ExternalMediaSnapshot(
      accessGranted: accessGranted,
      sessions: snapshot.sessions,
      current: accessGranted ? snapshot.current : null,
      volume: snapshot.volume,
    );
  }

  @override
  Future<void> stop() async => calls.add('stop');

  @override
  Future<void> openAccessSettings() async => calls.add('openAccessSettings');

  @override
  Future<void> openAppInfo() async => calls.add('openAppInfo');

  @override
  Future<int> sdkInt() async => sdk;

  @override
  Future<void> selectSession(String? package) async =>
      calls.add('select:${package ?? 'auto'}');

  Future<void> _command(String name) async {
    calls.add(name);
    final f = failWith;
    if (f != null) {
      failWith = null;
      throw f;
    }
  }

  @override
  Future<void> play() => _command('play');
  @override
  Future<void> pause() => _command('pause');
  @override
  Future<void> next() => _command('next');
  @override
  Future<void> previous() => _command('previous');
  @override
  Future<void> seekTo(Duration position) =>
      _command('seekTo:${position.inMilliseconds}');
  @override
  Future<void> setVolume(double volume) => _command('volume:$volume');
}
