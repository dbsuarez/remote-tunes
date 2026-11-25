import 'dart:async';

import 'package:flutter/foundation.dart';

import '../audio/audio_backend.dart';
import 'eq_model.dart';

/// Where the equalizer's settings are kept (the settings table, in the app).
abstract class EqStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> remove(String key);
}

/// The equalizer of this phone's own player: the bands the phone offers, what
/// they are set to, and presets. Settings can be remembered per sound output
/// (the speaker, wired headphones, Bluetooth) and are applied again when that
/// output is in use.
class EqualizerController extends ChangeNotifier {
  EqualizerController({
    required AudioBackend backend,
    required EqStore store,
    required Future<String> Function() outputRoute,
  })  : _backend = backend,
        _store = store,
        _route = outputRoute;

  final AudioBackend _backend;
  final EqStore _store;
  final Future<String> Function() _route;

  static const _defaultKey = 'eq_default';
  static String _outputKey(String route) => 'eq_output_$route';

  EqBands? _bands;
  EqSettings _settings = const EqSettings();
  String _output = 'unknown';
  bool _outputSaved = false;
  bool _started = false;

  /// The phone's bands; null until the first song has been loaded (Android only
  /// sets the equalizer up then) or when the phone has none.
  EqBands? get bands => _bands;
  EqSettings get settings => _settings;

  /// Where the sound goes: `speaker`, `wired`, `bluetooth` (or `unknown`).
  String get output => _output;

  /// The current settings are remembered for [output].
  bool get savedForOutput => _outputSaved;

  /// Reads the saved settings and the phone's bands, and applies them. Call once
  /// at start-up; it finishes when the bands are known.
  Future<void> init() async {
    if (_started) return;
    _started = true;
    await _refreshOutput();
    _bands = await _backend.equalizerBands();
    await _apply(notify: true);
  }

  /// Checks which output is in use and switches to its saved settings (call when
  /// the screen opens or the app comes back).
  Future<void> refreshOutput() async {
    final before = _output;
    await _refreshOutput();
    if (_output != before) await _apply(notify: true);
  }

  Future<void> _refreshOutput() async {
    try {
      _output = await _route();
    } catch (_) {
      _output = 'unknown';
    }
    final saved = EqSettings.fromJson(await _store.read(_outputKey(_output)));
    _outputSaved = saved != null;
    _settings = saved ?? EqSettings.fromJson(await _store.read(_defaultKey)) ?? const EqSettings();
  }

  Future<void> _apply({bool notify = false}) async {
    final b = _bands;
    if (b != null) {
      var gains = _settings.gains;
      if (gains.length != b.count) {
        // Another phone's saved bands, or none yet: start from the preset or flat.
        gains = (EqPreset.byName(_settings.preset) ?? EqPreset.flat).gainsFor(b);
        _settings = _settings.copyWith(gains: gains);
      }
      try {
        await _backend.setEqualizer(enabled: _settings.enabled, gains: gains);
      } catch (_) {
        // The effect could not be changed; the settings are still kept.
      }
    }
    if (notify) notifyListeners();
  }

  Future<void> _save() async {
    final json = _settings.toJson();
    await _store.write(_defaultKey, json);
    if (_outputSaved) await _store.write(_outputKey(_output), json);
  }

  Future<void> setEnabled(bool on) async {
    _settings = _settings.copyWith(enabled: on);
    notifyListeners();
    await _apply();
    await _save();
  }

  Future<void> applyPreset(EqPreset preset) async {
    final b = _bands;
    if (b == null) return;
    _settings = _settings.copyWith(preset: preset.name, gains: preset.gainsFor(b), enabled: true);
    notifyListeners();
    await _apply();
    await _save();
  }

  /// Moves one band by hand (the preset then reads "Custom").
  Future<void> setBand(int index, double gainDb) async {
    final b = _bands;
    if (b == null || index < 0 || index >= b.count) return;
    final gains = [..._settings.gains];
    if (gains.length != b.count) return;
    gains[index] = gainDb.clamp(b.minDb, b.maxDb).toDouble();
    _settings = _settings.copyWith(gains: gains, clearPreset: true, enabled: true);
    notifyListeners();
    await _apply();
  }

  /// Saves after a slider was let go.
  Future<void> commit() => _save();

  Future<void> reset() => applyPreset(EqPreset.flat);

  /// Remember (or forget) these settings for the output in use.
  Future<void> setSavedForOutput(bool on) async {
    _outputSaved = on;
    if (on) {
      await _store.write(_outputKey(_output), _settings.toJson());
    } else {
      await _store.remove(_outputKey(_output));
    }
    notifyListeners();
  }
}
