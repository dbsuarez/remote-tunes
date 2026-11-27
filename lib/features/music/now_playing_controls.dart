import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../core/widgets/haptic_button.dart';
import '../../core/theme/app_theme.dart';
import 'sleep_timer_dialog.dart';

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

/// Sleep timer: opens the dial. The Player does the pausing, so it works even if this phone
/// disconnects.
class SleepTimerControl extends StatefulWidget {
  const SleepTimerControl({
    super.key,
    required this.secondsLeft,
    required this.enabled,
    required this.onSet,
    this.afterSong = false,
    this.offerFinishSong = true,
    this.compact = false,
    this.onNight,
  });

  /// Opens the night screen, offered in the dialog (null: not offered).
  final VoidCallback? onNight;

  final int secondsLeft;

  /// The time is up and the last song is playing to its end.
  final bool afterSong;

  /// Whether "Play last song to end" can be offered (not for another app's music).
  final bool offerFinishSong;
  final bool enabled;

  /// Minutes (0 switches it off), and whether the last song plays to its end.
  final void Function(int minutes, bool finishSong) onSet;

  /// A button for the quick-action row (lit while the timer is on) instead of the full card.
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
    // Only the card counts down.
    if (widget.compact) return;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  int get _seconds => _endsAt?.difference(DateTime.now()).inSeconds.clamp(0, 999999) ?? 0;

  String _left() => '${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}';

  Future<void> _open() async {
    final choice = await showSleepTimerDialog(context,
        secondsLeft: _seconds,
        waiting: widget.afterSong,
        offerFinishSong: widget.offerFinishSong,
        onNight: widget.onNight);
    if (choice != null && mounted) widget.onSet(choice.minutes, choice.finishSong);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final active = _endsAt != null || widget.afterSong;
    if (widget.compact) {
      return HapticButton(
        kind: HapticKind.selection,
        tooltip: 'Set sleep timer',
        isSelected: active,
        onPressed: widget.enabled ? _open : null,
        icon: Icon(Icons.bedtime_rounded, color: active ? theme.colorScheme.primary : null),
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
        child: Row(
          children: [
            Icon(Icons.bedtime_rounded, color: active ? RtColors.violet : theme.colorScheme.onSurfaceVariant),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.afterSong ? 'Pauses after this song' : (active ? 'Pauses in ${_left()}' : 'Sleep timer'),
                style: theme.textTheme.titleSmall,
              ),
            ),
            if (active)
              TextButton(
                onPressed: widget.enabled ? () => widget.onSet(0, false) : null,
                child: const Text('Cancel'),
              ),
            TextButton(
              key: const Key('sleep-card-set'),
              onPressed: widget.enabled ? _open : null,
              child: Text(active ? 'Change' : 'Set'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Volume as an icon in the quick-action row. Pressing it shows a small
/// vertical slider to adjust the volume; tap anywhere else to put it away.
class VolumeButton extends StatelessWidget {
  const VolumeButton({
    super.key,
    required this.volume,
    required this.enabled,
    required this.onChanged,
  });

  /// 0.0 to 1.0.
  final double volume;
  final bool enabled;
  final ValueChanged<double> onChanged;

  static IconData iconFor(double v) => v <= 0.001
      ? Icons.volume_off_rounded
      : (v < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PopupMenuButton<void>(
      tooltip: 'Volume',
      enabled: enabled,
      icon: Icon(iconFor(volume), color: theme.colorScheme.onSurfaceVariant),
      itemBuilder: (_) => [
        PopupMenuItem<void>(
          enabled: false,
          padding: EdgeInsets.zero,
          child: _VerticalVolume(initial: volume, onChanged: onChanged),
        ),
      ],
    );
  }
}

class _VerticalVolume extends StatefulWidget {
  const _VerticalVolume({required this.initial, required this.onChanged});

  final double initial;
  final ValueChanged<double> onChanged;

  @override
  State<_VerticalVolume> createState() => _VerticalVolumeState();
}

class _VerticalVolumeState extends State<_VerticalVolume> {
  late double _value = widget.initial.clamp(0.0, 1.0);
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _change(double v) {
    setState(() => _value = v);
    // While dragging, send now and then rather than on every pixel.
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () => widget.onChanged(v));
  }

  void _end(double v) {
    _debounce?.cancel();
    Haptics.selection();
    widget.onChanged(v);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: 64,
      height: 220,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Text('${(_value * 100).round()}%', style: theme.textTheme.labelMedium),
          Expanded(
            child: RotatedBox(
              quarterTurns: 3,
              child: Slider(
                value: _value,
                onChanged: _change,
                onChangeEnd: _end,
              ),
            ),
          ),
          Icon(VolumeButton.iconFor(_value), size: 20, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}
