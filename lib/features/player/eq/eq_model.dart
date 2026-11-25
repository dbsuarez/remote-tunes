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

/// Gain at [hz] read off points ([hzs] low to high, [vals]) on a log frequency
/// scale; flat outside the first and last point.
double interpolateDb(List<double> hzs, List<double> vals, double hz) {
  if (hz <= hzs.first) return vals.first;
  if (hz >= hzs.last) return vals.last;
  for (var i = 0; i < hzs.length - 1; i++) {
    if (hz <= hzs[i + 1]) {
      final t = (math.log(hz) - math.log(hzs[i])) / (math.log(hzs[i + 1]) - math.log(hzs[i]));
      return vals[i] + (vals[i + 1] - vals[i]) * t;
    }
  }
  return vals.last;
}

/// A named curve. It is written as gains (dB) at a few anchor frequencies and
/// turned into gains for however many bands the phone has.
class EqPreset {
  const EqPreset(this.name, this.points);

  final String name;

  /// Gains at [anchors] (dB).
  final List<double> points;

  static const anchors = <double>[60, 230, 910, 3600, 14000];

  /// The ten sliders of the 10-band view (hertz).
  static const tenCenters = <double>[31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000];

  /// This curve at the ten sliders, kept inside [minDb] to [maxDb].
  List<double> tenGains(double minDb, double maxDb) => [
        for (final hz in tenCenters)
          interpolateDb(anchors, points, hz).clamp(minDb, maxDb).toDouble(),
      ];

  static String tenLabel(int i) {
    final hz = tenCenters[i];
    if (hz < 1000) return '${hz.round()}';
    return '${(hz / 1000).round()}k';
  }

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
    return [
      for (final hz in bands.centersHz)
        interpolateDb(anchors, points, hz).clamp(bands.minDb, bands.maxDb).toDouble(),
    ];
  }
}

/// What the equalizer is set to.
/// How strongly the compressor evens out loud and quiet parts (Android's multiband compressor, used
/// as one band over the whole sound). Off leaves the music as it is.
enum CompressorLevel {
  off('Off', 'The music as it is', 0, 1, 20, 250, 0),
  light('Light', 'Gently evens out loud and quiet parts', -24, 2, 20, 250, 3),
  medium('Medium', 'Good for quiet listening and for talk', -28, 3, 10, 200, 5),
  strong('Strong', 'Loud and quiet become much closer', -32, 5, 5, 150, 8);

  const CompressorLevel(
      this.label, this.hint, this.thresholdDb, this.ratio, this.attackMs, this.releaseMs, this.makeupDb);

  final String label;
  final String hint;

  /// Above this level (dB) the sound is turned down by [ratio] : 1.
  final double thresholdDb;
  final double ratio;

  /// How fast it reacts to a loud part, and lets go afterwards (milliseconds).
  final double attackMs;
  final double releaseMs;

  /// Turned back up afterwards (dB), so the music is not quieter overall.
  final double makeupDb;

  bool get on => this != off;

  static CompressorLevel parse(String? name) =>
      values.firstWhere((l) => l.name == name, orElse: () => CompressorLevel.off);
}

class EqSettings {
  const EqSettings({
    this.enabled = false,
    this.preset,
    this.gains = const [],
    this.preampDb = 0,
    this.toneOn = false,
    this.bassDb = 0,
    this.trebleDb = 0,
    this.limit = false,
    this.tenBand = false,
    this.tenGains = const [],
    this.compressor = 'off',
  });

  /// The compressor's strength (a [CompressorLevel] name). It works even when the equalizer is off.
  final String compressor;

  CompressorLevel get compressorLevel => CompressorLevel.parse(compressor);

  final bool enabled;

  /// The 10-band view is in use: ten sliders that are blended down onto the
  /// phone's own (usually five) bands.
  final bool tenBand;

  /// dB at [EqPreset.tenCenters] (empty: flat).
  final List<double> tenGains;

  /// Overall level before the bands (dB, -12 to +12).
  final double preampDb;

  /// The Bass / Treble knobs are in use.
  final bool toneOn;

  /// Extra bass and treble (dB, -10 to +10), added on top of the bands.
  final double bassDb;
  final double trebleDb;

  /// Turns everything down by as much as the bands boost, so loud passages do
  /// not distort.
  final bool limit;

  static const preampRange = 12.0;
  static const toneRange = 10.0;

  /// The preset these gains came from; null once a slider was moved by hand.
  final String? preset;

  /// dB per band (empty: not set yet, treated as flat).
  final List<double> gains;

  EqSettings copyWith({
    bool? enabled,
    String? preset,
    bool clearPreset = false,
    List<double>? gains,
    double? preampDb,
    bool? toneOn,
    double? bassDb,
    double? trebleDb,
    bool? limit,
    bool? tenBand,
    List<double>? tenGains,
    String? compressor,
  }) =>
      EqSettings(
        enabled: enabled ?? this.enabled,
        preset: clearPreset ? null : (preset ?? this.preset),
        gains: gains ?? this.gains,
        preampDb: preampDb ?? this.preampDb,
        toneOn: toneOn ?? this.toneOn,
        bassDb: bassDb ?? this.bassDb,
        trebleDb: trebleDb ?? this.trebleDb,
        limit: limit ?? this.limit,
        tenBand: tenBand ?? this.tenBand,
        tenGains: tenGains ?? this.tenGains,
        compressor: compressor ?? this.compressor,
      );

  /// What each band is really set to: the sliders plus, when Tone is on, the
  /// Bass and Treble knobs (bass lifts the low bands, treble the high ones).
  List<double> effectiveGains(EqBands bands) {
    final base = tenBand && tenGains.length == EqPreset.tenCenters.length
        // Ten sliders, read off at each of the phone's bands.
        ? [for (final hz in bands.centersHz) interpolateDb(EqPreset.tenCenters, tenGains, hz)]
        : gains.length == bands.count
            ? gains
            : List.filled(bands.count, 0.0);
    return [
      for (var i = 0; i < bands.count; i++)
        (base[i] +
                (toneOn
                    ? bassDb * bassWeight(bands.centersHz[i]) +
                        trebleDb * trebleWeight(bands.centersHz[i])
                    : 0))
            .clamp(bands.minDb, bands.maxDb)
            .toDouble(),
    ];
  }

  /// The ten sliders as they are really applied by our own equalizer: the
  /// sliders plus, when Tone is on, Bass and Treble.
  List<double> effectiveTenGains(EqBands bands) {
    final base = tenGains.length == EqPreset.tenCenters.length
        ? tenGains
        : List.filled(EqPreset.tenCenters.length, 0.0);
    return [
      for (var i = 0; i < base.length; i++)
        (base[i] +
                (toneOn
                    ? bassDb * bassWeight(EqPreset.tenCenters[i]) +
                        trebleDb * trebleWeight(EqPreset.tenCenters[i])
                    : 0))
            .clamp(bands.minDb, bands.maxDb)
            .toDouble(),
    ];
  }

  /// The level change to apply before the bands: the preamp, and with Limit on,
  /// enough turning down to cancel the biggest boost. With our own equalizer
  /// ([trueTen]) Limit is a real limiter instead, so nothing is turned down.
  double effectivePreampDb(EqBands bands, {bool trueTen = false}) {
    var db = preampDb;
    if (limit && !trueTen) {
      final boost = effectiveGains(bands).fold<double>(0, math.max);
      db -= boost;
    }
    return db.clamp(-24.0, EqSettings.preampRange).toDouble();
  }

  /// 1 for deep bass, falling to 0 around 1.5 kHz.
  static double bassWeight(double hz) =>
      (1 - (math.log(hz) / math.ln10 - 2) / 1.2).clamp(0.0, 1.0).toDouble();

  /// 0 below 1.5 kHz, rising to 1 for the highest treble.
  static double trebleWeight(double hz) =>
      ((math.log(hz) / math.ln10 - 3.2) / 1.0).clamp(0.0, 1.0).toDouble();

  String toJson() => jsonEncode({
        'enabled': enabled,
        'preset': preset,
        'gains': gains,
        'preampDb': preampDb,
        'toneOn': toneOn,
        'bassDb': bassDb,
        'trebleDb': trebleDb,
        'limit': limit,
        'tenBand': tenBand,
        'tenGains': tenGains,
        'compressor': compressor,
      });

  static double _num(Object? v, double range) =>
      v is num ? v.toDouble().clamp(-range, range).toDouble() : 0.0;

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
        preampDb: _num(m['preampDb'], EqSettings.preampRange),
        toneOn: m['toneOn'] == true,
        bassDb: _num(m['bassDb'], EqSettings.toneRange),
        trebleDb: _num(m['trebleDb'], EqSettings.toneRange),
        limit: m['limit'] == true,
        tenBand: m['tenBand'] == true,
        tenGains: m['tenGains'] is List
            ? [for (final e in m['tenGains'] as List) if (e is num) e.toDouble()]
            : const [],
        compressor: CompressorLevel.parse(m['compressor'] as String?).name,
      );
    } catch (_) {
      return null;
    }
  }
}
