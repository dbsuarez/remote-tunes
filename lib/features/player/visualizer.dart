import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

/// Reads the spectrum of the sound this phone is playing, as a few bars.
///
/// Android's Visualizer hands over only how loud each range of frequencies is
/// (nothing is recorded), but asks for the microphone permission to do it.
class VisualizerService {
  VisualizerService({
    MethodChannel? channel,
    Future<bool> Function()? hasPermission,
    int? Function()? sessionId,
    this.barCount = 24,
    this.checkEvery = const Duration(seconds: 1),
  })  : _channel = channel ?? const MethodChannel('remotetunes/visualizer'),
        _hasPermission = hasPermission ?? _micGranted,
        _sessionId = sessionId ?? currentSessionId {
    _channel.setMethodCallHandler(_onCall);
  }

  /// Where the audible sound's session id comes from (set when the player starts).
  static int? Function() currentSessionId = () => null;

  /// Asks for the permission (from Settings, when the visualizer is switched on).
  static Future<bool> requestPermission() async =>
      (await Permission.microphone.request()).isGranted;

  static Future<bool> _micGranted() async => (await Permission.microphone.status).isGranted;

  final MethodChannel _channel;
  final Future<bool> Function() _hasPermission;
  final int? Function() _sessionId;
  final int barCount;
  final Duration checkEvery;

  /// 0 to 1 per bar, smoothed (rises quickly, falls slowly).
  final ValueNotifier<List<double>> bars = ValueNotifier(const []);

  /// Why nothing moves, when it does not: the permission, or this phone.
  final ValueNotifier<String?> problem = ValueNotifier(null);

  Timer? _timer;
  int? _attachedTo;
  bool _running = false;
  bool _disposed = false;

  Future<void> _onCall(MethodCall call) async {
    if (call.method != 'bars' || _disposed) return;
    final raw = call.arguments;
    if (raw is! List) return;
    final now = [for (final v in raw) v is num ? v.toDouble().clamp(0.0, 1.0) : 0.0];
    final old = bars.value;
    bars.value = [
      for (var i = 0; i < now.length; i++)
        i < old.length && old[i] > now[i] ? old[i] * 0.82 + now[i] * 0.18 : now[i],
    ];
  }

  /// Starts following the sound (and keeps following it when the song changes
  /// to the other player).
  Future<void> start() async {
    if (_running || _disposed) return;
    _running = true;
    await _attach();
    _timer = Timer.periodic(checkEvery, (_) => _attach());
  }

  Future<void> _attach() async {
    if (!_running || _disposed) return;
    final id = _sessionId();
    if (id == null || id == _attachedTo) return;
    if (!await _hasPermission()) {
      problem.value = 'permission';
      return;
    }
    bool ok;
    try {
      ok = await _channel.invokeMethod<bool>('start', {'session': id, 'bars': barCount}) ?? false;
    } catch (_) {
      ok = false;
    }
    if (_disposed || !_running) return;
    // A refusal is remembered for this sound, so it is not asked again every second.
    _attachedTo = id;
    problem.value = ok ? null : 'unavailable';
  }

  Future<void> stop() async {
    _running = false;
    _timer?.cancel();
    _timer = null;
    _attachedTo = null;
    bars.value = const [];
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }

  Future<void> dispose() async {
    if (_disposed) return;
    await stop();
    _disposed = true;
    _channel.setMethodCallHandler(null);
    bars.dispose();
    problem.dispose();
  }
}

/// The moving bars under the cover. Follows the sound while [isPlaying].
class VisualizerStrip extends StatefulWidget {
  const VisualizerStrip({super.key, required this.isPlaying, this.service});

  final bool isPlaying;

  /// For tests.
  final VisualizerService? service;

  @override
  State<VisualizerStrip> createState() => _VisualizerStripState();
}

class _VisualizerStripState extends State<VisualizerStrip> {
  late final VisualizerService _service = widget.service ?? VisualizerService();

  @override
  void initState() {
    super.initState();
    if (widget.isPlaying) _service.start();
  }

  @override
  void didUpdateWidget(VisualizerStrip old) {
    super.didUpdateWidget(old);
    if (old.isPlaying != widget.isPlaying) {
      widget.isPlaying ? _service.start() : _service.stop();
    }
  }

  @override
  void dispose() {
    _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<String?>(
      valueListenable: _service.problem,
      builder: (context, problem, _) {
        if (problem != null) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              problem == 'permission'
                  ? 'The visualizer needs the microphone permission (Android asks for it to read '
                      'the sound; nothing is recorded). Switch it off and on in Settings to be asked again.'
                  : 'This phone does not let the visualizer read this sound.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          );
        }
        return SizedBox(
          height: 56,
          child: ValueListenableBuilder<List<double>>(
            valueListenable: _service.bars,
            builder: (context, bars, _) => CustomPaint(
              key: const Key('visualizer-bars'),
              painter: BarsPainter(
                bars: bars,
                count: _service.barCount,
                low: theme.colorScheme.primary,
                high: theme.colorScheme.secondary,
              ),
              size: Size.infinite,
            ),
          ),
        );
      },
    );
  }
}

class BarsPainter extends CustomPainter {
  BarsPainter({required this.bars, required this.count, required this.low, required this.high});

  final List<double> bars;
  final int count;
  final Color low;
  final Color high;

  @override
  void paint(Canvas canvas, Size size) {
    final gap = 3.0;
    final w = (size.width - gap * (count - 1)) / count;
    for (var i = 0; i < count; i++) {
      final v = i < bars.length ? bars[i] : 0.0;
      final h = 3 + (size.height - 3) * v;
      final paint = Paint()..color = Color.lerp(low, high, i / (count - 1))!;
      final x = i * (w + gap);
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, size.height - h, w, h), Radius.circular(w / 2)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(BarsPainter old) =>
      old.bars != bars || old.low != low || old.high != high || old.count != count;
}
