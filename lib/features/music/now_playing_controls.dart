import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../core/theme/app_theme.dart';

/// Speed as an icon in the quick-action row: the icon lights up (and says the
/// speed) when it is not normal.
class SpeedButton extends StatelessWidget {
  static const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  static String label(double v) => '${v.toString().replaceAll(RegExp(r'\.0$'), '')}\u00d7';

  const SpeedButton({super.key, required this.speed, required this.enabled, required this.onSet});

  final double speed;
  final bool enabled;
  final ValueChanged<double> onSet;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final changed = speed != 1.0;
    return PopupMenuButton<double>(
      tooltip: 'Set playback speed',
      enabled: enabled,
      onSelected: (v) {
        Haptics.selection();
        onSet(v);
      },
      itemBuilder: (_) => [
        for (final v in SpeedButton.speeds)
          CheckedPopupMenuItem(
            value: v,
            checked: v == speed,
            child: Text(v == 1.0 ? 'Normal (1\u00d7)' : SpeedButton.label(v)),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: changed
            ? Text(SpeedButton.label(speed),
                style: theme.textTheme.titleSmall?.copyWith(color: RtColors.violet))
            : Icon(Icons.speed_rounded, color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }
}

/// Sleep timer: pick a time, see it count down, cancel. The Player does the
/// pausing, so it works even if this phone disconnects.
class SleepTimerControl extends StatefulWidget {
  const SleepTimerControl({
    super.key,
    required this.secondsLeft,
    required this.enabled,
    required this.onSet,
    this.compact = false,
  });

  final int secondsLeft;
  final bool enabled;
  final ValueChanged<int> onSet;

  /// An icon for the quick-action row (shows the time left while it runs)
  /// instead of the full card.
  final bool compact;

  @override
  State<SleepTimerControl> createState() => SleepTimerControlState();
}

class SleepTimerControlState extends State<SleepTimerControl> {
  DateTime? _endsAt;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(SleepTimerControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.secondsLeft != widget.secondsLeft) _sync();
  }

  void _sync() {
    _tick?.cancel();
    if (widget.secondsLeft <= 0) {
      _endsAt = null;
      return;
    }
    _endsAt = DateTime.now().add(Duration(seconds: widget.secondsLeft));
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _left() {
    final end = _endsAt;
    if (end == null) return '';
    final s = end.difference(DateTime.now()).inSeconds.clamp(0, 999999);
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = _endsAt != null;
    if (widget.compact) {
      return PopupMenuButton<int>(
        tooltip: 'Set sleep timer',
        enabled: widget.enabled,
        onSelected: (m) {
          Haptics.selection();
          widget.onSet(m);
        },
        itemBuilder: (_) => [
          if (active) PopupMenuItem(value: 0, child: Text('Cancel (pauses in ${_left()})')),
          const PopupMenuItem(value: 15, child: Text('15 minutes')),
          const PopupMenuItem(value: 30, child: Text('30 minutes')),
          const PopupMenuItem(value: 45, child: Text('45 minutes')),
          const PopupMenuItem(value: 60, child: Text('1 hour')),
          const PopupMenuItem(value: 120, child: Text('2 hours')),
        ],
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: active
              ? Text(_left(),
                  style: theme.textTheme.titleSmall?.copyWith(color: RtColors.violet))
              : Icon(Icons.bedtime_rounded, color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.bedtime_rounded,
                color: active ? RtColors.violet : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                active ? 'Pauses in ${_left()}' : 'Sleep timer',
                style: theme.textTheme.titleSmall,
              ),
            ),
            if (active)
              TextButton(
                onPressed: widget.enabled ? () => widget.onSet(0) : null,
                child: const Text('Cancel'),
              ),
            PopupMenuButton<int>(
              tooltip: 'Set sleep timer',
              enabled: widget.enabled,
              onSelected: widget.onSet,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 15, child: Text('15 minutes')),
                PopupMenuItem(value: 30, child: Text('30 minutes')),
                PopupMenuItem(value: 45, child: Text('45 minutes')),
                PopupMenuItem(value: 60, child: Text('1 hour')),
                PopupMenuItem(value: 120, child: Text('2 hours')),
              ],
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(active ? 'Change' : 'Set',
                    style: TextStyle(color: theme.colorScheme.primary)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

