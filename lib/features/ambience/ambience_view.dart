import 'dart:async';

import 'package:flutter/material.dart';

import 'ambience_import.dart';
import 'ambience_models.dart';

/// What only the playing phone can do: give sounds their files and set the loudest allowed.
class AmbienceOwner {
  const AmbienceOwner({
    required this.pickFile,
    required this.addFile,
    required this.addOwnSound,
    required this.removeFile,
    required this.setMaxVolume,
    this.pickFolder,
  });

  /// Lets the owner choose a folder and gives the files in it, or null. Null: importing is not offered.
  final Future<List<String>?> Function()? pickFolder;

  /// Gives the path of a picked sound file, or null.
  final Future<String?> Function() pickFile;
  final Future<void> Function(String soundId, String path) addFile;
  final Future<void> Function(String name, String path) addOwnSound;
  final Future<void> Function(String soundId) removeFile;
  final Future<void> Function(double volume) setMaxVolume;
}

IconData ambienceIcon(AmbienceSound s) => switch (s.id) {
      'rain' => Icons.water_drop_rounded,
      'light-rain' => Icons.grain_rounded,
      'thunder' => Icons.thunderstorm_rounded,
      'distant-thunder' => Icons.bolt_rounded,
      'ocean' => Icons.waves_rounded,
      'seagulls' => Icons.flutter_dash,
      'stream' => Icons.water_rounded,
      'crickets' => Icons.nightlight_round,
      'owls' => Icons.dark_mode_rounded,
      'frogs' => Icons.pets_rounded,
      'campfire' => Icons.local_fire_department_rounded,
      'wind' => Icons.air_rounded,
      'birds' => Icons.park_rounded,
      'white-noise' || 'pink-noise' || 'brown-noise' => Icons.graphic_eq_rounded,
      _ => Icons.music_note_rounded,
    };

String _timerLabel(int minutes) => minutes < 60 ? '$minutes min' : '${minutes ~/ 60} hour${minutes >= 120 ? 's' : ''}';

String _left(int seconds) {
  final h = seconds ~/ 3600, m = (seconds % 3600) ~/ 60, s = seconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '$m:${two(s)}';
}

/// The Ambience screen: sounds as tiles to switch on, each with its volume; play, stop, the volume of
/// everything, the sleep timer and the mixes. The same on the playing phone and from the other one
/// ([owner] is then null).
class AmbienceView extends StatefulWidget {
  const AmbienceView({super.key, required this.controls, this.owner, this.enabled = true});

  final AmbienceControls controls;
  final AmbienceOwner? owner;

  /// False while the Controller is reconnecting.
  final bool enabled;

  @override
  State<AmbienceView> createState() => _AmbienceViewState();
}

class _AmbienceViewState extends State<AmbienceView> {
  /// Slider positions while a finger is on them.
  final Map<String, double> _dragging = {};

  AmbienceControls get _c => widget.controls;

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _run(Future<void> Function() action) async {
    if (!widget.enabled) return;
    try {
      await action();
      final error = _c.state.error;
      if (error != null) _snack(error);
    } catch (e) {
      _snack('$e');
    }
  }

  Future<void> _tap(AmbienceSound s) async {
    if (!s.available) {
      if (widget.owner == null) {
        _snack('Add a file for ${s.name} on the phone that plays.');
        return;
      }
      await _addFile(s);
      return;
    }
    await _run(() => _c.setActive(s.id, !_c.state.active.containsKey(s.id)));
  }

  Future<void> _addFile(AmbienceSound s) => _run(() async {
        final path = await widget.owner!.pickFile();
        if (path == null) return;
        await widget.owner!.addFile(s.id, path);
        await _c.setActive(s.id, true);
      });

  Future<void> _addOwn() => _run(() async {
        final path = await widget.owner!.pickFile();
        if (path == null || !mounted) return;
        final file = path.split(RegExp(r'[\\/]')).last;
        final dot = file.lastIndexOf('.');
        final name = await showDialog<String>(
          context: context,
          builder: (_) => _NameDialog(title: 'Name this sound', initial: dot > 0 ? file.substring(0, dot) : file),
        );
        if (name == null) return;
        await widget.owner!.addOwnSound(name, path);
      });

  /// Picks a folder, shows which sound each file would go to, and adds the ones agreed.
  Future<void> _importFolder() => _run(() async {
        final owner = widget.owner!;
        final paths = await owner.pickFolder!();
        if (paths == null || !mounted) return;
        final rows = planImport(paths, _c.state.sounds);
        if (rows.isEmpty) {
          _snack('No MP3, OGG, WAV or FLAC files in that folder.');
          return;
        }
        final agreed = await showDialog<bool>(
          context: context,
          builder: (_) => _ImportDialog(rows: rows, sounds: importTargets(_c.state.sounds)),
        );
        if (agreed != true || !mounted) return;
        final chosen = [for (final r in rows) if (r.target != AmbienceImportRow.skip) r];
        _snack('Adding ${chosen.length} sound${chosen.length == 1 ? '' : 's'}…');
        var added = 0;
        final failed = <String>[];
        for (final row in chosen) {
          try {
            if (row.target == AmbienceImportRow.newSound) {
              await owner.addOwnSound(row.newName, row.path);
            } else {
              await owner.addFile(row.target, row.path);
            }
            added++;
          } catch (_) {
            failed.add(row.fileName);
          }
        }
        _snack('Added $added sound${added == 1 ? '' : 's'}.${failed.isEmpty ? '' : " Couldn't add ${failed.join(', ')}."}');
      });

  Future<void> _fileMenu(AmbienceSound s) async {
    final owner = widget.owner;
    if (owner == null || !s.available) return;
    final noise = ambienceCatalog.any((x) => x.id == s.id && x.available);
    if (noise) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              key: const Key('amb-replace'),
              leading: const Icon(Icons.swap_horiz_rounded),
              title: Text('Choose another file for ${s.name}'),
              onTap: () => Navigator.pop(ctx, 'replace'),
            ),
            ListTile(
              key: const Key('amb-remove'),
              leading: const Icon(Icons.delete_outline_rounded),
              title: Text(s.category == ambienceOwnCategory ? 'Delete this sound' : 'Take its file away'),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'replace') {
      await _run(() async {
        final path = await owner.pickFile();
        if (path != null) await owner.addFile(s.id, path);
      });
    } else if (choice == 'remove') {
      await _run(() => owner.removeFile(s.id));
    }
  }

  Future<void> _timer() async {
    final choice = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('Sleep timer. The sound fades out over the last 5 minutes.'),
            ),
            for (final m in [0, ...ambienceTimers])
              ListTile(
                key: ValueKey('amb-timer-$m'),
                title: Text(m == 0 ? 'No timer' : _timerLabel(m)),
                trailing: (_c.state.timerMinutes ?? 0) == m ? const Icon(Icons.check_rounded) : null,
                onTap: () => Navigator.pop(ctx, m),
              ),
          ],
        ),
      ),
    );
    if (choice != null) await _run(() => _c.setTimer(choice == 0 ? null : choice));
  }

  Future<void> _mixes() async {
    final chosen = await showModalBottomSheet<({String? start, String? delete, bool save})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) {
        final state = _c.state;
        final own = [for (final m in state.mixes) if (!m.builtIn) m];
        final presets = [for (final m in state.mixes) if (m.builtIn) m];
        String names(AmbienceMix m) => [for (final id in m.layers.keys) state.sound(id)?.name ?? id].join(', ');
        Widget tile(AmbienceMix m) => ListTile(
              key: ValueKey('amb-mix-${m.id}'),
              title: Text(m.name),
              subtitle: Text(names(m), maxLines: 2, overflow: TextOverflow.ellipsis),
              trailing: m.builtIn
                  ? null
                  : IconButton(
                      key: ValueKey('amb-mix-delete-${m.id}'),
                      tooltip: 'Delete ${m.name}',
                      icon: const Icon(Icons.delete_outline_rounded),
                      onPressed: () => Navigator.pop(ctx, (start: null, delete: m.id, save: false)),
                    ),
              onTap: () => Navigator.pop(ctx, (start: m.id, delete: null, save: false)),
            );
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
            child: ListView(
              shrinkWrap: true,
              children: [
                if (state.active.isNotEmpty)
                  ListTile(
                    key: const Key('amb-mix-save'),
                    leading: const Icon(Icons.favorite_border_rounded),
                    title: Text('Save what is on (${state.active.length}) as a mix'),
                    onTap: () => Navigator.pop(ctx, (start: null, delete: null, save: true)),
                  ),
                if (own.isNotEmpty) const _Heading('Your mixes'),
                for (final m in own) tile(m),
                const _Heading('Ready-made'),
                for (final m in presets) tile(m),
              ],
            ),
          ),
        );
      },
    );
    if (chosen == null || !mounted) return;
    if (chosen.save) {
      final name = await showDialog<String>(
        context: context,
        builder: (_) => _NameDialog(title: 'Name this mix', initial: _c.state.mixName ?? ''),
      );
      if (name != null) await _run(() => _c.saveMix(name));
    } else if (chosen.delete case final id?) {
      await _run(() => _c.deleteMix(id));
    } else if (chosen.start case final id?) {
      await _run(() async {
        final missing = await _c.startMix(id);
        if (missing.isNotEmpty) _snack('Playing without ${missing.join(', ')}: no file yet.');
      });
    }
  }

  Future<void> _maxVolume() async {
    final owner = widget.owner!;
    final value = await showDialog<double>(context: context, builder: (_) => _MaxDialog(initial: _c.state.maxVolume));
    if (value != null) await _run(() => owner.setMaxVolume(value));
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final theme = Theme.of(context);
        final state = _c.state;
        if (state.sounds.isEmpty) {
          return state.error == null
              ? const Center(child: CircularProgressIndicator())
              : Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(state.error!, textAlign: TextAlign.center)));
        }
        final categories = <String>{for (final s in state.sounds) s.category, if (widget.owner != null) ambienceOwnCategory};
        return Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, box) {
                  final columns = (box.maxWidth / 112).floor().clamp(3, 8);
                  final width = (box.maxWidth - 24) / columns;
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    children: [
                      if (widget.owner?.pickFolder != null)
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            key: const Key('amb-import'),
                            onPressed: widget.enabled ? _importFolder : null,
                            icon: const Icon(Icons.drive_folder_upload_rounded),
                            label: const Text('Import a folder'),
                          ),
                        ),
                      for (final c in categories) ...[
                        _Heading(c),
                        Wrap(
                          children: [
                            for (final s in state.sounds.where((s) => s.category == c))
                              SizedBox(width: width, child: _tile(theme, state, s)),
                            if (c == ambienceOwnCategory && widget.owner != null) SizedBox(width: width, child: _addTile(theme)),
                          ],
                        ),
                      ],
                    ],
                  );
                },
              ),
            ),
            _bar(theme, state),
          ],
        );
      },
    );
  }

  Widget _square(ThemeData theme, {required Color color, required Widget child}) => Material(
        color: color,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(width: 64, height: 64, child: Center(child: child)),
      );

  Widget _tile(ThemeData theme, AmbienceState state, AmbienceSound s) {
    final on = state.active.containsKey(s.id);
    final volume = _dragging[s.id] ?? state.active[s.id] ?? 0;
    final colors = theme.colorScheme;
    return Column(
      children: [
        Semantics(
          button: true,
          selected: on,
          label: '${s.name}${s.available ? '' : ', add a file'}',
          excludeSemantics: true,
          child: InkWell(
            key: ValueKey('amb-sound-${s.id}'),
            borderRadius: BorderRadius.circular(18),
            onTap: widget.enabled ? () => _tap(s) : null,
            onLongPress: widget.enabled && widget.owner != null ? () => _fileMenu(s) : null,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Stack(
                children: [
                  _square(
                    theme,
                    color: on ? colors.primary : colors.surfaceContainerHighest,
                    child: Icon(ambienceIcon(s),
                        size: 30,
                        color: on ? colors.onPrimary : colors.onSurfaceVariant.withValues(alpha: s.available ? 1 : 0.35)),
                  ),
                  if (!s.available)
                    Positioned(
                      right: 4,
                      bottom: 4,
                      child: Icon(Icons.add_circle_rounded, key: ValueKey('amb-add-${s.id}'), size: 18, color: colors.primary),
                    ),
                ],
              ),
            ),
          ),
        ),
        Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
        SizedBox(
          height: 36,
          child: on
              ? SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    trackHeight: 3,
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    key: ValueKey('amb-volume-${s.id}'),
                    value: volume.clamp(0.0, 1.0),
                    label: '${(volume * 100).round()}',
                    semanticFormatterCallback: (v) => '${s.name} volume ${(v * 100).round()} percent',
                    onChanged: widget.enabled ? (v) => setState(() => _dragging[s.id] = v) : null,
                    onChangeEnd: (v) async {
                      await _run(() => _c.setVolume(s.id, v));
                      if (mounted) setState(() => _dragging.remove(s.id));
                    },
                  ),
                )
              : null,
        ),
      ],
    );
  }

  Widget _addTile(ThemeData theme) => Column(
        children: [
          InkWell(
            key: const Key('amb-add-own'),
            borderRadius: BorderRadius.circular(18),
            onTap: widget.enabled ? _addOwn : null,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: _square(theme, color: theme.colorScheme.surfaceContainerHigh, child: const Icon(Icons.add_rounded, size: 30)),
            ),
          ),
          Text('Add a sound', style: theme.textTheme.bodySmall),
        ],
      );

  Widget _bar(ThemeData theme, AmbienceState state) {
    final master = _dragging['*'] ?? state.master;
    final count = state.active.length;
    final timer = state.timerMinutes;
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                [
                  state.mixName ?? (count == 0 ? 'Tap a sound to begin' : '$count sound${count == 1 ? '' : 's'} on'),
                  if (state.mixName != null) '$count sound${count == 1 ? '' : 's'}',
                  if (timer != null) '${_left(state.secondsLeft ?? timer * 60)} left',
                ].join(' · '),
                key: const Key('amb-status'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
              Row(
                children: [
                  const Icon(Icons.volume_up_rounded, size: 20),
                  Expanded(
                    child: Slider(
                      key: const Key('amb-master'),
                      value: master.clamp(0.0, 1.0),
                      semanticFormatterCallback: (v) => 'Ambience volume ${(v * 100).round()} percent',
                      // The slider stops at the loudest allowed.
                      onChanged: widget.enabled ? (v) => setState(() => _dragging['*'] = v.clamp(0.0, state.maxVolume)) : null,
                      onChangeEnd: (v) async {
                        await _run(() => _c.setMaster(v.clamp(0.0, state.maxVolume)));
                        if (mounted) setState(() => _dragging.remove('*'));
                      },
                    ),
                  ),
                  SizedBox(width: 32, child: Text('${(master * 100).round()}', textAlign: TextAlign.end)),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  IconButton(key: const Key('amb-mixes'), tooltip: 'Mixes', icon: const Icon(Icons.favorite_rounded), onPressed: widget.enabled ? _mixes : null),
                  IconButton.filled(
                    key: const Key('amb-play'),
                    tooltip: state.playing ? 'Pause' : 'Play',
                    iconSize: 32,
                    icon: Icon(state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    onPressed: widget.enabled && count > 0 ? () => _run(state.playing ? _c.pause : _c.play) : null,
                  ),
                  IconButton(key: const Key('amb-stop'), tooltip: 'Stop', icon: const Icon(Icons.stop_rounded), onPressed: widget.enabled ? () => _run(_c.stop) : null),
                  IconButton(
                    key: const Key('amb-timer'),
                    tooltip: 'Sleep timer',
                    icon: Icon(timer == null ? Icons.timer_outlined : Icons.timer_rounded, color: timer == null ? null : theme.colorScheme.primary),
                    onPressed: widget.enabled ? _timer : null,
                  ),
                  if (widget.owner != null)
                    IconButton(key: const Key('amb-max'), tooltip: 'Maximum volume', icon: const Icon(Icons.hearing_rounded), onPressed: _maxVolume),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 8),
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );
}

class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.title, this.initial = ''});
  final String title;
  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final _field = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  void _save() {
    if (_field.text.trim().isNotEmpty) Navigator.pop(context, _field.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          key: const Key('amb-name'),
          controller: _field,
          autofocus: true,
          maxLength: 40,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => _save(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(key: const Key('amb-name-save'), onPressed: _save, child: const Text('Save')),
        ],
      );
}

class _MaxDialog extends StatefulWidget {
  const _MaxDialog({required this.initial});
  final double initial;

  @override
  State<_MaxDialog> createState() => _MaxDialogState();
}

class _MaxDialogState extends State<_MaxDialog> {
  late double _value = widget.initial;

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Maximum volume'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('The ambience never plays louder than this, also when controlled from the other phone. '
                'The phone\'s own volume buttons still apply, so set those for the room too.'),
            Slider(key: const Key('amb-max-slider'), value: _value, onChanged: (v) => setState(() => _value = v)),
            Text('${(_value * 100).round()}%'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(key: const Key('amb-max-save'), onPressed: () => Navigator.pop(context, _value), child: const Text('Save')),
        ],
      );
}

/// Which sound each file of a folder goes to; each can be changed or left out.
class _ImportDialog extends StatefulWidget {
  const _ImportDialog({required this.rows, required this.sounds});

  final List<AmbienceImportRow> rows;
  final List<AmbienceSound> sounds;

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  /// Gives [row] a new destination. A sound takes one file: whoever had it becomes a new sound.
  void _choose(AmbienceImportRow row, String target) => setState(() {
        if (target != AmbienceImportRow.newSound && target != AmbienceImportRow.skip) {
          for (final other in widget.rows) {
            if (other != row && other.target == target) other.target = AmbienceImportRow.newSound;
          }
        }
        row.target = target;
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = widget.rows.where((r) => r.target != AmbienceImportRow.skip).length;
    return Dialog.fullscreen(
      child: Scaffold(
        appBar: AppBar(
          leading: IconButton(
            key: const Key('amb-import-cancel'),
            tooltip: 'Cancel',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Import sounds'),
        ),
        body: ListView.builder(
          itemCount: widget.rows.length + 1,
          itemBuilder: (context, i) {
            if (i == 0) {
              return const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Text('Each file was matched by its name. Check them, and change any that is wrong.'),
              );
            }
            final row = widget.rows[i - 1];
            final replaces = widget.sounds.any((s) => s.id == row.target && s.available);
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(row.fileName, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                  DropdownButton<String>(
                    key: ValueKey('amb-import-to-${row.fileName}'),
                    isExpanded: true,
                    value: row.target,
                    items: [
                      DropdownMenuItem(
                          value: AmbienceImportRow.newSound,
                          child: Text('New sound "${row.newName}"', overflow: TextOverflow.ellipsis)),
                      const DropdownMenuItem(value: AmbienceImportRow.skip, child: Text('Leave it out')),
                      for (final s in widget.sounds) DropdownMenuItem(value: s.id, child: Text(s.name, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) {
                      if (v != null) _choose(row, v);
                    },
                  ),
                  if (replaces)
                    Text('Replaces the file it has now',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.tertiary)),
                ],
              ),
            );
          },
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton(
              key: const Key('amb-import-go'),
              onPressed: count == 0 ? null : () => Navigator.pop(context, true),
              child: Text('Import $count sound${count == 1 ? '' : 's'}'),
            ),
          ),
        ),
      ),
    );
  }
}
