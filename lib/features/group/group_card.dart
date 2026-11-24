import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../music/music_source.dart' show friendlyError;
import 'group_models.dart';
import 'group_providers.dart';

/// "Play on this phone too": this phone plays the Player's song in step with
/// it. Hidden where group play is not possible (the web Controller).
class GroupCard extends ConsumerStatefulWidget {
  const GroupCard({super.key, required this.enabled});

  /// False while the Controller is reconnecting.
  final bool enabled;

  @override
  ConsumerState<GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends ConsumerState<GroupCard> {
  bool _aligning = false;

  void _snack(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _toggle(GroupFollower f, bool value) async {
    try {
      value ? await f.join() : await f.leave();
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  Future<void> _autoAlign(GroupFollower f) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Auto-align'),
        content: const Text(
          'This listens with the microphone and measures exactly how much '
          'later or earlier this phone sounds than the Player, then fixes the '
          'fine-tune for you.\n\n'
          '1. Put the two phones side by side, about 10 cm apart.\n'
          '2. Turn both volumes up, in a quiet room.\n'
          '3. Keep still and quiet for about 15 seconds.\n\n'
          'The Player plays a series of clicks, first on its own, then this '
          'phone. Nothing is saved or sent anywhere.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Start')),
        ],
      ),
    );
    if (go != true || !mounted) return;
    setState(() => _aligning = true);
    try {
      final r = await f.autoAlign();
      _snack(r.message);
    } catch (e) {
      _snack(friendlyError(e));
    } finally {
      if (mounted) setState(() => _aligning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final follower = ref.watch(groupFollowerProvider);
    if (follower == null) return const SizedBox.shrink();
    final status = ref.watch(groupStatusProvider).valueOrNull ?? follower.status;
    final theme = Theme.of(context);
    final on = status.isOn;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.speaker_group_rounded,
                    color: on ? RtColors.teal : theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('Play on this phone too', style: theme.textTheme.titleSmall),
                ),
                Switch(
                  value: on,
                  onChanged: widget.enabled && !_aligning && (on || status.available)
                      ? (v) => _toggle(follower, v)
                      : null,
                ),
              ],
            ),
            if (!on)
              Text(
                status.available
                    ? 'This phone plays the same song as the Player, in sync. '
                        'Both phones must be on the same Wi-Fi.'
                    : 'Needs a connection over the same Wi-Fi (not the internet).',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              )
            else ...[
              const SizedBox(height: 4),
              _StatusLine(status: status),
              if (status.warning.isNotEmpty) ...[
                const SizedBox(height: 6),
                _Warning(text: status.warning),
              ],
              const SizedBox(height: 8),
              _Readout(status: status),
              const SizedBox(height: 8),
              _AutoAlign(
                busy: _aligning,
                enabled: widget.enabled && status.phase == GroupPhase.playing,
                note: status.calibration,
                onStart: () => _autoAlign(follower),
                onCancel: follower.cancelAutoAlign,
              ),
              const SizedBox(height: 8),
              Text(
                'Fine-tune${status.route == 'speaker' ? '' : ' (${status.route})'}',
                style: theme.textTheme.labelLarge,
              ),
              Text(
                'If this phone sounds late, move it to +. If early, to −. '
                'Saved separately for each way the sound comes out.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Earlier by 5 ms',
                    icon: const Icon(Icons.remove_rounded),
                    onPressed: !_aligning && status.nudgeMs > -300
                        ? () => follower.setNudgeMs(status.nudgeMs - 5)
                        : null,
                  ),
                  Expanded(
                    child: Slider(
                      value: status.nudgeMs.toDouble(),
                      min: -300,
                      max: 300,
                      divisions: 120,
                      label: '${status.nudgeMs > 0 ? '+' : ''}${status.nudgeMs} ms',
                      onChanged:
                          _aligning ? null : (v) => follower.setNudgeMs(v.round()),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Later by 5 ms',
                    icon: const Icon(Icons.add_rounded),
                    onPressed: !_aligning && status.nudgeMs < 300
                        ? () => follower.setNudgeMs(status.nudgeMs + 5)
                        : null,
                  ),
                ],
              ),
              Row(
                children: [
                  Text('${status.nudgeMs > 0 ? '+' : ''}${status.nudgeMs} ms',
                      style: theme.textTheme.bodyMedium),
                  const Spacer(),
                  TextButton(
                    onPressed: _aligning ? null : follower.resync,
                    child: const Text('Measure again'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _AutoAlign extends StatelessWidget {
  const _AutoAlign({
    required this.busy,
    required this.enabled,
    required this.note,
    required this.onStart,
    required this.onCancel,
  });

  final bool busy;
  final bool enabled;
  final String note;
  final VoidCallback onStart;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: busy
                  ? FilledButton.tonalIcon(
                      onPressed: onCancel,
                      icon: const Icon(Icons.close_rounded),
                      label: const Text('Cancel'),
                    )
                  : FilledButton.tonalIcon(
                      onPressed: enabled ? onStart : null,
                      icon: const Icon(Icons.mic_rounded),
                      label: const Text('Auto-align (uses the microphone)'),
                    ),
            ),
          ],
        ),
        if (busy) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(),
        ],
        if (note.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(note,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ] else if (!busy && !enabled)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              'Available once it says "Playing in sync".',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
      ],
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: RtColors.warning.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: RtColors.warning.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.warning_amber_rounded, size: 18, color: RtColors.warning),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.status});

  final GroupStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (IconData icon, Color color, String text) = switch (status.phase) {
      GroupPhase.playing => (Icons.graphic_eq_rounded, RtColors.teal, 'Playing in sync'),
      GroupPhase.downloading =>
        (Icons.downloading_rounded, RtColors.violet, status.message),
      GroupPhase.syncing => (Icons.sync_rounded, RtColors.warning, status.message),
      GroupPhase.problem =>
        (Icons.error_outline_rounded, theme.colorScheme.error, status.message),
      _ => (Icons.pause_circle_outline_rounded, theme.colorScheme.onSurfaceVariant,
          status.message.isEmpty ? 'Joined. Waiting for the Player.' : status.message),
    };
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: theme.textTheme.bodyMedium?.copyWith(color: color))),
      ],
    );
  }
}

/// The numbers: how the two clocks compare and how far the sound is off.
class _Readout extends StatelessWidget {
  const _Readout({required this.status});

  final GroupStatus status;

  String _ms(double? v, {bool signed = false}) => v == null
      ? '…'
      : '${signed && v > 0 ? '+' : ''}${v.round()} ms';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final drift = status.driftMs;
    final good = drift != null && drift.abs() <= 30;
    Widget row(String label, String value, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1),
          child: Row(
            children: [
              Expanded(
                  child: Text(label,
                      style: theme.textTheme.bodySmall?.copyWith(color: muted))),
              Text(value,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: color, fontWeight: FontWeight.w600)),
            ],
          ),
        );
    return Column(
      children: [
        row('Off by (this phone vs Player)', drift == null ? '–' : _ms(drift, signed: true),
            color: drift == null ? null : (good ? RtColors.teal : RtColors.warning)),
        row('Connection delay (round trip)', _ms(status.rttMs)),
        row('Clock difference spread', _ms(status.spreadMs)),
        if (status.outputLatencyMs != null)
          row("This phone's own audio delay", _ms(status.outputLatencyMs?.toDouble())),
      ],
    );
  }
}
