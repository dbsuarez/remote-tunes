import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'ambience_import.dart';
import 'ambience_models.dart';

/// Plays looping sounds together (the phone uses SoLoud; tests use a pretend one).
abstract class AmbienceEngine {
  /// Starts [path] looping as the voice [id] at [volume]. Throws if the file cannot be played.
  Future<void> start(String id, String path, double volume);
  Future<void> setVolume(String id, double volume);
  Future<void> stop(String id);
  Future<void> setPaused(bool paused);
  Future<void> stopAll();
}

/// Where the audio files are: copies the owner added, and the noise the app makes.
abstract class AmbienceFiles {
  /// The file to play for a sound, or null if it has none. [saved] is what [add] gave.
  Future<String?> pathFor(String soundId, String? saved);

  /// Keeps a copy of [sourcePath] for the sound, and gives what to remember it by.
  Future<String> add(String soundId, String sourcePath);
  Future<void> remove(String saved);
}

/// Where the choices are kept between runs.
abstract class AmbienceStore {
  Future<String?> read();
  Future<void> write(String value);
}

class AmbienceException implements Exception {
  const AmbienceException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// The file types the player can loop.
const ambienceExtensions = {'mp3', 'ogg', 'wav', 'flac'};

/// Ambience on the phone that plays it: which sounds are on and how loud, the mixes, the sleep timer.
class AmbienceController extends ChangeNotifier implements AmbienceControls {
  AmbienceController({
    required this.engine,
    required this.files,
    required this.store,
    this.pauseMusic,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final AmbienceEngine engine;
  final AmbienceFiles files;
  final AmbienceStore store;

  /// Music and ambience never play together: called before ambience starts.
  final Future<void> Function()? pauseMusic;
  final DateTime Function() _now;

  /// The timer fades out over this much of its end.
  static const fadeSeconds = 5 * 60;

  final Map<String, String> _saved = {}; // sound id -> the file kept for it
  final Map<String, String> _own = {}; // id -> name, sounds the owner added by name
  final Set<String> _environments = {}; // which of those are whole environments
  final Map<String, String> _icons = {}; // sound id -> the icon the owner chose
  final Set<String> _keptEmpty = {}; // sounds whose file was taken away: the folder does not refill them
  String? _folder;
  final List<AmbienceMix> _mixes = [];
  final Map<String, double> _active = {};
  final Set<String> _voices = {};
  double _master = 0.7;
  double _max = 1;
  int? _timer;
  double _left = 0;
  DateTime? _since;
  Timer? _tick;
  bool _playing = false;
  String? _mixName;
  String? _error;
  Future<void>? _loading;
  Future<void>? _queue;

  /// Reads what was kept. Safe to call more than once.
  Future<void> load() => _loading ??= _load();

  @override
  Future<void> refresh() => load();

  /// Whether sounds are loaded (playing or paused), so the notification is ambience's.
  bool get holding => _playing || _voices.isNotEmpty;

  Future<void> _load() async {
    try {
      final j = jsonDecode(await store.read() ?? '{}');
      if (j is! Map) return;
      for (final e in (j['files'] is Map ? j['files'] as Map : const {}).entries) {
        if (e.key is String && e.value is String) _saved[e.key as String] = e.value as String;
      }
      for (final e in (j['own'] is Map ? j['own'] as Map : const {}).entries) {
        if (e.key is String && e.value is String) _own[e.key as String] = e.value as String;
      }
      for (final e in (j['icons'] is Map ? j['icons'] as Map : const {}).entries) {
        if (e.key is String && e.value is String) _icons[e.key as String] = e.value as String;
      }
      if (j['folder'] is String) _folder = j['folder'] as String;
      if (j['empty'] is List) _keptEmpty.addAll([for (final id in j['empty'] as List) if (id is String) id]);
      if (j['env'] is List) _environments.addAll([for (final id in j['env'] as List) if (id is String) id]);
      if (j['mixes'] is List) {
        for (final m in j['mixes'] as List) {
          if (AmbienceMix.fromJson(m) case final mix?) _mixes.add(mix);
        }
      }
      _active.addAll(readLayers(j['active']));
      if (j['master'] is num) _master = (j['master'] as num).toDouble().clamp(0.0, 1.0);
      if (j['max'] is num) _max = (j['max'] as num).toDouble().clamp(0.0, 1.0);
      if (j['timer'] is num) _timer = (j['timer'] as num).toInt();
      if (j['mix'] is String) _mixName = j['mix'] as String;
    } catch (_) {
      // Damaged settings start afresh.
    }
    _active.removeWhere((id, _) => !_hasAudio(id));
    _left = (_timer ?? 0) * 60;
    notifyListeners();
  }

  Future<void> _save() async {
    try {
      await store.write(jsonEncode({
        'files': _saved,
        'own': _own,
        'env': _environments.toList(),
        'icons': _icons,
        'empty': _keptEmpty.toList(),
        if (_folder != null) 'folder': _folder,
        'mixes': [for (final m in _mixes) m.toJson()],
        'active': _active,
        'master': _master,
        'max': _max,
        if (_timer != null) 'timer': _timer,
        if (_mixName != null) 'mix': _mixName,
      }));
    } catch (_) {}
  }

  bool _isBuiltInNoise(String id) => ambienceCatalog.any((s) => s.id == id && s.available);
  bool _hasAudio(String id) => _saved.containsKey(id) || _isBuiltInNoise(id);

  List<AmbienceSound> get _sounds => [
        for (final s in ambienceCatalog) s.copyWith(available: _hasAudio(s.id), icon: _icons[s.id]),
        // Environments first, then the owner's other sounds.
        for (final environment in [true, false])
          for (final e in _own.entries)
            if (_environments.contains(e.key) == environment)
              AmbienceSound(
                id: e.key,
                name: e.value,
                category: environment ? ambienceEnvironmentCategory : ambienceOwnCategory,
                available: _hasAudio(e.key),
                icon: _icons[e.key],
              ),
      ];

  @override
  AmbienceState get state => AmbienceState(
        sounds: _sounds,
        mixes: [...ambiencePresets, ..._mixes],
        active: Map.unmodifiable(_active),
        playing: _playing,
        master: min(_master, _max),
        maxVolume: _max,
        timerMinutes: _timer,
        secondsLeft: _timer == null ? null : _remaining().ceil(),
        mixName: _mixName,
        error: _error,
      );

  // ------------------------------------------------------------------ sound

  /// What is left of the timer, in seconds. It only runs while playing.
  double _remaining() {
    final since = _since;
    if (since == null) return _left;
    return max(0, _left - _now().difference(since).inMilliseconds / 1000);
  }

  double _fade() {
    final t = _timer;
    if (t == null) return 1;
    final window = min(fadeSeconds, t * 60);
    return (_remaining() / window).clamp(0.0, 1.0);
  }

  double _volumeOf(String id) => (_active[id] ?? 0) * min(_master, _max) * _fade();

  /// One change to the engine at a time, so a quick tap cannot overtake a slow start.
  Future<void> _inTurn(Future<void> Function() action) {
    final next = (_queue ?? Future<void>.value()).then((_) => action());
    _queue = next.catchError((Object _) {});
    return next;
  }

  Future<void> _startVoice(String id) async {
    try {
      final path = await files.pathFor(id, _saved[id]);
      if (path == null) throw const AmbienceException('no file');
      await engine.start(id, path, _volumeOf(id));
      _voices.add(id);
    } catch (_) {
      _active.remove(id);
      _error = "${_nameOf(id)} couldn't be played. Add its file again.";
    }
  }

  String _nameOf(String id) => _sounds.where((s) => s.id == id).map((s) => s.name).firstOrNull ?? 'That sound';

  Future<void> _applyVolumes() async {
    for (final id in _voices.toList()) {
      await engine.setVolume(id, _volumeOf(id));
    }
  }

  void _runClock() {
    _tick?.cancel();
    _tick = null;
    if (!_playing || _timer == null) return;
    _since = _now();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => _onTick());
  }

  void _holdClock() {
    _left = _remaining();
    _since = null;
    _tick?.cancel();
    _tick = null;
  }

  Future<void> _onTick() async {
    if (!_playing || _timer == null) return;
    if (_remaining() <= 0) {
      await stop();
      return;
    }
    await _inTurn(_applyVolumes);
    notifyListeners();
  }

  Future<void> _playNow() async {
    if (_active.isEmpty) return;
    await pauseMusic?.call();
    if (!_playing) {
      _playing = true;
      _runClock();
    }
    await engine.setPaused(false);
    for (final id in _active.keys.toList()) {
      if (!_voices.contains(id)) await _startVoice(id);
    }
    if (_active.isEmpty) await _stopNow();
  }

  Future<void> _stopNow() async {
    _playing = false;
    _holdClock();
    _left = (_timer ?? 0) * 60;
    _voices.clear();
    await engine.stopAll();
  }

  @override
  Future<void> play() => _inTurn(() async {
        await load();
        _error = null;
        await _playNow();
        notifyListeners();
      });

  @override
  Future<void> pause() => _inTurn(() async {
        if (!_playing) return;
        _playing = false;
        _holdClock();
        await engine.setPaused(true);
        notifyListeners();
      });

  @override
  Future<void> stop() => _inTurn(() async {
        await _stopNow();
        notifyListeners();
      });

  /// Music started: ambience gives way.
  Future<void> musicStarted() async {
    if (_playing || _voices.isNotEmpty) await stop();
  }

  @override
  Future<void> setActive(String soundId, bool on) => _inTurn(() async {
        await load();
        _error = null;
        if (on) {
          if (!_hasAudio(soundId)) throw AmbienceException('Add a file for ${_nameOf(soundId)} first.');
          _active.putIfAbsent(soundId, () => 0.5);
          _mixName = null;
          await _playNow();
        } else {
          if (_active.remove(soundId) == null) return;
          _mixName = null;
          if (_voices.remove(soundId)) await engine.stop(soundId);
          if (_active.isEmpty) await _stopNow();
        }
        notifyListeners();
        await _save();
      });

  @override
  Future<void> setVolume(String soundId, double volume) => _inTurn(() async {
        if (!_active.containsKey(soundId)) return;
        _active[soundId] = volume.clamp(0.0, 1.0);
        _mixName = null;
        if (_voices.contains(soundId)) await engine.setVolume(soundId, _volumeOf(soundId));
        notifyListeners();
        await _save();
      });

  @override
  Future<void> setMaster(double volume) => _inTurn(() async {
        await load();
        _master = volume.clamp(0.0, _max);
        await _applyVolumes();
        notifyListeners();
        await _save();
      });

  /// The loudest the ambience may ever be (only set on this phone).
  Future<void> setMaxVolume(double volume) => _inTurn(() async {
        await load();
        _max = volume.clamp(0.0, 1.0);
        _master = min(_master, _max);
        await _applyVolumes();
        notifyListeners();
        await _save();
      });

  @override
  Future<void> setTimer(int? minutes) => _inTurn(() async {
        await load();
        _timer = minutes == null || minutes <= 0 ? null : min(minutes, 12 * 60);
        _since = null;
        _left = (_timer ?? 0) * 60;
        _runClock();
        await _applyVolumes();
        notifyListeners();
        await _save();
      });

  // ------------------------------------------------------------------ mixes

  @override
  Future<List<String>> startMix(String mixId) async {
    var missing = <String>[];
    await _inTurn(() async {
      await load();
      _error = null;
      final mix = [...ambiencePresets, ..._mixes].where((m) => m.id == mixId).firstOrNull;
      if (mix == null) throw const AmbienceException('That mix is no longer there.');
      missing = [for (final id in mix.layers.keys) if (!_hasAudio(id)) _nameOf(id)];
      final layers = {
        for (final e in mix.layers.entries)
          if (_hasAudio(e.key)) e.key: e.value,
      };
      if (layers.isEmpty) throw AmbienceException('Add files for ${missing.join(' and ')} first.');
      await _stopNow();
      _active
        ..clear()
        ..addAll(layers);
      _mixName = mix.name;
      await _playNow();
      notifyListeners();
      await _save();
    });
    return missing;
  }

  @override
  Future<void> saveMix(String name) => _inTurn(() async {
        await load();
        final clean = name.trim();
        if (clean.isEmpty) throw const AmbienceException('Give the mix a name.');
        if (_active.isEmpty) throw const AmbienceException('Switch some sounds on first.');
        final short = clean.length > 40 ? clean.substring(0, 40) : clean;
        final at = _mixes.indexWhere((m) => m.name.toLowerCase() == short.toLowerCase());
        final mix = AmbienceMix(
          id: at < 0 ? 'mix-${_now().microsecondsSinceEpoch}' : _mixes[at].id,
          name: short,
          layers: Map.of(_active),
        );
        at < 0 ? _mixes.add(mix) : _mixes[at] = mix;
        _mixName = short;
        notifyListeners();
        await _save();
      });

  @override
  Future<void> deleteMix(String mixId) => _inTurn(() async {
        await load();
        _mixes.removeWhere((m) => m.id == mixId);
        notifyListeners();
        await _save();
      });

  // ------------------------------------------------------------------ files

  /// Gives a sound its audio (a copy of [sourcePath] is kept).
  Future<void> addFile(String soundId, String sourcePath) => _inTurn(() async {
        await load();
        final ext = sourcePath.split('.').last.toLowerCase();
        if (!ambienceExtensions.contains(ext)) {
          throw const AmbienceException('Pick an MP3, OGG, WAV or FLAC file.');
        }
        final old = _saved[soundId];
        final saved = await files.add(soundId, sourcePath);
        _saved[soundId] = saved;
        _keptEmpty.remove(soundId);
        if (old != null && old != saved) await files.remove(old);
        // A sound that is playing takes the new file.
        if (_voices.remove(soundId)) {
          await engine.stop(soundId);
          if (_playing) await _startVoice(soundId);
        }
        notifyListeners();
        await _save();
      });

  /// Makes a sound of the owner's own, with its file; [environment] puts it with the environments.
  Future<void> addOwnSound(String name, String sourcePath, {bool environment = false}) async {
    await load();
    final clean = name.trim();
    if (clean.isEmpty) throw const AmbienceException('Give the sound a name.');
    // Several can be added in the same instant (importing a folder), so the clock alone is not enough.
    var id = 'own-${_now().microsecondsSinceEpoch}';
    for (var n = 2; _own.containsKey(id); n++) {
      id = 'own-${_now().microsecondsSinceEpoch}-$n';
    }
    _own[id] = clean.length > 30 ? clean.substring(0, 30) : clean;
    if (environment) _environments.add(id);
    try {
      await addFile(id, sourcePath);
    } catch (_) {
      _own.remove(id);
      _environments.remove(id);
      rethrow;
    }
  }

  /// Takes a sound's file away (an own sound goes altogether).
  Future<void> removeFile(String soundId) => _inTurn(() async {
        await load();
        final saved = _saved.remove(soundId);
        if (!_isBuiltInNoise(soundId)) {
          _active.remove(soundId);
          if (_voices.remove(soundId)) await engine.stop(soundId);
          if (_active.isEmpty) await _stopNow();
        }
        if (ambienceCatalog.any((s) => s.id == soundId)) _keptEmpty.add(soundId);
        _own.remove(soundId);
        _environments.remove(soundId);
        if (!ambienceCatalog.any((s) => s.id == soundId)) _icons.remove(soundId);
        if (saved != null) await files.remove(saved);
        notifyListeners();
        await _save();
      });

  /// The folder that new sound files are picked up from, or null.
  String? get watchedFolder => _folder;

  Future<void> setWatchedFolder(String? folder) => _inTurn(() async {
        await load();
        _folder = folder;
        // Choosing a folder again means: fill what matches, also what was emptied before.
        _keptEmpty.clear();
        notifyListeners();
        await _save();
      });

  /// Connects the files among [paths] that are named like a sound with no file. Gives the names of the
  /// sounds that got one.
  Future<List<String>> connectNew(List<String> paths) async {
    await load();
    final added = <String>[];
    for (final m in matchByName(paths, _sounds)) {
      if (_keptEmpty.contains(m.id)) continue;
      try {
        await addFile(m.id, m.path);
        added.add(_nameOf(m.id));
      } catch (_) {
        // A file that cannot be copied is tried again next time.
      }
    }
    return added;
  }

  /// The icon a sound shows (a name from the icon library); null gives it its usual one.
  Future<void> setIcon(String soundId, String? icon) => _inTurn(() async {
        await load();
        if (icon == null) {
          _icons.remove(soundId);
        } else {
          _icons[soundId] = icon;
        }
        notifyListeners();
        await _save();
      });

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }
}
