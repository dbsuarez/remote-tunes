import 'dart:async';
import 'dart:math' as math;

import '../eq/eq_model.dart';
import 'audio_backend.dart';

/// Two audio players behind one [AudioBackend], so a song can fade out while the
/// next one fades in.
///
/// Everything normal (load, play, seek, volume...) goes to the player that is
/// audible. [crossfadeTo] starts the next song on the other player at zero
/// volume, ramps one down and the other up (equal power, so the loudness stays
/// even), and then swaps their roles.
class CrossfadeBackend implements AudioBackend {
  CrossfadeBackend(this._a, this._b, {this.tick = const Duration(milliseconds: 40)}) {
    _active = _a;
    _wire(_a);
    _wire(_b);
  }

  final AudioBackend _a;
  final AudioBackend _b;

  /// How often the volumes are moved while fading.
  final Duration tick;

  late AudioBackend _active;
  AudioBackend get _other => identical(_active, _a) ? _b : _a;

  double _volume = 1.0;
  double _speed = 1.0;

  /// How far the fade has gone (0 to 1); 0 when no fade is running.
  double _t = 0;
  Timer? _ramp;
  Completer<bool>? _fade;
  String? _pendingPath;
  bool _activePlaying = false;

  final _position = StreamController<Duration>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _completed = StreamController<void>.broadcast();
  final _duration = StreamController<Duration?>.broadcast();
  final _errors = StreamController<String>.broadcast();
  final _advanced = StreamController<String?>.broadcast();
  final _lastDuration = <AudioBackend, Duration?>{};
  final _subs = <StreamSubscription<dynamic>>[];

  /// Only what the audible player says is passed on.
  void _wire(AudioBackend b) {
    _subs.addAll([
      b.positionStream.listen((d) {
        if (identical(b, _active)) _position.add(d);
      }),
      b.playingStream.listen((p) {
        if (identical(b, _active)) {
          _activePlaying = p;
          _playing.add(p);
        }
      }),
      b.completedStream.listen((_) {
        if (!identical(b, _active)) return;
        final fade = _fade;
        final inc = _other;
        if (fade != null) {
          // The song ran out during the fade: the next one takes over (while the
          // next is still loading, the fade starts as soon as it is ready).
          if (_ramp != null) {
            _ramp?.cancel();
            _finishFade(inc, _pendingPath ?? '');
          }
          return;
        }
        _completed.add(null);
      }),
      b.durationStream.listen((d) {
        _lastDuration[b] = d;
        if (identical(b, _active)) _duration.add(d);
      }),
      b.errorStream.listen((e) {
        if (identical(b, _active)) _errors.add(e);
      }),
      b.advancedStream.listen((p) {
        if (identical(b, _active)) _advanced.add(p);
      }),
    ]);
  }

  @override
  bool get supportsCrossfade => true;

  @override
  Stream<Duration> get positionStream => _position.stream;
  @override
  Duration get position => _active.position;
  @override
  Stream<bool> get playingStream => _playing.stream;
  @override
  Stream<void> get completedStream => _completed.stream;
  @override
  Stream<Duration?> get durationStream => _duration.stream;
  @override
  Stream<String> get errorStream => _errors.stream;
  @override
  Stream<String?> get advancedStream => _advanced.stream;

  /// Stops a fade in progress and puts the audible player back to full volume.
  Future<void> _cancelFade() async {
    _ramp?.cancel();
    _ramp = null;
    final fade = _fade;
    _fade = null;
    _t = 0;
    if (fade != null) {
      await _other.pause();
      await _active.setVolume(_volume);
      if (!fade.isCompleted) fade.complete(false);
    }
  }

  Future<void> _prepareNewTrack() async {
    await _cancelFade();
    await _other.pause();
    await _other.setVolume(0);
    await _active.setVolume(_volume);
  }

  @override
  Future<Duration?> load(String filePath) async {
    await _prepareNewTrack();
    return _active.load(filePath);
  }

  @override
  Future<Duration?> loadUrl(String url) async {
    await _prepareNewTrack();
    return _active.loadUrl(url);
  }

  @override
  Future<void> play() async {
    await _active.play();
    if (_fade != null) await _other.play();
  }

  @override
  Future<void> pause() async {
    await _active.pause();
    if (_fade != null) await _other.pause();
  }

  @override
  Future<void> seek(Duration position) async {
    // Jumping in the song ends a fade (the song fades in no more).
    if (_fade != null) await _cancelFade();
    await _active.seek(position);
  }

  @override
  Future<void> setVolume(double volume) async {
    _volume = volume.clamp(0.0, 1.0);
    await _applyVolumes();
  }

  Future<void> _applyVolumes() async {
    if (_fade == null) {
      await _active.setVolume(_volume);
      return;
    }
    // Equal power: the two together stay as loud as one.
    final out = math.cos(_t * math.pi / 2);
    final into = math.sin(_t * math.pi / 2);
    await _active.setVolume(_volume * out);
    await _other.setVolume(_volume * into);
  }

  @override
  Future<void> setSpeed(double speed) async {
    _speed = speed;
    await _a.setSpeed(speed);
    await _b.setSpeed(speed);
  }

  @override
  Future<void> setNext(String? filePath) => _active.setNext(filePath);

  @override
  Future<EqBands?> equalizerBands() => _a.equalizerBands();

  @override
  Future<void> setEqualizer({required bool enabled, required List<double> gains}) async {
    await _a.setEqualizer(enabled: enabled, gains: gains);
    await _b.setEqualizer(enabled: enabled, gains: gains);
  }

  @override
  Future<void> setPreamp(double db) async {
    await _a.setPreamp(db);
    await _b.setPreamp(db);
  }

  @override
  Future<bool> crossfadeTo(String filePath, Duration length) async {
    if (_fade != null || length <= Duration.zero) return false;
    final incoming = _other;
    final done = Completer<bool>();
    // Claimed straight away, so nothing else starts a fade while this one loads.
    _fade = done;
    _pendingPath = filePath;
    _t = 0;
    try {
      await incoming.load(filePath);
    } on AudioBackendException {
      if (identical(_fade, done)) _fade = null;
      if (!done.isCompleted) done.complete(false);
      return false;
    }
    // The first load of the other player can be slow (it is cold). If the fade
    // was cancelled meanwhile (a skip, a seek), leave it.
    if (!identical(_fade, done)) {
      await incoming.pause();
      return false;
    }
    await incoming.setVolume(0);
    await incoming.setSpeed(_speed);

    // Time the fade to the end of the song playing: wait if there is time to
    // spare (the next song is already loaded, so it starts at once), shorten the
    // fade if the load took too long.
    var fadeLength = length;
    final total = _lastDuration[_active];
    if (total != null && total > Duration.zero) {
      final remaining = total - _active.position;
      if (remaining > length + const Duration(milliseconds: 80)) {
        await Future<void>.delayed(remaining - length);
        if (!identical(_fade, done)) {
          await incoming.pause();
          return false;
        }
      } else if (remaining < length) {
        fadeLength = remaining > const Duration(milliseconds: 200)
            ? remaining
            : const Duration(milliseconds: 200);
      }
    }
    await incoming.play();

    final step = tick.inMilliseconds / fadeLength.inMilliseconds;
    _ramp = Timer.periodic(tick, (timer) async {
      // While paused the fade waits where it is.
      if (!_activePlaying) return;
      _t = math.min(1.0, _t + step);
      if (_t >= 1.0) {
        timer.cancel();
        await _finishFade(incoming, filePath);
      } else {
        await _applyVolumes();
      }
    });
    return done.future;
  }

  Future<void> _finishFade(AudioBackend incoming, String filePath) async {
    final fade = _fade;
    if (fade == null) return;
    final outgoing = _active;
    _active = incoming;
    _fade = null;
    _ramp = null;
    _t = 0;
    await outgoing.pause();
    await outgoing.setVolume(0);
    await incoming.setVolume(_volume);
    _activePlaying = true;
    _playing.add(true);
    final d = _lastDuration[incoming];
    if (d != null) _duration.add(d);
    _advanced.add(filePath);
    if (!fade.isCompleted) fade.complete(true);
  }

  @override
  Future<void> dispose() async {
    _ramp?.cancel();
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _a.dispose();
    await _b.dispose();
    for (final c in [_position, _playing, _completed, _duration, _errors, _advanced]) {
      await c.close();
    }
  }
}
