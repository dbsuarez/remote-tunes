import 'dart:math';

import 'package:flutter/material.dart';

import '../../core/haptics.dart';

/// The longest the timer can be set to, in minutes (12 hours).
const sleepTimerMost = 12 * 60;

/// What the dialog opens with, and keeps. The phone app saves it between runs (see [save]).
class SleepTimerMemory {
  static int minutes = 30;
  static bool finishSong = false;
  static Future<void> Function(int minutes, bool finishSong)? save;
}

/// What was chosen: [minutes] 0 switches the timer off.
typedef SleepChoice = ({int minutes, bool finishSong});

/// The sleep timer: turn the knob to set the time, one ring for each hour. Null if cancelled.
Future<SleepChoice?> showSleepTimerDialog(BuildContext context,
        {int secondsLeft = 0, bool waiting = false, bool offerFinishSong = true}) =>
    showDialog<SleepChoice>(
      context: context,
      builder: (_) => _SleepTimerDialog(secondsLeft: secondsLeft, waiting: waiting, offerFinishSong: offerFinishSong),
    );

class _SleepTimerDialog extends StatefulWidget {
  const _SleepTimerDialog({required this.secondsLeft, required this.waiting, required this.offerFinishSong});

  final int secondsLeft;
  final bool waiting;
  final bool offerFinishSong;

  @override
  State<_SleepTimerDialog> createState() => _SleepTimerDialogState();
}

class _SleepTimerDialogState extends State<_SleepTimerDialog> {
  late int _minutes =
      (widget.secondsLeft > 0 ? (widget.secondsLeft / 60).ceil() : SleepTimerMemory.minutes).clamp(1, sleepTimerMost);
  late bool _finishSong = SleepTimerMemory.finishSong;

  String get _title {
    if (widget.waiting) return 'Sleep Timer: after this song';
    if (widget.secondsLeft > 0) return 'Sleep Timer: in ${(widget.secondsLeft / 60).ceil()} min';
    return 'Sleep Timer';
  }

  void _ok() {
    SleepTimerMemory.minutes = _minutes;
    SleepTimerMemory.finishSong = _finishSong;
    SleepTimerMemory.save?.call(_minutes, _finishSong).catchError((Object _) {});
    Navigator.pop<SleepChoice>(context, (minutes: _minutes, finishSong: widget.offerFinishSong && _finishSong));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final screen = MediaQuery.sizeOf(context);
    // The rest of the dialog needs about 380; a short screen gets a smaller knob.
    final dial = max(100.0, [280.0, screen.width - 128, screen.height - 380].reduce(min));
    final active = widget.secondsLeft > 0 || widget.waiting;
    return AlertDialog(
      // Only a very short screen scrolls: elsewhere turning the knob moves nothing else.
      scrollable: screen.height < 600,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      title: Row(
        children: [
          Icon(Icons.timelapse_rounded, color: theme.colorScheme.primary),
          const SizedBox(width: 12),
          Expanded(child: Text(_title, key: const Key('sleep-title'), style: theme.textTheme.titleMedium)),
        ],
      ),
      content: SizedBox(
        width: dial,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('$_minutes min',
                key: const Key('sleep-minutes'),
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SleepDial(size: dial, minutes: _minutes, onChanged: (m) => setState(() => _minutes = m)),
            if (widget.offerFinishSong)
              CheckboxListTile(
                key: const Key('sleep-finish-song'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Play last song to end'),
                value: _finishSong,
                onChanged: (v) => setState(() => _finishSong = v ?? false),
              ),
          ],
        ),
      ),
      actionsAlignment: MainAxisAlignment.spaceBetween,
      actions: [
        TextButton(
          key: const Key('sleep-disable'),
          onPressed: active ? () => Navigator.pop<SleepChoice>(context, (minutes: 0, finishSong: false)) : null,
          child: const Text('Disable'),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
            const SizedBox(width: 4),
            FilledButton.tonal(key: const Key('sleep-ok'), onPressed: _ok, child: const Text('OK')),
          ],
        ),
      ],
    );
  }
}

/// A knob turned with a finger. A full turn is an hour; each hour draws its own ring, further out.
class SleepDial extends StatefulWidget {
  const SleepDial({super.key, required this.size, required this.minutes, required this.onChanged});

  final double size;
  final int minutes;
  final ValueChanged<int> onChanged;

  @override
  State<SleepDial> createState() => _SleepDialState();
}

class _SleepDialState extends State<SleepDial> {
  /// The angle of the finger at the last move, and the time as turned so far (finer than minutes).
  double? _angle;
  double _turned = 0;

  /// Where the finger is around the middle, or null too near it to tell.
  double? _angleOf(Offset at) {
    final from = at - Offset(widget.size / 2, widget.size / 2);
    return from.distance < widget.size * 0.08 ? null : atan2(from.dy, from.dx);
  }

  void _move(Offset at) {
    final angle = _angleOf(at);
    final before = _angle;
    _angle = angle;
    if (angle == null || before == null) return;
    // The short way round, so passing the top does not jump a whole turn.
    var by = angle - before;
    if (by > pi) by -= 2 * pi;
    if (by < -pi) by += 2 * pi;
    // Held at the ends: turning back responds at once.
    _turned = (_turned + by / (2 * pi) * 60).clamp(1.0, sleepTimerMost.toDouble());
    final minutes = _turned.round();
    if (minutes != widget.minutes) {
      Haptics.selection();
      widget.onChanged(minutes);
    }
  }

  void _step(int by) => widget.onChanged((widget.minutes + by).clamp(1, sleepTimerMost));

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Semantics(
      slider: true,
      label: 'Sleep timer time',
      value: '${widget.minutes} minutes',
      increasedValue: '${widget.minutes + 1} minutes',
      decreasedValue: '${max(1, widget.minutes - 1)} minutes',
      onIncrease: () => _step(1),
      onDecrease: () => _step(-1),
      child: Listener(
        key: const Key('sleep-dial'),
        behavior: HitTestBehavior.opaque,
        onPointerDown: (e) {
          _turned = widget.minutes.toDouble();
          _angle = _angleOf(e.localPosition);
        },
        onPointerMove: (e) => _move(e.localPosition),
        onPointerUp: (_) => _angle = null,
        child: CustomPaint(
          size: Size.square(widget.size),
          painter: _DialPainter(widget.minutes, colors.primary, colors.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _DialPainter extends CustomPainter {
  _DialPainter(this.minutes, this.ring, this.notch);

  final int minutes;
  final Color ring;
  final Color notch;

  @override
  void paint(Canvas canvas, Size size) {
    final middle = size.center(Offset.zero);
    final half = size.width / 2;
    final knob = half * 0.58;
    canvas.drawCircle(middle, knob + 4, Paint()..color = Colors.white.withValues(alpha: 0.06));
    canvas.drawCircle(middle, knob, Paint()..color = Colors.black);

    // One ring for each hour begun, from the knob outwards; closer together when there are many.
    final rings = (minutes / 60).ceil();
    final first = knob + 9;
    final spacing = min(half * 0.13, (half - 4 - first) / max(1, rings - 1));
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = min(6.0, spacing * 0.65)
      ..color = ring;
    for (var i = 0; i < rings; i++) {
      final share = i < rings - 1 ? 1.0 : (minutes - i * 60) / 60;
      final box = Rect.fromCircle(center: middle, radius: first + i * spacing);
      if (share >= 1) {
        canvas.drawArc(box, 0, 2 * pi, false, line);
      } else {
        canvas.drawArc(box, -pi / 2, 2 * pi * share, false, line);
      }
    }

    final angle = (minutes % 60) / 60 * 2 * pi - pi / 2;
    final point = Offset(cos(angle), sin(angle));
    canvas.drawLine(
      middle + point * (knob * 0.66),
      middle + point * (knob * 0.80),
      Paint()
        ..strokeCap = StrokeCap.round
        ..strokeWidth = 8
        ..color = notch,
    );
  }

  @override
  bool shouldRepaint(_DialPainter old) => old.minutes != minutes || old.ring != ring || old.notch != notch;
}
