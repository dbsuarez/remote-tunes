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
        final gains = s.gains.length == bands.count ? s.gains : List.filled(bands.count, 0.0);
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
            const SizedBox(height: 16),
            Opacity(
              opacity: s.enabled ? 1 : 0.45,
              child: SizedBox(
                height: 280,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = 0; i < bands.count; i++)
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
                                  onChanged: (v) => c.setBand(i, v),
                                  onChangeEnd: (_) {
                                    Haptics.selection();
                                    c.commit();
                                  },
                                ),
                              ),
                            ),
                            Text(bands.labelFor(i), style: theme.textTheme.labelSmall),
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
