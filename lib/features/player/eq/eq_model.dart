import 'dart:convert';
import 'dart:math' as math;

/// The frequency bands the phone's equalizer offers (they differ per phone; most
/// have five).
class EqBands {
  const EqBands({required this.minDb, required this.maxDb, required this.centersHz});

  final double minDb;
  final double maxDb;

  /// Center frequency of each band in hertz, lowest first.
  final List<double> centersHz;

  int get count => centersHz.length;

  /// "60 Hz", "910 Hz", "3.6 kHz", "14 kHz".
  String labelFor(int band) {
    final hz = centersHz[band];
    if (hz < 1000) return '${hz.round()} Hz';
    final k = hz / 1000;
    return '${k == k.roundToDouble() ? k.toStringAsFixed(0) : k.toStringAsFixed(1)} kHz';
  }
}

/// A named curve. It is written as gains (dB) at a few anchor frequencies and
/// turned into gains for however many bands the phone has.
class EqPreset {
  const EqPreset(this.name, this.points);

  final String name;

  /// Gains at [anchors] (dB).
  final List<double> points;

  static const anchors = <double>[60, 230, 910, 3600, 14000];

  static const flat = EqPreset('Flat', [0, 0, 0, 0, 0]);

  static const all = <EqPreset>[
    flat,
    EqPreset('Bass boost', [6, 4, 0, 0, 0]),
    EqPreset('Treble boost', [0, 0, 0, 3, 6]),
    EqPreset('Vocal', [-2, 0, 4, 3, -1]),
    EqPreset('Rock', [4, 2, -1, 3, 4]),
    EqPreset('Pop', [-1, 2, 4, 2, -1]),
    EqPreset('Jazz', [3, 2, -2, 2, 4]),
    EqPreset('Classical', [4, 3, -1, 3, 4]),
    EqPreset('Loudness', [5, 2, 0, 2, 5]),
  ];

  static EqPreset? byName(String? name) {
    for (final p in all) {
      if (p.name == name) return p;
    }
    return null;
  }

  /// The gain for each of [bands], read off this curve on a log frequency
  /// scale and kept inside what the phone allows.
  List<double> gainsFor(EqBands bands) {
    double at(double hz) {
      if (hz <= anchors.first) return points.first;
      if (hz >= anchors.last) return points.last;
      for (var i = 0; i < anchors.length - 1; i++) {
        if (hz <= anchors[i + 1]) {
          final t = (math.log(hz) - math.log(anchors[i])) /
              (math.log(anchors[i + 1]) - math.log(anchors[i]));
          return points[i] + (points[i + 1] - points[i]) * t;
        }
      }
      return points.last;
    }

    return [
      for (final hz in bands.centersHz) at(hz).clamp(bands.minDb, bands.maxDb).toDouble(),
    ];
  }
}

/// What the equalizer is set to.
class EqSettings {
  const EqSettings({this.enabled = false, this.preset, this.gains = const []});

  final bool enabled;

  /// The preset these gains came from; null once a slider was moved by hand.
  final String? preset;

  /// dB per band (empty: not set yet, treated as flat).
  final List<double> gains;

  EqSettings copyWith({bool? enabled, String? preset, bool clearPreset = false, List<double>? gains}) =>
      EqSettings(
        enabled: enabled ?? this.enabled,
        preset: clearPreset ? null : (preset ?? this.preset),
        gains: gains ?? this.gains,
      );

  String toJson() => jsonEncode({'enabled': enabled, 'preset': preset, 'gains': gains});

  static EqSettings? fromJson(String? text) {
    if (text == null || text.isEmpty) return null;
    try {
      final m = jsonDecode(text);
      if (m is! Map) return null;
      final g = m['gains'];
      return EqSettings(
        enabled: m['enabled'] == true,
        preset: m['preset'] is String ? m['preset'] as String : null,
        gains: g is List ? [for (final e in g) if (e is num) e.toDouble()] : const [],
      );
    } catch (_) {
      return null;
    }
  }
}
