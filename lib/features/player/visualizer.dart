import '../../data/repositories/settings_repository.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

export 'visualizer_look.dart' show VisualizerStyle;
import 'visualizer_look.dart';

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

  /// Asks for the permission (when the visualizer is switched on). Tests replace this.
  static Future<bool> Function() requestPermission = _requestMicrophone;

  static Future<bool> _requestMicrophone() async =>
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

/// Switches the visualizer on or off (from Settings or from the button on Now Playing).
/// Turning it on first asks for the microphone permission (Android needs it to read the
/// sound; nothing is recorded); if that is refused it stays off and says why.
Future<void> switchVisualizer(BuildContext context, SettingsRepository repo, bool on) async {
  if (on && !await VisualizerService.requestPermission()) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('The visualizer needs the microphone permission.')));
    }
    return;
  }
  await repo.setVisualizerEnabled(on);
}

/// The moving bars under the cover. Follows the sound while [isPlaying].
class VisualizerStrip extends StatefulWidget {
  const VisualizerStrip({
    super.key,
    required this.isPlaying,
    this.style = VisualizerStyle.bars,
    this.onCycle,
    this.service,
  });

  final bool isPlaying;
  final VisualizerStyle style;

  /// A tap on the visualizer asks for the next style (null: a tap does nothing).
  final VoidCallback? onCycle;

  /// For tests.
  final VisualizerService? service;

  @override
  State<VisualizerStrip> createState() => _VisualizerStripState();
}

class _VisualizerStripState extends State<VisualizerStrip> with SingleTickerProviderStateMixin {
  late final VisualizerService _service = widget.service ?? VisualizerService();
  final _shaper = VisualizerShaper();
  final _animator = VisualizerAnimator();
  late final Ticker _ticker = createTicker(_onTick);
  Duration _last = Duration.zero;

  /// The style's name is shown for a moment after it changes.
  bool _showName = false;
  Timer? _nameTimer;

  @override
  void initState() {
    super.initState();
    _service.bars.addListener(_onReading);
    if (widget.isPlaying) {
      _service.start();
      _ticker.start();
    }
  }

  /// A new reading from Android (about 20 a second).
  void _onReading() {
    final raw = _service.bars.value;
    _animator.setTarget(_shaper.shape(raw));
    if (!_ticker.isActive) _ticker.start();
  }

  /// Every frame: the bars close in on the last reading.
  void _onTick(Duration now) {
    final dt = _last == Duration.zero ? 1 / 60 : (now - _last).inMicroseconds / 1e6;
    _last = now;
    _animator.step(dt.clamp(0.0, 0.1));
    // Nothing playing and everything has fallen: stop drawing frames.
    if (!widget.isPlaying && _animator.idle) {
      _ticker.stop();
      _last = Duration.zero;
    }
  }

  @override
  void didUpdateWidget(VisualizerStrip old) {
    super.didUpdateWidget(old);
    if (old.style != widget.style) {
      _nameTimer?.cancel();
      setState(() => _showName = true);
      _nameTimer = Timer(const Duration(milliseconds: 1400), () {
        if (mounted) setState(() => _showName = false);
      });
    }
    if (old.isPlaying != widget.isPlaying) {
      if (widget.isPlaying) {
        _service.start();
        if (!_ticker.isActive) _ticker.start();
      } else {
        _service.stop();
        _shaper.reset();
        // The bars fall away by themselves (stopping the service clears the reading).
        _animator.setTarget(const []);
      }
    }
  }

  @override
  void dispose() {
    _nameTimer?.cancel();
    _ticker.dispose();
    _service.bars.removeListener(_onReading);
    _service.dispose();
    _animator.dispose();
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
        return Semantics(
          label: 'Visualizer, ${widget.style.label}. Tap to change the style.',
          button: widget.onCycle != null,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onCycle,
            child: SizedBox(
              height: 72,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: CustomPaint(
                      key: const Key('visualizer-bars'),
                      painter: VisualizerPainter(
                        animator: _animator,
                        style: widget.style,
                        low: theme.colorScheme.primary,
                        high: theme.colorScheme.secondary,
                      ),
                    ),
                  ),
                  // The name of the style, for a moment after a tap.
                  Positioned(
                    left: 0,
                    top: 0,
                    child: AnimatedOpacity(
                      key: const Key('visualizer-name'),
                      opacity: _showName ? 1 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surface.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(widget.style.label, style: theme.textTheme.labelSmall),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
