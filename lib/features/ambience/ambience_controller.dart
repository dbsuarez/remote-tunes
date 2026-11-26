import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'ambience_banner.dart';
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

  /// How strong the sound in [path] is, as a share of the loudest a file can be: its average (RMS) and
  /// its highest point. Null if it cannot be told.
  Future<({double rms, double peak})?> measure(String path);
}

/// How much to turn a file up (or down) so that all sounds are about equally loud. Recordings of rain or
/// crickets are often far quieter than music. Short peaks (crackles) may go a little over the top, where
/// the player rounds them off, but not further.
double evenGain(({double rms, double peak})? level) {
  if (level == null || level.rms <= 0.00001) return 1;
  var gain = ambienceLoudness / level.rms;
  if (level.peak > 0) gain = min(gain, ambienceHeadroom / level.peak);
  return gain.clamp(0.2, 12.0);
}

/// The average level every sound is brought to (about -20 dB), and how far its peaks may go over full.
const ambienceLoudness = 0.1;
const ambienceHeadroom = 2.5;

/// Where the audio files are: copies the owner added, and the noise the app makes.
abstract class AmbienceFiles {
  /// The file to play for a sound, or null if it has none. [saved] is what [add] gave.
  Future<String?> pathFor(String soundId, String? saved);

  /// Keeps a copy of [sourcePath] for the sound, and gives what to remember it by.
  Future<String> add(String soundId, String sourcePath);
  Future<void> remove(String saved);

  /// Keeps [bytes] under a new name that starts with [name], and gives what to remember it by.
  Future<String> write(String name, Uint8List bytes);
}

/// A group's own banner: the finished picture, the picture it was cut from, and how.
typedef AmbienceBanner = ({String imagePath, String? sourcePath, BannerFraming framing});

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

/// What a restored backup added.
typedef AmbienceRestore = ({int sounds, int mixes, int banners});

/// A scheduled start still happens this long after its time (the phone may have been busy), not later.
const ambienceLateStart = Duration(minutes: 10);

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
  final Map<String, double> _gain = {}; // sound id -> the measured evening-out of its file
  final Map<String, double> _boost = {}; // sound id -> the owner's louder (above 1) or softer
  String? _folder;
  AmbienceSchedule _schedule = const AmbienceSchedule();
  String? _ranOn; // the day the schedule last started
  Timer? _bedtime;
  final Map<String, ({String file, String? source, BannerFraming framing})> _banners = {}; // by group
  final Map<String, AmbienceBanner> _bannerPaths = {}; // the same, with where the files are
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
      for (final (key, into) in [('gain', _gain), ('boost', _boost)]) {
        for (final e in (j[key] is Map ? j[key] as Map : const {}).entries) {
          if (e.key is String && e.value is num) into[e.key as String] = (e.value as num).toDouble().clamp(0.2, 12.0);
        }
      }
      for (final e in (j['banners'] is Map ? j['banners'] as Map : const {}).entries) {
        final v = e.value;
        if (e.key is String && v is Map && v['file'] is String) {
          _banners[e.key as String] =
              (file: v['file'] as String, source: v['source'] is String ? v['source'] as String : null, framing: BannerFraming.fromJson(v));
        }
      }
      _schedule = AmbienceSchedule.fromJson(j['schedule']);
      if (j['ranOn'] is String) _ranOn = j['ranOn'] as String;
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
    for (final group in _banners.keys.toList()) {
      await _findBanner(group);
    }
    notifyListeners();
    _watchBedtime();
  }

  Future<void> _save() async {
    try {
      await store.write(jsonEncode({
        'files': _saved,
        'own': _own,
        'env': _environments.toList(),
        'icons': _icons,
        'empty': _keptEmpty.toList(),
        'schedule': _schedule.toJson(),
        if (_ranOn != null) 'ranOn': _ranOn,
        'banners': {
          for (final e in _banners.entries)
            e.key: {'file': e.value.file, if (e.value.source != null) 'source': e.value.source, ...e.value.framing.toJson()},
        },
        'gain': _gain,
        'boost': _boost,
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
        for (final s in ambienceCatalog) s.copyWith(available: _hasAudio(s.id), icon: _icons[s.id], boost: _boost[s.id]),
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
                boost: _boost[e.key] ?? 1,
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

  double _volumeOf(String id) =>
      (_active[id] ?? 0) * min(_master, _max) * _fade() * (_gain[id] ?? 1) * (_boost[id] ?? 1);

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
      // Measured once for each file, the first time it plays.
      if (!_gain.containsKey(id)) {
        try {
          _gain[id] = evenGain(await engine.measure(path));
          await _save();
        } catch (_) {
          // Plays as it is.
        }
      }
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
        _gain.remove(soundId); // a new file, to be measured again
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
        _gain.remove(soundId);
        _boost.remove(soundId);
        _environments.remove(soundId);
        if (!ambienceCatalog.any((s) => s.id == soundId)) _icons.remove(soundId);
        if (saved != null) await files.remove(saved);
        notifyListeners();
        await _save();
      });

  /// Makes one sound louder or softer for good (1 is as it comes; 0.25 to 4).
  Future<void> setBoost(String soundId, double boost) => _inTurn(() async {
        await load();
        final v = boost.clamp(0.25, 4.0);
        if ((v - 1).abs() < 0.01) {
          _boost.remove(soundId);
        } else {
          _boost[soundId] = v;
        }
        if (_voices.contains(soundId)) await engine.setVolume(soundId, _volumeOf(soundId));
        notifyListeners();
        await _save();
      });

  // ------------------------------------------------------------- bedtime

  AmbienceSchedule get schedule => _schedule;

  /// When the schedule starts next, or null if it is off.
  DateTime? get nextStart {
    if (!_schedule.enabled) return null;
    final now = _now();
    var at = DateTime(now.year, now.month, now.day, _schedule.hour, _schedule.minute);
    if (_ranOn == _day(at) || now.difference(at) >= ambienceLateStart) {
      at = DateTime(now.year, now.month, now.day + 1, _schedule.hour, _schedule.minute);
    }
    return at;
  }

  static String _day(DateTime d) => '${d.year}-${d.month}-${d.day}';

  Future<void> setSchedule(AmbienceSchedule schedule) async {
    await load();
    // A new time may be later today: it is allowed to run again.
    if (schedule.hour != _schedule.hour || schedule.minute != _schedule.minute || !_schedule.enabled) _ranOn = null;
    _schedule = schedule;
    // A time that has just passed means tomorrow, not "start now".
    final now = _now();
    final at = DateTime(now.year, now.month, now.day, schedule.hour, schedule.minute);
    if (schedule.enabled && _ranOn == null && !now.isBefore(at)) _ranOn = _day(at);
    notifyListeners();
    await _save();
    _watchBedtime();
  }

  void _watchBedtime() {
    _bedtime?.cancel();
    _bedtime = null;
    if (!_schedule.enabled) return;
    _bedtime = Timer.periodic(const Duration(seconds: 15), (_) => unawaited(checkBedtime()));
    unawaited(checkBedtime());
  }

  /// Starts the scheduled mix if its time has come (it only can while the app is running).
  Future<void> checkBedtime() async {
    if (!_schedule.enabled) return;
    final now = _now();
    final at = DateTime(now.year, now.month, now.day, _schedule.hour, _schedule.minute);
    if (now.isBefore(at) || now.difference(at) >= ambienceLateStart || _ranOn == _day(at)) return;
    _ranOn = _day(at);
    await _save();
    try {
      await setTimer(_schedule.timerMinutes);
      await startMix(_schedule.mixId);
    } catch (e) {
      _error = 'The bedtime mix could not start: $e';
      notifyListeners();
    }
  }

  // ------------------------------------------------------------- backup

  /// Everything to put in a backup: the choices, and the files they name (name to path).
  Future<({Map<String, dynamic> data, Map<String, String> files})> exportData() async {
    await load();
    await _save();
    final data = Map<String, dynamic>.from(jsonDecode(await store.read() ?? '{}') as Map)
      // Where files were on this phone means nothing on another.
      ..remove('folder')
      ..remove('ranOn');
    final paths = <String, String>{};
    Future<void> add(String id, String saved) async {
      final path = await files.pathFor(id, saved);
      if (path != null) paths[saved] = path;
    }

    for (final e in _saved.entries) {
      await add(e.key, e.value);
    }
    for (final b in _banners.values) {
      await add('banner', b.file);
      if (b.source != null) await add('banner', b.source!);
    }
    return (data: data, files: paths);
  }

  /// Adds what a backup holds that this phone lacks. Nothing here is replaced. [backup] maps the names the
  /// backup uses to where those files are now.
  Future<AmbienceRestore> importData(Map<String, dynamic> data, Map<String, String> backup) async {
    await load();
    var sounds = 0, mixes = 0, banners = 0;
    final untouched = _saved.isEmpty && _mixes.isEmpty && _active.isEmpty;
    Map<String, dynamic> map(String key) => data[key] is Map ? Map<String, dynamic>.from(data[key] as Map) : const {};
    final theirOwn = map('own');
    final theirEnv = data['env'] is List ? {...(data['env'] as List).whereType<String>()} : <String>{};
    final renamed = <String, String>{}; // their sound id -> ours

    for (final e in map('files').entries) {
      var id = e.key;
      final path = backup[e.value];
      final own = theirOwn[id];
      if (own is String) {
        // A sound of that name already here is the same sound.
        final same = _own.entries
            .where((o) => o.value.toLowerCase() == own.toLowerCase() && _environments.contains(o.key) == theirEnv.contains(id))
            .map((o) => o.key)
            .firstOrNull;
        if (same != null) {
          renamed[id] = same;
          continue;
        }
      } else if (!ambienceCatalog.any((s) => s.id == id)) {
        continue;
      }
      if (_saved.containsKey(id) || path == null) continue;
      try {
        _saved[id] = await files.add(id, path);
      } catch (_) {
        continue;
      }
      if (own is String) {
        _own[id] = own;
        if (theirEnv.contains(e.key)) _environments.add(id);
      }
      _keptEmpty.remove(id);
      sounds++;
      for (final (key, into) in [('gain', _gain), ('boost', _boost)]) {
        final v = map(key)[e.key];
        if (v is num) into[id] = v.toDouble().clamp(0.2, 12.0);
      }
    }
    String ours(String id) => renamed[id] ?? id;
    for (final e in map('icons').entries) {
      if (e.value is String) _icons.putIfAbsent(ours(e.key), () => e.value as String);
    }
    for (final e in map('boost').entries) {
      if (e.value is num) _boost.putIfAbsent(ours(e.key), () => (e.value as num).toDouble().clamp(0.25, 4.0));
    }
    for (final raw in data['mixes'] is List ? data['mixes'] as List : const []) {
      final mix = AmbienceMix.fromJson(raw);
      if (mix == null || _mixes.any((m) => m.name.toLowerCase() == mix.name.toLowerCase())) continue;
      final taken = _mixes.any((m) => m.id == mix.id);
      _mixes.add(AmbienceMix(
        id: taken ? 'mix-${_now().microsecondsSinceEpoch}-$mixes' : mix.id,
        name: mix.name,
        layers: {for (final l in mix.layers.entries) ours(l.key): l.value},
      ));
      mixes++;
    }
    for (final e in map('banners').entries) {
      final v = e.value;
      if (_banners.containsKey(e.key) || v is! Map) continue;
      final image = backup[v['file']];
      if (image == null) continue;
      try {
        final file = await files.add('banner', image);
        final from = backup[v['source']];
        final source = from == null ? null : await files.add('bannersrc', from);
        _banners[e.key] = (file: file, source: source, framing: BannerFraming.fromJson(v));
        await _findBanner(e.key);
        banners++;
      } catch (_) {
        // A picture that cannot be copied is left out.
      }
    }
    // A phone with nothing set up takes the rest too.
    if (untouched) {
      _active
        ..clear()
        ..addAll({for (final l in readLayers(data['active']).entries) ours(l.key): l.value});
      if (data['master'] is num) _master = (data['master'] as num).toDouble().clamp(0.0, 1.0);
      if (data['max'] is num) _max = min(_max, (data['max'] as num).toDouble().clamp(0.0, 1.0));
      if (data['timer'] is num) _timer = (data['timer'] as num).toInt();
      _left = (_timer ?? 0) * 60;
      if (!_schedule.enabled) await setSchedule(AmbienceSchedule.fromJson(data['schedule']));
    }
    _active.removeWhere((id, _) => !_hasAudio(id));
    notifyListeners();
    await _save();
    return (sounds: sounds, mixes: mixes, banners: banners);
  }

  /// The owner's own banner of a group, or null.
  AmbienceBanner? banner(String group) => _bannerPaths[group];

  Future<void> _findBanner(String group) async {
    final b = _banners[group];
    if (b == null) {
      _bannerPaths.remove(group);
      return;
    }
    try {
      final image = await files.pathFor('banner', b.file);
      final source = b.source == null ? null : await files.pathFor('banner', b.source);
      if (image == null) {
        _bannerPaths.remove(group);
      } else {
        _bannerPaths[group] = (imagePath: image, sourcePath: source, framing: b.framing);
      }
    } catch (_) {
      _bannerPaths.remove(group);
    }
  }

  /// Gives a group its banner: [png] as it will show. [newSource] is the picture it was just cut from
  /// (null: the one kept already, only framed differently).
  Future<void> setBanner(String group, Uint8List png, BannerFraming framing, {String? newSource}) => _inTurn(() async {
        await load();
        final old = _banners[group];
        final source = newSource == null ? old?.source : await files.add('bannersrc', newSource);
        final file = await files.write('banner', png);
        _banners[group] = (file: file, source: source, framing: framing);
        await _findBanner(group);
        if (old != null) {
          await files.remove(old.file);
          if (old.source != null && old.source != source) await files.remove(old.source!);
        }
        notifyListeners();
        await _save();
      });

  Future<void> removeBanner(String group) => _inTurn(() async {
        await load();
        final old = _banners.remove(group);
        _bannerPaths.remove(group);
        if (old == null) return;
        await files.remove(old.file);
        if (old.source != null) await files.remove(old.source!);
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
    _bedtime?.cancel();
    _tick?.cancel();
    super.dispose();
  }
}
