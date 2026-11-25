import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/haptics.dart';
import '../../../providers/connection_providers.dart';
import 'eq_model.dart';
import 'equalizer_controller.dart';

/// The equalizer page, for the music that plays on this phone.
class EqualizerScreen extends ConsumerWidget {
  const EqualizerScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final core = ref.watch(playerCoreProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Equalizer')),
      body: SafeArea(
        child: core.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (_, __) =>
              const Center(child: Text('The player could not start. Try again.')),
          data: (c) => EqualizerView(controller: c.equalizer),
        ),
      ),
    );
  }
}

/// The controls themselves (separate from the page so they can be tested).
class EqualizerView extends StatefulWidget {
  const EqualizerView({super.key, required this.controller});

  final EqualizerController controller;

  @override
  State<EqualizerView> createState() => _EqualizerViewState();
}

class _EqualizerViewState extends State<EqualizerView> with WidgetsBindingObserver {
  EqualizerController get c => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    c.refreshOutput();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) c.refreshOutput();
  }

  static String _db(double v) => '${v > 0 ? '+' : ''}${v.toStringAsFixed(1)} dB';

  static String _outputName(String route) => switch (route) {
        'speaker' => 'the phone speaker',
        'wired' => 'wired headphones',
        'bluetooth' => 'Bluetooth',
        _ => 'this output',
      };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final theme = Theme.of(context);
        final bands = c.bands;
        final s = c.settings;
        if (bands == null) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'The equalizer starts working once a song has been played on this phone. '
                'Play any song, then come back.\n\n(If this phone has no equalizer, it is not available.)',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          );
        }
        final ten = s.tenBand;
        final gains = ten
            ? (s.tenGains.length == EqPreset.tenCenters.length
                ? s.tenGains
                : List.filled(EqPreset.tenCenters.length, 0.0))
            : (s.gains.length == bands.count ? s.gains : List.filled(bands.count, 0.0));
        return ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Equalizer'),
              subtitle: const Text('Changes how the music on this phone sounds.'),
              value: s.enabled,
              onChanged: (v) {
                Haptics.selection();
                c.setEnabled(v);
              },
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final p in EqPreset.all)
                  ChoiceChip(
                    label: Text(p.name),
                    selected: s.enabled && s.preset == p.name,
                    onSelected: (_) {
                      Haptics.selection();
                      c.applyPreset(p);
                    },
                  ),
                if (s.preset == null && s.gains.isNotEmpty)
                  const ChoiceChip(label: Text('Custom'), selected: true),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              key: const Key('eq-mode'),
              showSelectedIcon: false,
              segments: [
                ButtonSegment(value: false, label: Text('${bands.count} bands (phone)')),
                const ButtonSegment(value: true, label: Text('10 bands')),
              ],
              selected: {ten},
              onSelectionChanged: (v) {
                Haptics.selection();
                c.setTenBand(v.first);
              },
            ),
            if (ten)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  "This phone's equalizer really has ${bands.count} bands, so the ten sliders are "
                  'blended onto them: neighbouring sliders work together.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
            const SizedBox(height: 16),
            // What the sound will look like: the bands and the Tone knobs together.
            Opacity(
              opacity: s.enabled ? 1 : 0.45,
              child: SizedBox(
                height: 96,
                child: CustomPaint(
                  key: const Key('eq-curve'),
                  painter: EqCurvePainter(
                    bands: bands,
                    gains: s.effectiveGains(bands),
                    line: theme.colorScheme.primary,
                    grid: theme.colorScheme.outlineVariant,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Opacity(
              opacity: s.enabled ? 1 : 0.45,
              child: SizedBox(
                height: 280,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < gains.length; i++)
                      Expanded(
                        child: Column(
                          children: [
                            Text(
                              '${gains[i] > 0 ? '+' : ''}${gains[i].toStringAsFixed(1)}',
                              style: theme.textTheme.labelSmall,
                            ),
                            Expanded(
                              child: RotatedBox(
                                quarterTurns: 3,
                                child: Slider(
                                  min: bands.minDb,
                                  max: bands.maxDb,
                                  value: gains[i].clamp(bands.minDb, bands.maxDb),
                                  onChanged: (v) => ten ? c.setTenBandGain(i, v) : c.setBand(i, v),
                                  onChangeEnd: (_) {
                                    Haptics.selection();
                                    c.commit();
                                  },
                                ),
                              ),
                            ),
                            Text(ten ? EqPreset.tenLabel(i) : bands.labelFor(i),
                                style: theme.textTheme.labelSmall),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: c.reset,
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Reset to flat'),
              ),
            ),
            const Divider(),
            // Preamp: the overall level before the bands.
            Row(
              children: [
                SizedBox(
                  width: 96,
                  child: Text('Preamp\n${_db(s.preampDb)}', style: theme.textTheme.bodyMedium),
                ),
                Expanded(
                  child: Slider(
                    min: -EqSettings.preampRange,
                    max: EqSettings.preampRange,
                    divisions: 48,
                    value: s.preampDb,
                    onChanged: c.setPreamp,
                    onChangeEnd: (_) => c.commit(),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Tone'),
              subtitle: const Text('Bass and Treble knobs on top of the bands.'),
              value: s.toneOn,
              onChanged: (v) {
                Haptics.selection();
                c.setToneOn(v);
              },
            ),
            Opacity(
              opacity: s.toneOn ? 1 : 0.45,
              child: Column(
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 96,
                        child: Text('Bass\n${_db(s.bassDb)}', style: theme.textTheme.bodyMedium),
                      ),
                      Expanded(
                        child: Slider(
                          min: -EqSettings.toneRange,
                          max: EqSettings.toneRange,
                          divisions: 40,
                          value: s.bassDb,
                          onChanged: c.setBass,
                          onChangeEnd: (_) => c.commit(),
                        ),
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      SizedBox(
                        width: 96,
                        child: Text('Treble\n${_db(s.trebleDb)}', style: theme.textTheme.bodyMedium),
                      ),
                      Expanded(
                        child: Slider(
                          min: -EqSettings.toneRange,
                          max: EqSettings.toneRange,
                          divisions: 40,
                          value: s.trebleDb,
                          onChanged: c.setTreble,
                          onChangeEnd: (_) => c.commit(),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Limit'),
              subtitle: const Text(
                  'Turns everything down by as much as the bands boost, so loud music does not distort.'),
              value: s.limit,
              onChanged: (v) {
                Haptics.selection();
                c.setLimit(v);
              },
            ),
            const Divider(),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Remember for ${_outputName(c.output)}'),
              subtitle: const Text(
                  'These settings come back by themselves whenever the sound goes to this output.'),
              value: c.savedForOutput,
              onChanged: c.setSavedForOutput,
            ),
          ],
        );
      },
    );
  }
}

/// The sound as a line: how much each frequency is raised or lowered.
class EqCurvePainter extends CustomPainter {
  EqCurvePainter({
    required this.bands,
    required this.gains,
    required this.line,
    required this.grid,
  });

  final EqBands bands;
  final List<double> gains;
  final Color line;
  final Color grid;

  static const _lowHz = 20.0;
  static const _highHz = 20000.0;

  /// Where a frequency sits across the width (0 to 1), on a log scale.
  static double xFor(double hz) =>
      ((math.log(hz) - math.log(_lowHz)) / (math.log(_highHz) - math.log(_lowHz))).clamp(0.0, 1.0);

  /// The curve's gain at [hz]: smooth between the band centers.
  double gainAt(double hz) {
    final c = bands.centersHz;
    if (c.isEmpty || gains.length != c.length) return 0;
    if (hz <= c.first) return gains.first;
    if (hz >= c.last) return gains.last;
    for (var i = 0; i < c.length - 1; i++) {
      if (hz <= c[i + 1]) {
        final t = (math.log(hz) - math.log(c[i])) / (math.log(c[i + 1]) - math.log(c[i]));
        final eased = (1 - math.cos(t * math.pi)) / 2;
        return gains[i] + (gains[i + 1] - gains[i]) * eased;
      }
    }
    return gains.last;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final range = math.max(bands.maxDb, -bands.minDb);
    double yFor(double db) => size.height / 2 - (db / range) * (size.height / 2 - 4);

    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, yFor(0)), Offset(size.width, yFor(0)), gridPaint);
    for (final hz in [100.0, 1000.0, 10000.0]) {
      final x = xFor(hz) * size.width;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint..color = grid.withValues(alpha: 0.4));
    }

    final path = Path();
    const steps = 120;
    for (var i = 0; i <= steps; i++) {
      final t = i / steps;
      final hz = math.exp(math.log(_lowHz) + t * (math.log(_highHz) - math.log(_lowHz)));
      final p = Offset(t * size.width, yFor(gainAt(hz)));
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..strokeJoin = StrokeJoin.round,
    );
    final dot = Paint()..color = line;
    for (var i = 0; i < bands.count && i < gains.length; i++) {
      canvas.drawCircle(Offset(xFor(bands.centersHz[i]) * size.width, yFor(gains[i])), 3.5, dot);
    }
  }

  @override
  bool shouldRepaint(EqCurvePainter old) =>
      old.gains != gains || old.bands != bands || old.line != line;
}
