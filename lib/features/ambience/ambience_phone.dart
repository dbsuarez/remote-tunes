/// The playing phone's side of Ambience Mode: the SoLoud engine, the sound files and the settings.
/// Phone only (files and native audio).
library;

import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:audio_session/audio_session.dart';
import 'package:flutter_soloud/flutter_soloud.dart';
import 'package:path/path.dart' as p;

import '../../data/repositories/settings_repository.dart';
import 'ambience_beats.dart';
import 'ambience_controller.dart';
import 'ambience_noise.dart';

class SoLoudAmbienceEngine implements AmbienceEngine {
  final _voices = <String, ({AudioSource source, SoundHandle handle})>{};
  StreamSubscription<AudioInterruptionEvent>? _interruptions;
  Future<void>? _starting;
  StreamSubscription<void>? _unplugged;
  bool _paused = false;

  /// Called when the sound should be paused properly: headphones pulled out (it must not carry on out
  /// loud), or another player taking over for good.
  Future<void> Function()? onMustPause;
  bool _interrupted = false;

  /// Files bigger than this are read from storage as they play, so a dozen long recordings do not
  /// fill the memory.
  static const _keepInMemory = 1536 * 1024;

  /// Fades each volume change, so sliders do not crackle.
  static const _glide = Duration(milliseconds: 150);

  /// The beats are pure tones: starting or cutting one at once clicks, so they fade in and out.
  static const _beatFade = Duration(milliseconds: 2500);

  /// Voices fading out, to be let go when silent; and the engine, once the last one is.
  final _fading = <String, ({Timer timer, AudioSource source, SoundHandle handle})>{};
  Timer? _release;

  SoLoud get _so => SoLoud.instance;

  Future<void> _ready() => _starting ??= () async {
        try {
          if (!_so.isInitialized) await _so.init();
        } catch (_) {
          _starting = null;
          rethrow;
        }
      }();

  /// Asks Android for the sound, and listens for calls and other apps taking it.
  Future<void> _takeFocus() async {
    try {
      final session = await AudioSession.instance;
      await session.setActive(true);
      _interruptions ??= session.interruptionEventStream.listen((e) {
        // Quiet notification sounds play over it; calls and other players pause it.
        if (e.type == AudioInterruptionType.duck) return;
        if (e.begin && e.type == AudioInterruptionType.unknown) {
          unawaited(onMustPause?.call());
          return;
        }
        _interrupted = e.begin;
        _setAll(e.begin || _paused);
      });
      _unplugged ??= session.becomingNoisyEventStream.listen((_) => unawaited(onMustPause?.call()));
    } catch (_) {
      // Plays without it.
    }
  }

  void _setAll(bool paused) {
    for (final v in _voices.values) {
      if (_so.getIsValidVoiceHandle(v.handle)) _so.setPause(v.handle, paused);
    }
  }

  @override
  Future<void> start(String id, String path, double volume) async {
    _release?.cancel();
    _release = null;
    await _ready();
    await stop(id);
    // The same file must be let go before it is loaded again.
    await _drop(id);
    final long = await File(path).length() > _keepInMemory;
    final source = await _so.loadFile(path, mode: long ? LoadMode.disk : LoadMode.memory);
    await _takeFocus();
    final fade = isAmbienceBeat(id);
    final handle = await _so.play(source, volume: fade ? 0 : volume, looping: true, paused: _paused || _interrupted);
    if (fade) _so.fadeVolume(handle, volume, _beatFade);
    // A sleeping child's sound must not be dropped when many play at once.
    _so.setProtectVoice(handle, true);
    _voices[id] = (source: source, handle: handle);
  }

  @override
  Future<({double rms, double peak})?> measure(String path) async {
    await _ready();
    // Points spread evenly through the whole file are enough to tell how loud it is.
    final samples = await _so.readSamplesFromFile(path, 60000);
    var sum = 0.0, peak = 0.0;
    var n = 0;
    for (final v in samples) {
      if (!v.isFinite) continue;
      sum += v * v;
      if (v.abs() > peak) peak = v.abs();
      n++;
    }
    return n == 0 ? null : (rms: sqrt(sum / n), peak: peak);
  }

  @override
  Future<void> setVolume(String id, double volume) async {
    final v = _voices[id];
    if (v == null || !_so.getIsValidVoiceHandle(v.handle)) return;
    _so.fadeVolume(v.handle, volume, _glide);
  }

  @override
  Future<void> stop(String id) async {
    final v = _voices.remove(id);
    if (v == null) return;
    // Only a voice that is heard needs to fade; a paused one just goes.
    if (isAmbienceBeat(id) && !_paused && !_interrupted && _so.getIsValidVoiceHandle(v.handle)) {
      _so.fadeVolume(v.handle, 0, _beatFade);
      _fading[id] = (timer: Timer(_beatFade, () => unawaited(_drop(id))), source: v.source, handle: v.handle);
      return;
    }
    await _end(v.source, v.handle);
  }

  Future<void> _end(AudioSource source, SoundHandle handle) async {
    try {
      await _so.stop(handle);
      await _so.disposeSource(source);
    } catch (_) {}
  }

  /// Lets a fading voice go now.
  Future<void> _drop(String id) async {
    final v = _fading.remove(id);
    if (v == null) return;
    v.timer.cancel();
    await _end(v.source, v.handle);
  }

  @override
  Future<void> setPaused(bool paused) async {
    _paused = paused;
    if (!paused) {
      _interrupted = false;
      if (_voices.isNotEmpty) await _takeFocus();
    }
    _setAll(paused);
  }

  @override
  Future<void> stopAll() async {
    for (final id in _voices.keys.toList()) {
      await stop(id);
    }
    _paused = false;
    _interrupted = false;
    await _interruptions?.cancel();
    _interruptions = null;
    await _unplugged?.cancel();
    _unplugged = null;
    // The engine is let go, so it uses no battery while silent (after anything fading has faded).
    _release?.cancel();
    _release = null;
    if (_fading.isEmpty) {
      await _letGo();
    } else {
      _release = Timer(_beatFade + const Duration(milliseconds: 100), () => unawaited(_letGo()));
    }
  }

  Future<void> _letGo() async {
    for (final id in _fading.keys.toList()) {
      await _drop(id);
    }
    if (_starting != null) {
      _starting = null;
      try {
        _so.deinit();
      } catch (_) {}
    }
  }
}

/// Copies of the owner's files, and the noise made on first use, in the app's own folder.
class PhoneAmbienceFiles implements AmbienceFiles {
  PhoneAmbienceFiles(this.directory);

  final Future<Directory> Function() directory;

  Future<Directory> _dir() async {
    final d = await directory();
    await d.create(recursive: true);
    return d;
  }

  @override
  Future<String?> pathFor(String soundId, String? saved) async {
    final dir = await _dir();
    if (saved != null) {
      final f = File(p.join(dir.path, saved));
      return await f.exists() ? f.path : null;
    }
    final color = noiseColorOf(soundId);
    if (color != null) return _made(dir, 'noise_${color.name}_1.wav', () => noiseWav(color));
    final beat = ambienceBeats[soundId];
    if (beat != null) return _made(dir, '${soundId}_1.wav', () => beatWav(beat));
    return null;
  }

  /// A file the app makes itself, on first use.
  Future<String> _made(Directory dir, String name, Uint8List Function() make) async {
    final f = File(p.join(dir.path, name));
    if (!await f.exists()) {
      final part = File('${f.path}.part');
      await part.writeAsBytes(await Isolate.run(make), flush: true);
      await part.rename(f.path);
    }
    return f.path;
  }

  @override
  Future<String> add(String soundId, String sourcePath) async {
    final dir = await _dir();
    final ext = p.extension(sourcePath).toLowerCase();
    // A new name each time: the old file may still be playing.
    final name = '${soundId}_${DateTime.now().millisecondsSinceEpoch}$ext';
    await File(sourcePath).copy(p.join(dir.path, name));
    return name;
  }

  @override
  Future<String> write(String name, Uint8List bytes) async {
    final dir = await _dir();
    final saved = '${name}_${DateTime.now().microsecondsSinceEpoch}.png';
    await File(p.join(dir.path, saved)).writeAsBytes(bytes, flush: true);
    return saved;
  }

  @override
  Future<void> remove(String saved) async {
    try {
      await File(p.join((await _dir()).path, saved)).delete();
    } catch (_) {}
  }
}

class SettingsAmbienceStore implements AmbienceStore {
  SettingsAmbienceStore(this.settings);

  final SettingsRepository settings;
  static const _key = 'ambience.v1';

  @override
  Future<String?> read() => settings.readValue(_key);
  @override
  Future<void> write(String value) => settings.writeValue(_key, value);
}
