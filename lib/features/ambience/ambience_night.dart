import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/screen_awake.dart';
import 'ambience_models.dart';

/// A nearly black screen for a dark room: the time, what is playing, and (after a tap) pause and stop.
/// The screen stays on and as dim as the phone allows, which also keeps a bedtime start on time.
class AmbienceNightScreen extends StatefulWidget {
  const AmbienceNightScreen({super.key, required this.controls, this.nextStart, this.now});

  final AmbienceControls controls;

  /// When the bedtime schedule will start next, or null.
  final DateTime? Function()? nextStart;
  final DateTime Function()? now;

  @override
  State<AmbienceNightScreen> createState() => _AmbienceNightScreenState();
}

class _AmbienceNightScreenState extends State<AmbienceNightScreen> {
  static const _dim = Color(0x55FFFFFF);

  final _leaving = Completer<void>();
  Timer? _clock;
  Timer? _hide;
  bool _buttons = false;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
    unawaited(ScreenAwake.during(() => _leaving.future));
    unawaited(ScreenDim.set(0.01));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));
  }

  @override
  void dispose() {
    _clock?.cancel();
    _hide?.cancel();
    _leaving.complete();
    unawaited(ScreenDim.set(null));
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  /// Shows the buttons for a few seconds.
  void _wake() {
    _hide?.cancel();
    _hide = Timer(const Duration(seconds: 6), () {
      if (mounted) setState(() => _buttons = false);
    });
    setState(() => _buttons = true);
  }

  Future<void> _do(Future<void> Function() action) async {
    _wake();
    try {
      await action();
    } catch (_) {
      // Nothing to show on a dark screen; the Ambience screen says why.
    }
  }

  @override
  Widget build(BuildContext context) {
    final time = TimeOfDay.fromDateTime(_now).format(context);
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        key: const Key('night-screen'),
        behavior: HitTestBehavior.opaque,
        onTap: _wake,
        child: SafeArea(
          child: Center(
            child: ListenableBuilder(
              listenable: widget.controls,
              builder: (context, _) {
                final s = widget.controls.state;
                final next = widget.nextStart?.call();
                final left = s.secondsLeft;
                final line = s.playing
                    ? [s.mixName ?? '${s.active.length} sounds', if (left != null) '${(left / 60).ceil()} min left'].join(' · ')
                    : next != null
                        ? 'Starts at ${TimeOfDay.fromDateTime(next).format(context)}'
                        : 'Silent';
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(time, key: const Key('night-time'), style: const TextStyle(color: _dim, fontSize: 64)),
                    ),
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(line, key: const Key('night-line'), textAlign: TextAlign.center, style: const TextStyle(color: _dim)),
                    ),
                    const SizedBox(height: 40),
                    SizedBox(
                      height: 64,
                      child: !_buttons
                          ? const Text('Tap for controls', style: TextStyle(color: Color(0x22FFFFFF), fontSize: 12))
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                IconButton(
                                  key: const Key('night-play'),
                                  tooltip: s.playing ? 'Pause' : 'Play',
                                  color: _dim,
                                  iconSize: 36,
                                  icon: Icon(s.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                                  onPressed: s.active.isEmpty
                                      ? null
                                      : () => _do(s.playing ? widget.controls.pause : widget.controls.play),
                                ),
                                const SizedBox(width: 24),
                                IconButton(
                                  key: const Key('night-stop'),
                                  tooltip: 'Stop',
                                  color: _dim,
                                  iconSize: 36,
                                  icon: const Icon(Icons.stop_rounded),
                                  onPressed: () => _do(widget.controls.stop),
                                ),
                                const SizedBox(width: 24),
                                IconButton(
                                  key: const Key('night-leave'),
                                  tooltip: 'Leave night mode',
                                  color: _dim,
                                  iconSize: 32,
                                  icon: const Icon(Icons.close_rounded),
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                              ],
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
