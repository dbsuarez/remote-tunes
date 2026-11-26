import 'dart:async';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import 'ambience_icons.dart';
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
    this.setIcon,
  });

  /// Gives a sound an icon from the library (null: its usual one). Null: not offered.
  final Future<void> Function(String soundId, String? icon)? setIcon;

  /// Lets the owner choose a folder and gives the files in it, or null. Null: importing is not offered.
  final Future<List<String>?> Function()? pickFolder;

  /// Gives the path of a picked sound file, or null.
  final Future<String?> Function() pickFile;
  final Future<void> Function(String soundId, String path) addFile;
  final Future<void> Function(String name, String path, {bool environment}) addOwnSound;
  final Future<void> Function(String soundId) removeFile;
  final Future<void> Function(double volume) setMaxVolume;
}

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

  /// The page shown: a category, or null for every sound that is ready to play.
  String? _category;

  final _pages = PageController();
  final Map<String?, GlobalKey> _chipKeys = {};

  /// The pages as last built, to stay on the same group when one appears or goes.
  List<String?> _pageList = const [null];

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  /// Keeps the chip of the page shown in view.
  void _revealChip(String? category) => WidgetsBinding.instance.addPostFrameCallback((_) {
        final context = _chipKeys[category]?.currentContext;
        if (context != null && context.mounted) {
          Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 200));
        }
      });

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
            if (row.target == AmbienceImportRow.newSound || row.target == AmbienceImportRow.newEnvironment) {
              await owner.addOwnSound(row.newName, row.path, environment: row.target == AmbienceImportRow.newEnvironment);
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
    // A built-in noise has no file to change.
    if (noise && owner.setIcon == null) return;
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (owner.setIcon != null)
              ListTile(
                key: const Key('amb-icon'),
                leading: AmbiencePicture(ambienceIconName(s), size: 24),
                title: Text('Change the picture of ${s.name}'),
                onTap: () => Navigator.pop(ctx, 'icon'),
              ),
            if (!noise) ListTile(
              key: const Key('amb-replace'),
              leading: const Icon(Icons.swap_horiz_rounded),
              title: Text('Choose another file for ${s.name}'),
              onTap: () => Navigator.pop(ctx, 'replace'),
            ),
            if (!noise) ListTile(
              key: const Key('amb-remove'),
              leading: const Icon(Icons.delete_outline_rounded),
              title: Text(isOwnAmbienceSound(s) ? 'Delete this sound' : 'Take its file away'),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
          ],
        ),
      ),
    );
    if (choice == 'icon') {
      if (!mounted) return;
      final picked = await showModalBottomSheet<({String? icon})>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => _IconSheet(sound: s),
      );
      if (picked != null) await _run(() => owner.setIcon!(s.id, picked.icon));
    } else if (choice == 'replace') {
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
        String names(AmbienceMix m) => [
              for (final id in m.layers.keys)
                state.sound(id)?.name ?? ambienceCatalog.where((s) => s.id == id).map((s) => s.name).firstOrNull ?? id,
            ].join(', ');
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
        // A page for what is ready, then one for each category; swipe between them or tap a chip. The owner
        // can always add a sound of their own.
        final all = <String>{for (final s in state.sounds) s.category, if (widget.owner != null) ambienceOwnCategory};
        final pages = <String?>[null, ...all];
        final chosen = pages.contains(_category) ? _category : null;
        if (!listEquals(pages, _pageList)) {
          _pageList = pages;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _pages.hasClients) _pages.jumpToPage(pages.indexOf(chosen));
          });
        }
        Widget chip(String? value, String label) => Padding(
              key: _chipKeys[value] ??= GlobalKey(),
              padding: const EdgeInsets.only(right: 6),
              child: ChoiceChip(
                key: ValueKey('amb-cat-${value ?? 'ready'}'),
                showCheckmark: false,
                visualDensity: VisualDensity.compact,
                label: Text(label),
                selected: chosen == value,
                onSelected: (_) {
                  setState(() => _category = value);
                  _revealChip(value);
                  if (_pages.hasClients) _pages.jumpToPage(pages.indexOf(value));
                },
              ),
            );
        return Column(
          children: [
            SizedBox(
              height: 52,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
                child: Row(children: [chip(null, 'Ready'), for (final c in all) chip(c, c)]),
              ),
            ),
            Expanded(
              child: PageView.builder(
                key: const Key('amb-pages'),
                controller: _pages,
                itemCount: pages.length,
                onPageChanged: (i) {
                  if (i >= pages.length || pages[i] == _category) return;
                  setState(() => _category = pages[i]);
                  _revealChip(pages[i]);
                },
                itemBuilder: (context, i) => _page(theme, state, all, pages[i]),
              ),
            ),
            _bar(theme, state),
          ],
        );
      },
    );
  }

  /// One page: the sounds ready to play (by category), or every place of one category.
  Widget _page(ThemeData theme, AmbienceState state, Set<String> all, String? page) {
    final owner = widget.owner;
    bool visible(AmbienceSound s) => page == null ? s.available : s.category == page;
    final categories = [
      for (final c in all)
        if (page == c ||
            (page == null && (state.sounds.any((s) => s.category == c && s.available) || (c == ambienceOwnCategory && owner != null))))
          c,
    ];
    return LayoutBuilder(
      builder: (context, box) {
        final columns = (box.maxWidth / 112).floor().clamp(3, 8);
        final width = (box.maxWidth - 24) / columns;
        return ListView(
          key: PageStorageKey('amb-list-${page ?? 'ready'}'),
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          children: [
            if (owner?.pickFolder != null && (page == null || page == ambienceOwnCategory))
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
              _Heading(c, key: ValueKey('amb-group-$c')),
              if (owner?.setIcon != null && (c == ambienceOwnCategory || c == ambienceEnvironmentCategory))
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Text('Hold a sound to change its picture.', style: theme.textTheme.bodySmall),
                ),
              Wrap(
                children: [
                  for (final s in state.sounds.where((s) => s.category == c && visible(s)))
                    SizedBox(width: width, child: _tile(theme, state, s)),
                  if (c == ambienceOwnCategory && owner != null) SizedBox(width: width, child: _addTile(theme)),
                ],
              ),
            ],
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
                    child: AmbiencePicture(ambienceIconName(s),
                        color: on ? colors.onPrimary : colors.onSurfaceVariant, faded: !s.available),
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
  const _Heading(this.text, {super.key});
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
        // Only a sound itself takes one file; any number can be new, or left out.
        if (!target.startsWith('+')) {
          for (final other in widget.rows) {
            if (other != row && other.target == target) other.target = AmbienceImportRow.newSound;
          }
        }
        row.target = target;
      });

  String _labelOf(AmbienceImportRow row) => switch (row.target) {
        AmbienceImportRow.newSound => 'New sound "${row.newName}"',
        AmbienceImportRow.newEnvironment => 'Environment "${row.newName}"',
        AmbienceImportRow.skip => 'Leave it out',
        final id => widget.sounds.where((s) => s.id == id).map((s) => '${s.name} (${s.category})').firstOrNull ?? id,
      };

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
                  OutlinedButton.icon(
                    key: ValueKey('amb-import-to-${row.fileName}'),
                    icon: const Icon(Icons.expand_more_rounded),
                    label: Text(_labelOf(row), maxLines: 1, overflow: TextOverflow.ellipsis),
                    onPressed: () async {
                      final target = await showModalBottomSheet<String>(
                        context: context,
                        showDragHandle: true,
                        isScrollControlled: true,
                        builder: (_) => _TargetSheet(row: row, sounds: widget.sounds),
                      );
                      if (target != null && mounted) _choose(row, target);
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

/// The picture library, to choose a sound's emoji or icon from, with a search.
class _IconSheet extends StatefulWidget {
  const _IconSheet({required this.sound});

  final AmbienceSound sound;

  @override
  State<_IconSheet> createState() => _IconSheetState();
}

class _IconSheetState extends State<_IconSheet> {
  String _query = '';
  bool _emoji = true;

  /// The groups to show: name and (kept value, label) pairs.
  List<({String group, List<({String value, String label})> pictures})> _groups() {
    final q = _query.trim().toLowerCase();
    final out = <({String group, List<({String value, String label})> pictures})>[];
    // An emoji typed or pasted into the search is offered as it is.
    if (q.isNotEmpty && q.runes.first > 0x2000 && q.length < 12) {
      final typed = _query.trim();
      out.add((group: 'Yours', pictures: [(value: '$ambienceEmojiPrefix$typed', label: typed)]));
    }
    // A search looks through both kinds.
    if (_emoji || q.isNotEmpty) {
      for (final g in ambienceEmoji.entries) {
        final found = <({String value, String label})>[];
        for (final entry in g.value) {
          final space = entry.indexOf(' ');
          final picture = entry.substring(0, space);
          final words = entry.substring(space + 1);
          if (q.isEmpty || words.contains(q) || g.key.toLowerCase().contains(q)) {
            found.add((value: '$ambienceEmojiPrefix$picture', label: words));
          }
        }
        if (found.isNotEmpty) out.add((group: g.key, pictures: found));
      }
    }
    if (!_emoji || q.isNotEmpty) {
      for (final g in ambienceIconGroups.entries) {
        final found = [
          for (final name in g.value.keys)
            if (q.isEmpty || name.contains(q) || g.key.toLowerCase().contains(q)) (value: name, label: name.replaceAll('-', ' ')),
        ];
        if (found.isNotEmpty) out.add((group: q.isEmpty ? g.key : '${g.key} (icons)', pictures: found));
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final current = ambienceIconName(widget.sound);
    final groups = _groups();
    return Padding(
      // Above the keyboard while searching.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Picture for ${widget.sound.name}',
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                        ),
                        TextButton(
                          key: const Key('amb-icon-usual'),
                          onPressed: () => Navigator.pop(context, (icon: null)),
                          child: const Text('Use the usual'),
                        ),
                      ],
                    ),
                    TextField(
                      key: const Key('amb-icon-search'),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search_rounded),
                        hintText: 'Search (frog, rain...) or type an emoji',
                        isDense: true,
                      ),
                      onChanged: (v) => setState(() => _query = v),
                    ),
                    if (_query.trim().isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            ChoiceChip(
                              key: const Key('amb-icon-tab-emoji'),
                              label: const Text('Emoji'),
                              selected: _emoji,
                              onSelected: (_) => setState(() => _emoji = true),
                            ),
                            const SizedBox(width: 8),
                            ChoiceChip(
                              key: const Key('amb-icon-tab-icons'),
                              label: const Text('Icons'),
                              selected: !_emoji,
                              onSelected: (_) => setState(() => _emoji = false),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: groups.isEmpty
                    ? const Center(child: Text('Nothing found. Try another word, or type an emoji.'))
                    : CustomScrollView(
                        key: ValueKey('amb-icons-$_emoji'),
                        slivers: [
                          for (final g in groups) ...[
                            SliverToBoxAdapter(child: _Heading(g.group)),
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              sliver: SliverGrid.builder(
                                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                    maxCrossAxisExtent: 60, mainAxisSpacing: 6, crossAxisSpacing: 6),
                                itemCount: g.pictures.length,
                                itemBuilder: (context, i) {
                                  final picture = g.pictures[i];
                                  final chosen = picture.value == current;
                                  return Tooltip(
                                    message: picture.label,
                                    child: Material(
                                      color: chosen ? colors.primary : colors.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(14),
                                      child: InkWell(
                                        key: ValueKey('amb-icon-${picture.value}'),
                                        borderRadius: BorderRadius.circular(14),
                                        onTap: () => Navigator.pop(context, (icon: picture.value)),
                                        child: Center(
                                          child: AmbiencePicture(picture.value,
                                              size: 28, color: chosen ? colors.onPrimary : colors.onSurfaceVariant),
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                          const SliverToBoxAdapter(child: SizedBox(height: 16)),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where one imported file can go: a new sound, an environment, nowhere, or one of the sounds (searched
/// by name). Gives the target.
class _TargetSheet extends StatefulWidget {
  const _TargetSheet({required this.row, required this.sounds});

  final AmbienceImportRow row;
  final List<AmbienceSound> sounds;

  @override
  State<_TargetSheet> createState() => _TargetSheetState();
}

class _TargetSheetState extends State<_TargetSheet> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final q = _query.trim().toLowerCase();
    final found = [
      for (final s in widget.sounds)
        if (q.isEmpty || s.name.toLowerCase().contains(q) || s.category.toLowerCase().contains(q)) s,
    ];
    final fixed = [
      (AmbienceImportRow.newSound, 'New sound "${row.newName}"', Icons.add_rounded),
      (AmbienceImportRow.newEnvironment, 'Environment "${row.newName}"', Icons.landscape_rounded),
      (AmbienceImportRow.skip, 'Leave it out', Icons.block_rounded),
    ];
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  key: const Key('amb-target-search'),
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.search_rounded), hintText: 'Search the sounds', isDense: true),
                  onChanged: (v) => setState(() => _query = v),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: (q.isEmpty ? fixed.length : 0) + found.length,
                  itemBuilder: (context, i) {
                    if (q.isEmpty && i < fixed.length) {
                      final (target, label, icon) = fixed[i];
                      return ListTile(
                        key: ValueKey('amb-target-$target'),
                        leading: Icon(icon),
                        title: Text(label),
                        selected: row.target == target,
                        onTap: () => Navigator.pop(context, target),
                      );
                    }
                    final sound = found[i - (q.isEmpty ? fixed.length : 0)];
                    return ListTile(
                      key: ValueKey('amb-target-${sound.id}'),
                      leading: AmbiencePicture(ambienceIconName(sound), size: 24),
                      title: Text(sound.name),
                      subtitle: Text(sound.available ? '${sound.category} · has a file' : sound.category),
                      selected: row.target == sound.id,
                      onTap: () => Navigator.pop(context, sound.id),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
