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
  bool _trueTen = false;

  /// The ten sliders are really ten filters of our own (not blended onto the
  /// phone's five bands). False when it is off, waiting for the first song, or
  /// this phone does not allow it.
  bool get trueTenBand => _trueTen && _backend.trueEqualizerActive != false;

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
        // The ten sliders as ten real filters, when this phone allows it.
        _trueTen = false;
        if (_settings.tenBand && _settings.enabled) {
          _trueTen = await _backend.setTrueEqualizer(
            enabled: true,
            centersHz: EqPreset.tenCenters,
            gains: _settings.effectiveTenGains(b),
            limiter: _settings.limit,
          );
        } else {
          await _backend.setTrueEqualizer(
            enabled: false,
            centersHz: EqPreset.tenCenters,
            gains: List.filled(EqPreset.tenCenters.length, 0.0),
            limiter: false,
          );
        }
        // What each band is really set to (sliders plus Bass / Treble), and the
        // preamp (plus Limit's turning down). Nothing changes while it is off.
        // With our own equalizer the phone's one stays flat.
        await _backend.setEqualizer(
          enabled: _settings.enabled,
          gains: _trueTen
              ? List.filled(b.count, 0.0)
              : _settings.effectiveGains(b),
        );
        await _backend.setPreamp(
            _settings.enabled ? _settings.effectivePreampDb(b, trueTen: _trueTen) : 0);
      } catch (_) {
        // The effect could not be changed; the settings are still kept.
      }
    }
    if (notify) notifyListeners();
  }

  /// Applies the settings again (the screen calls this when it opens: a song
  /// may have been loaded since, and whether our own equalizer works is only
  /// known then).
  Future<void> reapply() async {
    _bands ??= await _backend.equalizerBands();
    await _apply(notify: true);
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
    _settings = _settings.copyWith(
        preset: preset.name,
        gains: preset.gainsFor(b),
        tenGains: preset.tenGains(b.minDb, b.maxDb),
        enabled: true);
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

  /// Switches between the phone's own bands and the ten sliders. Going to ten,
  /// they start where the bands are now.
  Future<void> setTenBand(bool on) async {
    final b = _bands;
    if (b == null) return;
    var ten = _settings.tenGains;
    if (on && ten.length != EqPreset.tenCenters.length) {
      final g = _settings.gains.length == b.count ? _settings.gains : List.filled(b.count, 0.0);
      ten = [
        for (final hz in EqPreset.tenCenters)
          interpolateDb(b.centersHz, g, hz).clamp(b.minDb, b.maxDb).toDouble(),
      ];
    }
    _settings = _settings.copyWith(tenBand: on, tenGains: ten);
    notifyListeners();
    await _apply();
    await _save();
  }

  /// Moves one of the ten sliders (the preset then reads "Custom").
  Future<void> setTenBandGain(int index, double gainDb) async {
    final b = _bands;
    if (b == null || index < 0 || index >= EqPreset.tenCenters.length) return;
    final ten = _settings.tenGains.length == EqPreset.tenCenters.length
        ? [..._settings.tenGains]
        : List.filled(EqPreset.tenCenters.length, 0.0);
    ten[index] = gainDb.clamp(b.minDb, b.maxDb).toDouble();
    _settings = _settings.copyWith(tenGains: ten, tenBand: true, clearPreset: true, enabled: true);
    notifyListeners();
    await _apply();
  }

  Future<void> setPreamp(double db) async {
    _settings = _settings.copyWith(
        preampDb: db.clamp(-EqSettings.preampRange, EqSettings.preampRange).toDouble());
    notifyListeners();
    await _apply();
  }

  Future<void> setToneOn(bool on) async {
    _settings = _settings.copyWith(toneOn: on);
    notifyListeners();
    await _apply();
    await _save();
  }

  Future<void> setBass(double db) async {
    _settings = _settings.copyWith(
        bassDb: db.clamp(-EqSettings.toneRange, EqSettings.toneRange).toDouble(), toneOn: true);
    notifyListeners();
    await _apply();
  }

  Future<void> setTreble(double db) async {
    _settings = _settings.copyWith(
        trebleDb: db.clamp(-EqSettings.toneRange, EqSettings.toneRange).toDouble(), toneOn: true);
    notifyListeners();
    await _apply();
  }

  Future<void> setLimit(bool on) async {
    _settings = _settings.copyWith(limit: on);
    notifyListeners();
    await _apply();
    await _save();
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
