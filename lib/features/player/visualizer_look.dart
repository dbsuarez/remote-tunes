import 'dart:math' as math;

import 'package:flutter/material.dart';

/// How the visualizer is drawn.
enum VisualizerStyle {
  bars('Bars', 'Rounded bars with small caps that fall slowly'),
  mirror('Mirror', 'Bars growing up and down from the middle'),
  wave('Wave', 'A smooth, glowing line'),
  led('LED', 'Columns of lit squares, like a stereo'),
  spread('Spread', 'The bass in the middle, spreading out to both sides'),
  dots('Dots', 'A row of glowing dots that swell with the sound');

  const VisualizerStyle(this.label, this.hint);

  final String label;
  final String hint;

  /// The one after this (after the last, the first): what a tap moves to.
  VisualizerStyle get next => values[(index + 1) % values.length];

  static VisualizerStyle byName(String? name) =>
      values.firstWhere((s) => s.name == name, orElse: () => bars);
}

/// Turns what Android reports (a few readings a second, loud bass, quiet treble,
/// different loudness for every song) into numbers that look good: the spectrum
/// is evened out, the loudness of the song is followed, and a quiet floor is cut.
class VisualizerShaper {
  VisualizerShaper({this.floor = 0.06, this.minPeak = 0.35, this.gate = 0.05});

  /// Readings under this are noise, whatever the song's loudness.
  final double gate;

  /// Below this the bar stays flat (noise).
  final double floor;

  /// The loudest reading is never taken to be lower than this (silence stays flat).
  final double minPeak;

  double _peak = 0;

  /// 0.8 for the lowest bar rising to 1.25 for the highest: music loses energy
  /// toward the treble, so the right-hand bars would otherwise barely move.
  static double tilt(int i, int count) =>
      count <= 1 ? 1.0 : 0.8 + 0.45 * (i / (count - 1));

  List<double> shape(List<double> raw) {
    if (raw.isEmpty) return const [];
    final n = raw.length;
    final tilted = [for (var i = 0; i < n; i++) raw[i] < gate ? 0.0 : raw[i] * tilt(i, n)];
    final loudest = tilted.reduce(math.max);
    // Follows the song's loudness: rises at once, forgets slowly.
    _peak = math.max(math.max(_peak * 0.985, loudest), minPeak);
    return [
      for (final v in tilted)
        (((v / _peak) - floor) / (1 - floor)).clamp(0.0, 1.0).toDouble(),
    ];
  }

  void reset() => _peak = 0;
}

/// Moves the drawn bars toward what was measured at 60 frames a second: up
/// quickly, down slowly, with a cap that holds for a moment and then falls.
class VisualizerAnimator extends ChangeNotifier {
  List<double> _target = const [];
  List<double> values = const [];
  List<double> peaks = const [];
  List<double> _hold = const [];

  /// 0 to 1 closing in per frame on the way up.
  static const rise = 0.55;

  /// How far a bar falls per second.
  static const fallPerSecond = 1.6;

  /// A cap stays this long before it falls, then falls this fast per second.
  static const holdSeconds = 0.25;
  static const peakFallPerSecond = 0.9;

  void setTarget(List<double> target) {
    // No reading (the sound stopped): everything falls to nothing, in place.
    if (target.isEmpty) target = List.filled(values.length, 0.0);
    if (target.length != _target.length && target.length != values.length) {
      values = List.filled(target.length, 0.0);
      peaks = List.filled(target.length, 0.0);
      _hold = List.filled(target.length, 0.0);
    }
    _target = target;
  }

  /// True when everything has settled at zero (nothing left to animate).
  bool get idle => values.every((v) => v <= 0.001) && peaks.every((v) => v <= 0.001);

  /// Moves everything on by [dt] seconds.
  void step(double dt) {
    if (values.isEmpty) {
      // The sound went away: fall to nothing.
      return;
    }
    for (var i = 0; i < values.length; i++) {
      final t = i < _target.length ? _target[i] : 0.0;
      if (t > values[i]) {
        values[i] += (t - values[i]) * rise;
      } else {
        values[i] = math.max(t, values[i] - fallPerSecond * dt);
      }
      if (values[i] >= peaks[i]) {
        peaks[i] = values[i];
        _hold[i] = holdSeconds;
      } else if (_hold[i] > 0) {
        _hold[i] -= dt;
      } else {
        peaks[i] = math.max(values[i], peaks[i] - peakFallPerSecond * dt);
      }
    }
    notifyListeners();
  }
}

/// Draws the animator's numbers in a [style].
class VisualizerPainter extends CustomPainter {
  VisualizerPainter({
    required this.animator,
    required this.style,
    required this.low,
    required this.high,
  }) : super(repaint: animator);

  final VisualizerAnimator animator;
  final VisualizerStyle style;
  final Color low;
  final Color high;

  Color _at(double t) => Color.lerp(low, high, t.clamp(0.0, 1.0))!;

  /// Space between [count] bars and each bar's width: 3 px when there is room,
  /// less when narrow, never a negative width.
  static ({double gap, double w}) _fit(int count, double width) {
    final gap = math.min(3.0, width / count * 0.3);
    final w = math.max(1.0, (width - gap * (count - 1)) / count);
    return (gap: gap, w: w);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final v = animator.values;
    if (v.isEmpty) return;
    switch (style) {
      case VisualizerStyle.bars:
        _bars(canvas, size, v);
      case VisualizerStyle.mirror:
        _mirror(canvas, size, v);
      case VisualizerStyle.wave:
        _wave(canvas, size, v);
      case VisualizerStyle.led:
        _led(canvas, size, v);
      case VisualizerStyle.spread:
        _spread(canvas, size, v);
      case VisualizerStyle.dots:
        _dots(canvas, size, v);
    }
  }

  void _bars(Canvas canvas, Size size, List<double> v) {
    final n = v.length;
    final fit = _fit(n, size.width);
    final gap = fit.gap, w = fit.w;
    final glow = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    for (var i = 0; i < n; i++) {
      final h = 3 + (size.height - 8) * v[i];
      final x = i * (w + gap);
      final color = _at(i / (n - 1));
      final rect = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, size.height - h, w, h), Radius.circular(w / 2));
      canvas.drawRRect(rect, glow..color = color.withValues(alpha: 0.35 * v[i]));
      canvas.drawRRect(
        rect,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [color.withValues(alpha: 0.55), color],
          ).createShader(rect.outerRect),
      );
      // The cap.
      final capY = size.height - (3 + (size.height - 8) * animator.peaks[i]) - 4;
      if (animator.peaks[i] > 0.02) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, capY, w, 2.5), const Radius.circular(1.5)),
          Paint()..color = color.withValues(alpha: 0.9),
        );
      }
    }
  }

  void _mirror(Canvas canvas, Size size, List<double> v) {
    final n = v.length;
    final fit = _fit(n, size.width);
    final gap = fit.gap, w = fit.w;
    final mid = size.height / 2;
    for (var i = 0; i < n; i++) {
      final h = 2 + (mid - 3) * v[i];
      final x = i * (w + gap);
      final paint = Paint()..color = _at(i / (n - 1));
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, mid - h, w, h * 2), Radius.circular(w / 2)),
          paint);
    }
  }

  /// Columns of small lit squares, the way a stereo's level meter looks.
  void _led(Canvas canvas, Size size, List<double> v) {
    final n = v.length;
    final fit = _fit(n, size.width);
    final gap = fit.gap, w = fit.w;
    final cell = w.clamp(4.0, 12.0);
    final rows = ((size.height + 2) / (cell + 2)).floor().clamp(3, 12);
    final h = (size.height - 2 * (rows - 1)) / rows;
    for (var i = 0; i < n; i++) {
      final x = i * (w + gap);
      final lit = (v[i] * rows).round();
      for (var r = 0; r < rows; r++) {
        final y = size.height - (r + 1) * h - r * 2;
        final on = r < lit;
        // Low rows in the first color, the top rows in the second.
        final color = _at(r / (rows - 1));
        canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(x, y, w, h), const Radius.circular(2)),
          Paint()..color = on ? color : color.withValues(alpha: 0.10),
        );
      }
    }
  }

  /// The lowest sounds in the middle and the highest at both edges.
  void _spread(Canvas canvas, Size size, List<double> v) {
    final n = v.length;
    // Every reading is drawn twice (left and right of the middle).
    final slots = n * 2;
    final fit = _fit(slots, size.width);
    final gap = fit.gap, w = fit.w;
    final mid = size.height / 2;
    for (var i = 0; i < n; i++) {
      final h = 2 + (mid - 3) * v[i];
      final color = _at(i / (n - 1));
      final paint = Paint()..color = color;
      // i = 0 is next to the middle.
      final right = (n + i) * (w + gap);
      final left = (n - 1 - i) * (w + gap);
      for (final x in [left, right]) {
        canvas.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(x, mid - h, w, h * 2), Radius.circular(w / 2)),
            paint);
      }
    }
  }

  /// A row of dots that grow and brighten with the sound.
  void _dots(Canvas canvas, Size size, List<double> v) {
    final n = v.length;
    final step = size.width / n;
    final maxR = math.min(step / 2 - 1, size.height / 2 - 2);
    final glow = Paint()..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    for (var i = 0; i < n; i++) {
      final c = Offset(step * (i + 0.5), size.height / 2);
      final r = 2 + (maxR - 2) * v[i];
      final color = _at(i / (n - 1));
      canvas.drawCircle(c, r * 1.4, glow..color = color.withValues(alpha: 0.45 * v[i]));
      canvas.drawCircle(c, r, Paint()..color = color.withValues(alpha: 0.35 + 0.65 * v[i]));
    }
  }

  void _wave(Canvas canvas, Size size, List<double> v) {
    final n = v.length;
    final mid = size.height * 0.5;
    Offset p(int i) => Offset(
          size.width * i / (n - 1),
          mid - (size.height * 0.46) * v[i] * (i.isEven ? 1 : 0.85),
        );
    final path = Path()..moveTo(0, mid);
    path.lineTo(p(0).dx, p(0).dy);
    for (var i = 0; i < n - 1; i++) {
      final a = p(i), b = p(i + 1);
      final m = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
      path.quadraticBezierTo(a.dx, a.dy, m.dx, m.dy);
    }
    path.lineTo(size.width, p(n - 1).dy);
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeJoin = StrokeJoin.round
      ..shader = LinearGradient(colors: [low, high]).createShader(Offset.zero & size);
    canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 8
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8)
          ..shader = line.shader
          ..color = low.withValues(alpha: 0.5));
    canvas.drawPath(path, line);
  }

  @override
  bool shouldRepaint(VisualizerPainter old) =>
      old.style != style || old.low != low || old.high != high || old.animator != animator;
}
