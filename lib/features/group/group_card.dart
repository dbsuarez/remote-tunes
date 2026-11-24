import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../music/music_source.dart' show friendlyError;
import 'group_models.dart';
import 'group_providers.dart';

/// "Play on this phone too": this phone plays the Player's song in step with
/// it. Hidden where group play is not possible (the web Controller).
class GroupCard extends ConsumerWidget {
  const GroupCard({super.key, required this.enabled});

  /// False while the Controller is reconnecting.
  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final follower = ref.watch(groupFollowerProvider);
    if (follower == null) return const SizedBox.shrink();
    final status = ref.watch(groupStatusProvider).valueOrNull ?? follower.status;
    final theme = Theme.of(context);
    final on = status.isOn;

    Future<void> toggle(bool value) async {
      try {
        value ? await follower.join() : await follower.leave();
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(content: Text(friendlyError(e))));
        }
      }
    }

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
                  onChanged: enabled && (on || status.available) ? toggle : null,
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
              const SizedBox(height: 8),
              _Readout(status: status),
              const SizedBox(height: 8),
              Text('Fine-tune', style: theme.textTheme.labelLarge),
              Text(
                'If this phone sounds late, move it to +. If early, to −.',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              Row(
                children: [
                  IconButton(
                    tooltip: 'Earlier by 5 ms',
                    icon: const Icon(Icons.remove_rounded),
                    onPressed: status.nudgeMs > -300
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
                      onChanged: (v) => follower.setNudgeMs(v.round()),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Later by 5 ms',
                    icon: const Icon(Icons.add_rounded),
                    onPressed: status.nudgeMs < 300
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
                    onPressed: follower.resync,
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
      ],
    );
  }
}
