import 'dart:async';

import '../../core/protocol/protocol.dart';

/// Thrown by an engine when a command cannot be carried out. [code] is one of
/// the protocol [ErrorCodes].
class PlaybackException implements Exception {
  PlaybackException(this.code, this.message);
  final String code;
  final String message;

  @override
  String toString() => 'PlaybackException($code): $message';
}

/// The Player's audio engine. Phase 1 ships only [SimulatedPlaybackEngine];
/// Phase 2 adds a just_audio implementation behind this interface.
abstract class PlaybackEngine {
  PlaybackState get state;
  Stream<PlaybackState> get states;

  Future<void> play();
  Future<void> pause();
  Future<void> toggle();
  Future<void> next();
  Future<void> previous();
  Future<void> stop();
  Future<void> seek(int positionSeconds);

  /// 0.0–1.0
  Future<void> setVolume(double volume);
  Future<void> dispose();
}

class _Track {
  const _Track(this.title, this.artist, this.durationSeconds);
  final String title;
  final String artist;
  final int durationSeconds;
}

/// A silent, in-memory stand-in: three demo tracks and a ticking position.
/// Lets the full remote-control loop be verified before real audio (Phase 2).
class SimulatedPlaybackEngine implements PlaybackEngine {
  SimulatedPlaybackEngine({double initialVolume = 0.8, bool autoTick = true}) {
    _state = _build(0, 0, false, initialVolume.clamp(0.0, 1.0));
    if (autoTick) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
    }
  }

  static const _tracks = [
    _Track('Demo Track 1', 'RemoteTunes Demo', 180),
    _Track('Demo Track 2', 'RemoteTunes Demo', 210),
    _Track('Demo Track 3', 'RemoteTunes Demo', 150),
  ];

  late PlaybackState _state;
  Timer? _timer;
  final StreamController<PlaybackState> _controller =
      StreamController<PlaybackState>.broadcast();

  PlaybackState _build(int index, int position, bool playing, double volume) {
    final t = _tracks[index];
    return PlaybackState(
      title: t.title,
      artist: t.artist,
      positionSeconds: position,
      durationSeconds: t.durationSeconds,
      isPlaying: playing,
      queueIndex: index,
      queueLength: _tracks.length,
      volume: volume,
      source: 'simulated',
    );
  }

  @override
  PlaybackState get state => _state;

  @override
  Stream<PlaybackState> get states => _controller.stream;

  void _set(PlaybackState s) {
    _state = s;
    if (!_controller.isClosed) _controller.add(s);
  }

  void _tick() {
    if (!_state.isPlaying) return;
    final pos = _state.positionSeconds + 1;
    if (pos >= _state.durationSeconds) {
      _set(_build((_state.queueIndex + 1) % _tracks.length, 0, true, _state.volume));
    } else {
      _set(_state.copyWith(positionSeconds: pos));
    }
  }

  /// Advances the simulated clock by one second (for tests).
  void tickForTest() => _tick();

  @override
  Future<void> play() async => _set(_state.copyWith(isPlaying: true));

  @override
  Future<void> pause() async => _set(_state.copyWith(isPlaying: false));

  @override
  Future<void> toggle() async =>
      _set(_state.copyWith(isPlaying: !_state.isPlaying));

  @override
  Future<void> next() async => _set(_build(
      (_state.queueIndex + 1) % _tracks.length, 0, _state.isPlaying, _state.volume));

  @override
  Future<void> previous() async {
    // Like most players: restart the track if it has played a few seconds.
    if (_state.positionSeconds > 3) {
      _set(_state.copyWith(positionSeconds: 0));
      return;
    }
    final prev = (_state.queueIndex - 1 + _tracks.length) % _tracks.length;
    _set(_build(prev, 0, _state.isPlaying, _state.volume));
  }

  @override
  Future<void> stop() async =>
      _set(_state.copyWith(isPlaying: false, positionSeconds: 0));

  @override
  Future<void> seek(int positionSeconds) async {
    if (positionSeconds < 0 || positionSeconds > _state.durationSeconds) {
      throw PlaybackException(
        ErrorCodes.invalidPosition,
        'That position is outside the track (0–${_state.durationSeconds}s).',
      );
    }
    _set(_state.copyWith(positionSeconds: positionSeconds));
  }

  @override
  Future<void> setVolume(double volume) async {
    if (volume.isNaN || volume < 0 || volume > 1) {
      throw PlaybackException(
        ErrorCodes.invalidAction,
        'Volume must be between 0 and 1.',
      );
    }
    _set(_state.copyWith(volume: volume));
  }

  @override
  Future<void> dispose() async {
    _timer?.cancel();
    await _controller.close();
  }
}
