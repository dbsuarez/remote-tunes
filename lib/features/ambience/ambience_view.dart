import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';

import 'ambience_banner.dart';
import 'ambience_beats.dart';
import 'ambience_icons.dart';
import 'ambience_import.dart';
import 'ambience_manage.dart';
import 'ambience_models.dart';
import 'ambience_night.dart';
import 'ambience_style.dart';

/// A group's own banner as the view needs it.
typedef AmbienceBannerView = ({ImageProvider image, String? sourcePath, BannerFraming framing});

/// Reading and keeping the owner's banner pictures (by group name).
class AmbienceBanners {
  const AmbienceBanners({required this.of, required this.pick, required this.read, required this.set, required this.remove});

  final AmbienceBannerView? Function(String group) of;

  /// Gives the path of a picked picture, or null.
  final Future<String?> Function() pick;
  final Future<Uint8List> Function(String path) read;
  final Future<void> Function(String group, Uint8List png, BannerFraming framing, {String? newSource}) set;
  final Future<void> Function(String group) remove;
}

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
    this.setBoost,
    this.banners,
    this.schedule,
    this.setSchedule,
    this.nextStart,
    this.night = false,
    this.watchedFolder,
    this.watchFolder,
    this.checkFolder,
    this.rename,
    this.listBanners,
    this.setListBanners,
    this.organizer,
  });

  /// Categories, moving and ordering sounds, and their switches. Null: not offered.
  final AmbienceOrganizer? organizer;

  /// Renames one of the owner's own sounds. Null: not offered.
  final Future<void> Function(String soundId, String name)? rename;

  /// Whether the list of groups shows banners instead of circles, and changing that. Null: circles only.
  final bool Function()? listBanners;
  final Future<void> Function(bool banners)? setListBanners;

  /// The bedtime schedule (null: not offered).
  final AmbienceSchedule Function()? schedule;
  final Future<void> Function(AmbienceSchedule schedule)? setSchedule;
  final DateTime? Function()? nextStart;

  /// Whether night mode (a nearly black screen) is offered.
  final bool night;

  /// Pictures of the owner's own across the top of the groups. Null: not offered.
  final AmbienceBanners? banners;

  /// Makes one sound louder or softer (1 is as it comes). Null: not offered.
  final Future<void> Function(String soundId, double boost)? setBoost;

  /// The folder new files are picked up from, or null.
  final String? Function()? watchedFolder;

  /// Remembers a folder to pick new files up from (null: stop).
  final Future<void> Function(String? folder)? watchFolder;

  /// Connects the new files of the remembered folder; gives the names of the sounds that got one.
  final Future<List<String>> Function()? checkFolder;

  /// Gives a sound an icon from the library (null: its usual one). Null: not offered.
  final Future<void> Function(String soundId, String? icon)? setIcon;

  /// Lets the owner choose a folder and gives the files in it, or null. Null: importing is not offered.
  final Future<List<String>?> Function()? pickFolder;

  /// Gives the path of a picked sound file, or null.
  final Future<String?> Function() pickFile;
  final Future<void> Function(String soundId, String path) addFile;
  final Future<void> Function(String name, String path, {bool environment, String? category}) addOwnSound;
  final Future<void> Function(String soundId) removeFile;
  final Future<void> Function(double volume) setMaxVolume;
}

/// A frequency without needless zeros.
String _hz(double v) => v.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');

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
  const AmbienceView({super.key, required this.controls, this.owner, this.enabled = true, this.title = 'Ambience'});

  /// The name in the bar at the top.
  final String title;

  final AmbienceControls controls;
  final AmbienceOwner? owner;

  /// False while the Controller is reconnecting.
  final bool enabled;

  @override
  State<AmbienceView> createState() => _AmbienceViewState();
}

class _AmbienceViewState extends State<AmbienceView> with WidgetsBindingObserver {
  /// Slider positions while a finger is on them.
  final Map<String, double> _dragging = {};

  AmbienceControls get _c => widget.controls;

  /// The page of the sounds switched on (not a category name).
  static const _selected = '+selected';

  /// The page shown: a category, [_selected], or null for every sound that is ready to play.
  String? _category;

  final _pages = PageController();

  /// How far a finger has gone sideways over the banner.
  double _swipe = 0;

  /// The pages as last built, to stay on the same group when one appears or goes.
  List<String?> _pageList = const [null];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkFolder());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pages.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from a file manager or a download: there may be new files.
    if (state == AppLifecycleState.resumed) _checkFolder();
  }

  bool _checking = false;

  /// Picks up new files from the remembered folder. Says nothing unless something came in, or [asked].
  Future<void> _checkFolder({bool asked = false}) async {
    final check = widget.owner?.checkFolder;
    if (check == null || _checking) return;
    _checking = true;
    try {
      final added = await check();
      if (added.isNotEmpty) {
        _snack('Added from your folder: ${added.join(', ')}');
      } else if (asked) {
        _snack('No new files with a matching name.');
      }
    } catch (_) {
      if (asked) _snack("The folder couldn't be read.");
    } finally {
      _checking = false;
    }
  }

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

  Future<void> _addOwn([String? category]) => _run(() async {
        final path = await widget.owner!.pickFile();
        if (path == null || !mounted) return;
        final file = path.split(RegExp(r'[\\/]')).last;
        final dot = file.lastIndexOf('.');
        final name = await showDialog<String>(
          context: context,
          builder: (_) => _NameDialog(title: 'Name this sound', initial: dot > 0 ? file.substring(0, dot) : file),
        );
        if (name == null) return;
        await widget.owner!.addOwnSound(name, path, category: category);
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
        // From now on, new files here that are named like a sound connect by themselves.
        final first = paths.first;
        final cut = first.lastIndexOf(RegExp(r'[\\/]'));
        if (cut > 0) await owner.watchFolder?.call(first.substring(0, cut));
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
    final organizer = owner?.organizer;
    if (owner == null || (!s.available && organizer == null)) return;
    final noise = ambienceCatalog.any((x) => x.id == s.id && x.available);
    final tones = beatTones(s.id);
    // A sound the app makes has no file to change.
    if (noise && owner.setIcon == null && owner.setBoost == null && organizer == null) return;
    // Switches set for the whole category cannot be changed here.
    final group = organizer?.categories.where((c) => c.id == s.category).firstOrNull;
    final forced = {
      if (group?.once ?? false) ambienceFlagOnce,
      if (group?.alone ?? false) ambienceFlagAlone,
      if ((group?.headphones ?? false) || isAmbienceBeat(s.id)) ambienceFlagHeadphones,
    };
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (tones != null)
              ListTile(
                key: const Key('amb-tones'),
                leading: const Icon(Icons.headphones_rounded),
                title: Text('Left ear ${_hz(tones.left)} Hz · Right ear ${_hz(tones.right)} Hz'),
                subtitle: Text('A beat of ${_hz(tones.right - tones.left)} Hz. Use headphones.'),
              ),
            if (owner.rename != null && isOwnAmbienceSound(s))
              ListTile(
                key: const Key('amb-rename'),
                leading: const Icon(Icons.edit_rounded),
                title: Text('Rename ${s.name}'),
                onTap: () => Navigator.pop(ctx, 'rename'),
              ),
            if (owner.setIcon != null)
              ListTile(
                key: const Key('amb-icon'),
                leading: AmbiencePicture(ambienceIconName(s), size: 24),
                title: Text('Change the picture of ${s.name}'),
                onTap: () => Navigator.pop(ctx, 'icon'),
              ),
            if (owner.setBoost != null && s.available)
              ListTile(
                key: const Key('amb-boost'),
                leading: const Icon(Icons.volume_up_rounded),
                title: Text('Make ${s.name} louder or softer'),
                subtitle: s.boost == 1 ? null : Text('Now ${(s.boost * 100).round()}%'),
                onTap: () => Navigator.pop(ctx, 'boost'),
              ),
            if (!noise && s.available) ListTile(
              key: const Key('amb-replace'),
              leading: const Icon(Icons.swap_horiz_rounded),
              title: Text('Choose another file for ${s.name}'),
              onTap: () => Navigator.pop(ctx, 'replace'),
            ),
            if (!noise && (s.available || s.own)) ListTile(
              key: const Key('amb-remove'),
              leading: const Icon(Icons.delete_outline_rounded),
              title: Text(isOwnAmbienceSound(s) ? 'Delete this sound' : 'Take its file away'),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
            if (organizer != null) ...[
              ListTile(
                key: const Key('amb-move'),
                leading: const Icon(Icons.drive_file_move_outline),
                title: Text('Move ${s.name} to another category'),
                onTap: () => Navigator.pop(ctx, 'move'),
              ),
              const Divider(height: 1),
              AmbienceSwitches(
                own: () => organizer.soundFlags(s.id),
                set: (flag, on) => _run(() => organizer.setSoundFlag(s.id, flag, on)),
                forced: forced,
                forcedBy: isAmbienceBeat(s.id) && !(group?.once ?? false) && !(group?.alone ?? false)
                    ? 'These always need them'
                    : 'Set for the whole category',
              ),
            ],
          ],
          ),
        ),
      ),
    );
    if (choice == 'rename') {
      if (!mounted) return;
      final name = await showDialog<String>(
        context: context,
        builder: (_) => _NameDialog(title: 'Rename this sound', initial: s.name, maxLength: 30),
      );
      if (name != null) await _run(() => owner.rename!(s.id, name));
    } else if (choice == 'move') {
      if (!mounted) return;
      final to = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final c in organizer!.categories)
                  ListTile(
                    key: ValueKey('amb-move-to-${c.id}'),
                    leading: CircleAvatar(backgroundColor: ambienceColor(c.id), radius: 12),
                    title: Text(c.name),
                    trailing: c.id == s.category ? const Icon(Icons.check_rounded) : null,
                    onTap: () => Navigator.pop(ctx, c.id),
                  ),
              ],
            ),
          ),
        ),
      );
      if (to != null && to != s.category) await _run(() => organizer!.moveSound(s.id, to));
    } else if (choice == 'boost') {
      if (!mounted) return;
      final boost = await showDialog<double>(context: context, builder: (_) => _BoostDialog(sound: s));
      if (boost != null) await _run(() => owner.setBoost!(s.id, boost));
    } else if (choice == 'icon') {
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
        bool has(String id) => state.sound(id)?.available ?? false;
        // Those that can play now come first.
        final presets = [
          for (final playable in [true, false])
            for (final m in state.mixes)
              if (m.builtIn && m.layers.keys.any(has) == playable) m,
        ];
        String name(String id) =>
            state.sound(id)?.name ?? ambienceCatalog.where((s) => s.id == id).map((s) => s.name).firstOrNull ?? id;
        String names(AmbienceMix m) => [for (final id in m.layers.keys) name(id)].join(', ');
        String? needs(AmbienceMix m) {
          final missing = [for (final id in m.layers.keys) if (!has(id)) name(id)];
          return missing.isEmpty ? null : 'Needs: ${missing.join(', ')}';
        }

        Widget tile(AmbienceMix m) => ListTile(
              key: ValueKey('amb-mix-${m.id}'),
              title: Text(m.name),
              subtitle: Text([names(m), if (needs(m) case final n?) n].join('\n'), maxLines: 3, overflow: TextOverflow.ellipsis),
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

  String _titleOf(String? page, AmbienceState state) => switch (page) {
        null => 'Ready',
        _selected => state.active.isEmpty ? 'Selected' : 'Selected (${state.active.length})',
        final c => state.categoryName(c),
      };

  void _goTo(List<String?> pages, String? page) {
    setState(() => _category = page);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pages.hasClients) return;
      _pages.jumpToPage(pages.indexOf(page));
      // A page that has only just been added (on the management screen) is not measured yet, and the
      // jump reports the one before it: the title follows what was asked for.
      if (_category != page) setState(() => _category = page);
    });
  }

  Future<void> _editSchedule() async {
    final owner = widget.owner!;
    final chosen = await showDialog<AmbienceSchedule>(
      context: context,
      builder: (_) => _ScheduleDialog(initial: owner.schedule!(), state: _c.state),
    );
    if (chosen == null) return;
    await _run(() => owner.setSchedule!(chosen));
    if (mounted) setState(() {});
  }

  void _night() => Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute<void>(builder: (_) => AmbienceNightScreen(controls: _c, nextStart: widget.owner?.nextStart)),
      );

  /// The banner height set last, offered for the next new picture.
  double? _lastAspect;

  /// The name a page's banner is kept under.
  String _groupOf(String? page) => switch (page) { null => 'Ready', _selected => 'Selected', final c => c };

  /// Chooses, moves or takes away the banner picture of a group.
  Future<void> _editBanner(String group) async {
    final banners = widget.owner!.banners!;
    final current = banners.of(group);
    var choice = 'new';
    if (current != null) {
      final picked = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (current.sourcePath != null)
                  ListTile(
                    key: const Key('banner-move'),
                    leading: const Icon(Icons.crop_rounded),
                    title: const Text('Move and zoom this picture'),
                    onTap: () => Navigator.pop(ctx, 'move'),
                  ),
                ListTile(
                  key: const Key('banner-new'),
                  leading: const Icon(Icons.image_rounded),
                  title: const Text('Choose another picture'),
                  onTap: () => Navigator.pop(ctx, 'new'),
                ),
                ListTile(
                  key: const Key('banner-remove'),
                  leading: const Icon(Icons.delete_outline_rounded),
                  title: const Text('Take the picture away'),
                  onTap: () => Navigator.pop(ctx, 'remove'),
                ),
              ],
            ),
          ),
        ),
      );
      if (picked == null) return;
      choice = picked;
    }
    await _run(() async {
      if (choice == 'remove') return banners.remove(group);
      final path = choice == 'move' ? current!.sourcePath! : await banners.pick();
      if (path == null) return;
      final bytes = await banners.read(path);
      if (!mounted) return;
      final result = await Navigator.of(context).push<BannerResult>(MaterialPageRoute(
        builder: (_) => BannerCropScreen(
          bytes: bytes,
          group: _c.state.categoryName(group),
          // A new picture keeps the height this banner (or the last one set) has.
          framing: choice == 'move'
              ? current!.framing
              : BannerFraming(aspect: current?.framing.aspect ?? _lastAspect ?? ambienceBannerAspect),
        ),
      ));
      if (result == null) return;
      _lastAspect = result.framing.aspect;
      await banners.set(group, result.png, result.framing, newSource: choice == 'move' ? null : path);
    });
  }

  /// Every page in one list, to jump to: with circles, or with each group's banner.
  Future<void> _groups(List<String?> pages) async {
    final owner = widget.owner;
    var banners = owner?.setListBanners != null && (owner!.listBanners?.call() ?? false);
    final choice = await showModalBottomSheet<({String? page})>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, redraw) {
          final state = _c.state;
          void pick(String? page) => Navigator.pop(ctx, (page: page));
          void style(bool value) {
            redraw(() => banners = value);
            _run(() => owner!.setListBanners!(value));
          }

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (owner?.setListBanners != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                      child: Wrap(
                        alignment: WrapAlignment.center,
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            key: const Key('amb-list-circles'),
                            label: const Text('Circles'),
                            selected: !banners,
                            onSelected: (_) => style(false),
                          ),
                          ChoiceChip(
                            key: const Key('amb-list-banners'),
                            label: const Text('Banners'),
                            selected: banners,
                            onSelected: (_) => style(true),
                          ),
                        ],
                      ),
                    ),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final page in pages)
                            if (banners) _groupBanner(ctx, state, page, () => pick(page)) else _groupRow(state, page, () => pick(page)),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
    if (choice != null && mounted) _goTo(pages, choice.page);
  }

  Key _groupKey(String? page) => ValueKey('amb-cat-${page == _selected ? 'selected' : page ?? 'ready'}');

  Color _colorOf(String? page) => ambienceColor(page == _selected ? ambienceSelectedPage : page);

  Widget _groupRow(AmbienceState state, String? page, VoidCallback onTap) {
    final own = widget.owner?.banners?.of(_groupOf(page));
    return ListTile(
      key: _groupKey(page),
      leading: CircleAvatar(backgroundColor: _colorOf(page), foregroundImage: own?.image, radius: 18),
      title: Text(_titleOf(page, state)),
      trailing: page == _category ? const Icon(Icons.check_rounded) : null,
      onTap: onTap,
    );
  }

  Widget _groupBanner(BuildContext context, AmbienceState state, String? page, VoidCallback onTap) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: Semantics(
          button: true,
          selected: page == _category,
          child: InkWell(
            key: _groupKey(page),
            borderRadius: BorderRadius.circular(16),
            onTap: onTap,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SizedBox(
                height: 100,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _art(state, page),
                    if (page == _category)
                      const Positioned(top: 8, right: 8, child: Icon(Icons.check_circle_rounded, color: Colors.white)),
                    Positioned(
                      right: 8,
                      bottom: 8,
                      left: 8,
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(12)),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: Text(_titleOf(page, state),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  bool _needsPhones(AmbienceState state, String? page) =>
      ambienceNeedsHeadphones(page) || state.categoryList.any((c) => c.id == page && c.headphones);

  /// A group's picture: the owner's own, or its color with some of its sounds. A faint pair of
  /// headphones lies over the groups that need them.
  Widget _art(AmbienceState state, String? page) {
    final own = widget.owner?.banners?.of(_groupOf(page));
    final shown = [
      for (final s in state.sounds)
        if (switch (page) { null => s.available, _selected => state.active.containsKey(s.id), final c => s.category == c }) s,
    ].take(5).toList();
    final phones = _needsPhones(state, page);
    return Stack(
      fit: StackFit.expand,
      children: [
        if (own != null)
          Image(
            key: const Key('amb-banner-picture'),
            image: own.image,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => ColoredBox(color: _colorOf(page)),
          )
        else
          ColoredBox(
            color: Color.alphaBlend(Colors.white.withValues(alpha: 0.10), _colorOf(page)),
            child: phones
                ? null
                : ExcludeSemantics(
                    child: Center(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < shown.length; i++)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: AmbiencePicture(ambienceIconName(shown[i]), size: i.isEven ? 64 : 46, color: Colors.white54),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        if (phones)
          ExcludeSemantics(
            child: FittedBox(
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(Icons.headphones_rounded, key: const Key('amb-headphones-art'), color: Colors.white.withValues(alpha: 0.22)),
              ),
            ),
          ),
      ],
    );
  }

  /// A sideways swipe over the banner turns the page, as over the sounds.
  void _turn(List<String?> pages, double velocity) {
    final way = velocity.abs() > 300 ? -velocity.sign : (_swipe.abs() > 50 ? -_swipe.sign : 0.0);
    _swipe = 0;
    if (way == 0 || !_pages.hasClients) return;
    final next = pages.indexOf(pages.contains(_category) ? _category : null) + way.toInt();
    if (next < 0 || next >= pages.length) return;
    _pages.animateToPage(next, duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
  }

  void _headphonesInfo() => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          icon: const Icon(Icons.headphones_rounded),
          title: const Text('Use headphones'),
          content: const Text('A binaural beat is two tones a little apart, one for each ear; the beat is what you hear '
              'between them. It needs stereo headphones. On a speaker the two tones just blend together.'),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );

  void _folderInfo(String folder) => showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Watched folder'),
          content: Text('New files in "${folder.split(RegExp(r'[\\/]')).last}" named like a sound are added by themselves.',
              key: const Key('amb-watching')),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );

  Future<void> _manage(AmbienceOwner owner) async {
    final at = _category;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AmbienceManageScreen(
        controls: _c,
        organizer: owner.organizer!,
        onSound: _fileMenu,
        onAddSound: _addOwn,
        onBanner: owner.banners == null ? null : _editBanner,
        bannerOf: owner.banners == null ? null : (id) => owner.banners!.of(id)?.image,
      ),
    ));
    // Back on the group left, wherever it is in the order now.
    if (mounted) _goTo(_pageList, _pageList.contains(at) ? at : null);
  }

  /// The buttons at the top right: about the watched folder, and a menu of what is not needed often.
  List<Widget> _actions(String? page) {
    final owner = widget.owner;
    if (owner == null) return const [];
    final folder = owner.watchedFolder?.call();
    PopupMenuItem<String> item(String key, IconData icon, String text) => PopupMenuItem(
          key: Key(key),
          value: key,
          child: Row(children: [Icon(icon, size: 22), const SizedBox(width: 12), Flexible(child: Text(text))]),
        );
    final items = [
      if (owner.organizer != null) item('amb-manage', Icons.tune_rounded, 'Categories and sounds'),
      if (owner.banners != null) item('amb-banner-edit', Icons.add_photo_alternate_outlined, 'Banner picture'),
      if (owner.pickFolder != null) item('amb-import', Icons.drive_folder_upload_rounded, 'Import a folder'),
      if (owner.pickFolder != null && owner.checkFolder != null) item('amb-check', Icons.refresh_rounded, 'Rescan the folder'),
      if (folder != null && owner.watchFolder != null) item('amb-unwatch', Icons.link_off_rounded, 'Stop watching the folder'),
    ];
    return [
      if (folder != null)
        IconButton(
          key: const Key('amb-info'),
          tooltip: 'About the watched folder',
          icon: const Icon(Icons.info_outline_rounded),
          onPressed: () => _folderInfo(folder),
        ),
      if (items.isNotEmpty)
        PopupMenuButton<String>(
          key: const Key('amb-menu'),
          enabled: widget.enabled,
          onSelected: (choice) {
            switch (choice) {
              case 'amb-manage':
                _manage(owner);
              case 'amb-banner-edit':
                _editBanner(_groupOf(page));
              case 'amb-import':
                _importFolder();
              case 'amb-check':
                folder == null ? _snack('Import a folder first. Rescan then picks up its new files.') : _checkFolder(asked: true);
              case 'amb-unwatch':
                _run(() => owner.watchFolder!(null));
            }
          },
          itemBuilder: (_) => items,
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _c,
      builder: (context, _) {
        final state = _c.state;
        if (state.sounds.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: Text(widget.title)),
            body: state.error == null
                ? const Center(child: CircularProgressIndicator())
                : Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(state.error!, textAlign: TextAlign.center))),
          );
        }
        // A page for what is ready, one for what is on, then one for each group; swipe between them, or tap
        // the title for the list. The owner can always add a sound of their own.
        // In the owner's order: those with something in them, and on the playing phone also the owner's own
        // categories while still empty.
        final used = {for (final s in state.sounds) s.category};
        final all = <String>{
          for (final c in state.categoryList)
            if (used.contains(c.id) || (widget.owner != null && (c.custom || c.id == ambienceOwnCategory))) c.id,
        };
        final pages = <String?>[null, _selected, ...all];
        final chosen = pages.contains(_category) ? _category : null;
        if (!listEquals(pages, _pageList)) {
          _pageList = pages;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _pages.hasClients) _pages.jumpToPage(pages.indexOf(chosen));
          });
        }
        final color = _colorOf(chosen);
        return Scaffold(
          appBar: AppBar(
            title: Text(widget.title),
            backgroundColor: color,
            foregroundColor: Colors.white,
            actions: _actions(chosen),
          ),
          body: AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [color, Color.lerp(color, Colors.black, 0.35)!],
            ),
          ),
          child: Theme(
            data: ambienceTheme(Theme.of(context), color),
            child: Material(
              type: MaterialType.transparency,
              child: Builder(
                builder: (context) {
                  final theme = Theme.of(context);
                  return Column(
                    children: [
                      _banner(theme, state, pages, chosen),
                      _status(theme, state),
                      _dots(pages.length, pages.indexOf(chosen)),
                      Expanded(
                        child: PageView.builder(
                          key: const Key('amb-pages'),
                          controller: _pages,
                          itemCount: pages.length,
                          onPageChanged: (i) {
                            if (i >= pages.length || pages[i] == _category) return;
                            setState(() => _category = pages[i]);
                          },
                          itemBuilder: (context, i) => _page(theme, state, all, pages[i]),
                        ),
                      ),
                      _controls(theme, state, pages, color),
                    ],
                  );
                },
              ),
            ),
          ),
          ),
        );
      },
    );
  }

  /// The picture across the top, with the group's name on it. Swiping it turns the page.
  Widget _banner(ThemeData theme, AmbienceState state, List<String?> pages, String? page) {
    final screen = MediaQuery.sizeOf(context).height;
    final own = widget.owner?.banners?.of(_groupOf(page));
    return GestureDetector(
      key: const Key('amb-banner'),
      behavior: HitTestBehavior.opaque,
      onHorizontalDragStart: (_) => _swipe = 0,
      onHorizontalDragUpdate: (d) => _swipe += d.delta.dx,
      onHorizontalDragEnd: (d) => _turn(pages, d.primaryVelocity ?? 0),
      child: LayoutBuilder(
        builder: (context, box) => SizedBox(
          width: double.infinity,
          // As high as the owner set it, but the sounds always keep most of the screen.
          height: own != null
              ? max(72.0, min(box.maxWidth / own.framing.aspect, screen * 0.3))
              : (screen >= 700 ? 120 : 76),
          child: Stack(
            fit: StackFit.expand,
            children: [
              _art(state, page),
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Material(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(20),
                          child: InkWell(
                            key: const Key('amb-title'),
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => _groups(pages),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  ConstrainedBox(
                                    constraints: BoxConstraints(maxWidth: max(80, box.maxWidth - 88)),
                                    child: Text(_titleOf(page, state),
                                        key: const Key('amb-title-text'),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: theme.textTheme.titleLarge),
                                  ),
                                  const Icon(Icons.expand_more_rounded),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (_needsPhones(state, page)) ...[
                          const SizedBox(height: 4),
                          Material(
                            color: Colors.black.withValues(alpha: 0.45),
                            borderRadius: BorderRadius.circular(14),
                            child: InkWell(
                              key: const Key('amb-headphones'),
                              borderRadius: BorderRadius.circular(14),
                              onTap: _headphonesInfo,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.headphones_rounded, size: 16),
                                    const SizedBox(width: 6),
                                    Text('Use headphones', style: theme.textTheme.labelMedium),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// What is playing.
  Widget _status(ThemeData theme, AmbienceState state) {
    final count = state.active.length;
    final timer = state.timerMinutes;
    return Container(
      width: double.infinity,
      color: Colors.black.withValues(alpha: 0.18),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Text(
        [
          state.mixName ?? (count == 0 ? 'Tap a sound to begin' : '$count sound${count == 1 ? '' : 's'} on'),
          if (state.mixName != null) '$count sound${count == 1 ? '' : 's'}',
          if (state.onceLeft case final once?) '${_left(once)} of the sound left',
          if (timer != null) '${_left(state.secondsLeft ?? timer * 60)} left',
        ].join(' · '),
        key: const Key('amb-status'),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleSmall,
      ),
    );
  }

  Widget _dots(int count, int at) => ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Wrap(
            alignment: WrapAlignment.center,
            spacing: 7,
            runSpacing: 4,
            children: [
              for (var i = 0; i < count; i++)
                Container(
                  width: i == at ? 9 : 6,
                  height: i == at ? 9 : 6,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: i == at ? Colors.white : Colors.white38),
                ),
            ],
          ),
        ),
      );

  /// The floating bar (mixes, play, stop, what is on), the volume of everything, and the round buttons.
  Widget _controls(ThemeData theme, AmbienceState state, List<String?> pages, Color color) {
    final master = _dragging['*'] ?? state.master;
    final count = state.active.length;
    final timer = state.timerMinutes;
    Widget round(String key, String tip, IconData icon, VoidCallback? onPressed, {bool lit = false}) => IconButton(
          key: Key(key),
          tooltip: tip,
          icon: Icon(icon),
          style: IconButton.styleFrom(
            backgroundColor: Colors.white.withValues(alpha: lit ? 0.9 : 0.16),
            foregroundColor: lit ? color : Colors.white,
          ),
          onPressed: onPressed,
        );
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Material(
              color: Colors.black.withValues(alpha: 0.28),
              borderRadius: BorderRadius.circular(22),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                        key: const Key('amb-mixes'),
                        tooltip: 'Mixes',
                        icon: const Icon(Icons.favorite_rounded),
                        onPressed: widget.enabled ? _mixes : null),
                    const SizedBox(width: 8),
                    IconButton(
                      key: const Key('amb-play'),
                      tooltip: state.playing ? 'Pause' : 'Play',
                      iconSize: 34,
                      icon: Icon(state.playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
                      onPressed: widget.enabled && count > 0 ? () => _run(state.playing ? _c.pause : _c.play) : null,
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                        key: const Key('amb-stop'),
                        tooltip: 'Stop',
                        iconSize: 30,
                        icon: const Icon(Icons.stop_rounded),
                        onPressed: widget.enabled ? () => _run(_c.stop) : null),
                    const SizedBox(width: 8),
                    IconButton(
                      key: const Key('amb-selected'),
                      tooltip: 'What is on',
                      icon: Badge(
                        isLabelVisible: count > 0,
                        backgroundColor: Colors.white,
                        textColor: color,
                        label: Text('$count', key: const Key('amb-selected-count')),
                        child: const Icon(Icons.visibility_rounded),
                      ),
                      onPressed: () => _goTo(pages, _selected),
                    ),
                  ],
                ),
              ),
            ),
            Row(
              children: [
                const Icon(Icons.volume_up_rounded, size: 22),
                Expanded(
                  child: Slider(
                    key: const Key('amb-master'),
                    value: master.clamp(0.0, 1.0),
                    semanticFormatterCallback: (v) => 'Volume of all sounds ${(v * 100).round()} percent',
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
                round('amb-home', 'Ready sounds', Icons.home_rounded, () => _goTo(pages, null)),
                round('amb-timer', 'Sleep timer', Icons.timer_rounded, widget.enabled ? _timer : null, lit: timer != null),
                if (widget.owner?.setSchedule != null)
                  round('amb-schedule', 'Bedtime schedule', Icons.alarm_rounded, _editSchedule,
                      lit: widget.owner!.schedule!().enabled),
                if (widget.owner?.night ?? false) round('amb-night', 'Night mode', Icons.bedtime_rounded, _night),
                round('amb-groups', 'All groups', Icons.dashboard_rounded, () => _groups(pages)),
                if (widget.owner != null) round('amb-max', 'Maximum volume', Icons.hearing_rounded, _maxVolume),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// One page: the sounds ready to play (by category), or every place of one category.
  Widget _page(ThemeData theme, AmbienceState state, Set<String> all, String? page) {
    if (page == _selected) return _selectedPage(theme, state);
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
            for (final c in categories) ...[
              // A group's own page is already named by the title above.
              if (page == null)
                _Heading(state.categoryName(c), key: ValueKey('amb-group-$c'))
              else
                SizedBox(key: ValueKey('amb-group-$c'), height: 4),
              if (owner?.setIcon != null && (c == ambienceOwnCategory || c == ambienceEnvironmentCategory))
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Text('Hold a sound to change its picture.', style: theme.textTheme.bodySmall),
                ),
              Wrap(
                children: [
                  for (final s in state.sounds.where((s) => s.category == c && visible(s)))
                    SizedBox(width: width, child: _tile(theme, state, s)),
                  if (owner != null && (c == ambienceOwnCategory || (page == c && state.categoryList.any((x) => x.id == c && x.custom))))
                    SizedBox(width: width, child: _addTile(theme, c == ambienceOwnCategory ? null : c)),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  /// Only what is switched on, each with its volume.
  Widget _selectedPage(ThemeData theme, AmbienceState state) {
    final on = [for (final id in state.active.keys) if (state.sound(id) case final s?) s];
    if (on.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('Nothing is switched on. Tap a sound on another page to add it here.', textAlign: TextAlign.center),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final columns = (box.maxWidth / 112).floor().clamp(3, 8);
        final width = (box.maxWidth - 24) / columns;
        return ListView(
          key: const PageStorageKey('amb-list-selected'),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
          children: [
            Wrap(children: [for (final s in on) SizedBox(width: width, child: _tile(theme, state, s))]),
          ],
        );
      },
    );
  }

  Widget _square(ThemeData theme, {required Color color, required Widget child}) => Material(
        color: color,
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(width: 68, height: 68, child: Center(child: child)),
      );

  Widget _tile(ThemeData theme, AmbienceState state, AmbienceSound s) {
    final on = state.active.containsKey(s.id);
    final volume = _dragging[s.id] ?? state.active[s.id] ?? 0;
    // The color of the page shows through the picture of a sound that is on.
    final page = theme.colorScheme.onPrimary;
    return Column(
      children: [
        Semantics(
          button: true,
          selected: on,
          label: '${s.name}${s.available ? '' : ', add a file'}',
          excludeSemantics: true,
          child: InkWell(
            key: ValueKey('amb-sound-${s.id}'),
            borderRadius: BorderRadius.circular(20),
            onTap: widget.enabled ? () => _tap(s) : null,
            onLongPress: widget.enabled && widget.owner != null ? () => _fileMenu(s) : null,
            child: SizedBox(
              width: 96,
              height: 76,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _square(
                    theme,
                    color: on ? Colors.white : Colors.white.withValues(alpha: s.available ? 0.18 : 0.08),
                    child: AmbiencePicture(ambienceIconName(s), size: 32, color: on ? page : Colors.white, faded: !s.available),
                  ),
                  if (on) Positioned(top: 0, right: 0, child: Text('${(volume * 100).round()}', style: theme.textTheme.labelMedium)),
                  if (s.headphones || s.once || s.alone)
                    Positioned(
                      top: 0,
                      left: 2,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (s.headphones)
                            Icon(Icons.headphones_rounded, key: ValueKey('amb-phones-${s.id}'), size: 14, color: Colors.white70),
                          if (s.once)
                            Text('1\u00d7', key: ValueKey('amb-once-${s.id}'), style: theme.textTheme.labelSmall),
                          if (s.alone)
                            Icon(Icons.person_rounded, key: ValueKey('amb-alone-${s.id}'), size: 14, color: Colors.white70),
                        ],
                      ),
                    ),
                  // The owner's own, where it sits among the app's sounds.
                  if (s.own && s.category != ambienceOwnCategory && s.category != ambienceEnvironmentCategory)
                    Positioned(
                      left: 2,
                      bottom: 2,
                      child: Icon(Icons.star_rounded, key: ValueKey('amb-own-${s.id}'), size: 15, color: Colors.amberAccent),
                    ),
                  if (!s.available)
                    Positioned(
                      right: 12,
                      bottom: 6,
                      child: Icon(Icons.add_circle_rounded, key: ValueKey('amb-add-${s.id}'), size: 18, color: Colors.white),
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
                    activeTrackColor: Colors.white,
                    inactiveTrackColor: Colors.white30,
                    thumbColor: Colors.white,
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  ),
                  child: Slider(
                    key: ValueKey('amb-volume-${s.id}'),
                    value: volume.clamp(0.0, 1.0),
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

  Widget _addTile(ThemeData theme, [String? category]) => Column(
        children: [
          InkWell(
            key: const Key('amb-add-own'),
            borderRadius: BorderRadius.circular(18),
            onTap: widget.enabled ? () => _addOwn(category) : null,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: _square(theme, color: Colors.white.withValues(alpha: 0.12), child: const Icon(Icons.add_rounded, size: 30)),
            ),
          ),
          Text('Add a sound', style: theme.textTheme.bodySmall),
        ],
      );
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
  const _NameDialog({required this.title, this.initial = '', this.maxLength = 40});
  final String title;
  final String initial;
  final int maxLength;

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
          maxLength: widget.maxLength,
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
                          child: const Text('Use default'),
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

/// One sound louder or softer than it comes.
class _BoostDialog extends StatefulWidget {
  const _BoostDialog({required this.sound});

  final AmbienceSound sound;

  @override
  State<_BoostDialog> createState() => _BoostDialogState();
}

class _BoostDialogState extends State<_BoostDialog> {
  late double _value = widget.sound.boost.clamp(0.25, 4.0);

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text('Loudness of ${widget.sound.name}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('100% is as the app evens it out. This stays with the sound, in every mix.'),
            Slider(
              key: const Key('amb-boost-slider'),
              min: 0.25,
              max: 4,
              divisions: 15,
              value: _value,
              onChanged: (v) => setState(() => _value = v),
            ),
            Text('${(_value * 100).round()}%', key: const Key('amb-boost-value')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, 1.0), child: const Text('Default')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(key: const Key('amb-boost-save'), onPressed: () => Navigator.pop(context, _value), child: const Text('Save')),
        ],
      );
}

/// When a mix starts by itself.
class _ScheduleDialog extends StatefulWidget {
  const _ScheduleDialog({required this.initial, required this.state});

  final AmbienceSchedule initial;
  final AmbienceState state;

  @override
  State<_ScheduleDialog> createState() => _ScheduleDialogState();
}

class _ScheduleDialogState extends State<_ScheduleDialog> {
  late AmbienceSchedule _s = widget.initial;

  @override
  Widget build(BuildContext context) {
    final mixes = widget.state.mixes;
    // Those that can play now come first.
    bool playable(AmbienceMix m) => m.layers.keys.any((id) => widget.state.sound(id)?.available ?? false);
    final ordered = [...mixes.where(playable), ...mixes.where((m) => !playable(m))];
    final mixId = ordered.any((m) => m.id == _s.mixId) ? _s.mixId : ordered.first.id;
    final time = TimeOfDay(hour: _s.hour, minute: _s.minute);
    return AlertDialog(
      title: const Text('Bedtime schedule'),
      content: SizedBox(
        width: 360,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                key: const Key('sch-on'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Start by itself every day'),
                value: _s.enabled,
                onChanged: (v) => setState(() => _s = _s.copyWith(enabled: v)),
              ),
              ListTile(
                key: const Key('sch-time'),
                contentPadding: EdgeInsets.zero,
                title: const Text('At'),
                trailing: Text(time.format(context), style: Theme.of(context).textTheme.titleLarge),
                onTap: () async {
                  final picked = await showTimePicker(context: context, initialTime: time);
                  if (picked != null) setState(() => _s = _s.copyWith(hour: picked.hour, minute: picked.minute));
                },
              ),
              const Text('Mix'),
              DropdownButton<String>(
                key: const Key('sch-mix'),
                isExpanded: true,
                value: mixId,
                items: [
                  for (final m in ordered)
                    DropdownMenuItem(value: m.id, child: Text(playable(m) ? m.name : '${m.name} (needs files)', overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _s = _s.copyWith(mixId: v)),
              ),
              const SizedBox(height: 8),
              const Text('Stop after'),
              DropdownButton<int>(
                key: const Key('sch-timer'),
                isExpanded: true,
                value: _s.timerMinutes ?? 0,
                items: [
                  for (final m in {0, ...ambienceTimers, if (_s.timerMinutes != null) _s.timerMinutes!})
                    DropdownMenuItem(value: m, child: Text(m == 0 ? 'Until I stop it' : _timerLabel(m))),
                ],
                onChanged: (v) => setState(() => _s = _s.withTimer(v == null || v == 0 ? null : v)),
              ),
              const SizedBox(height: 8),
              Text(
                'It can only start while RemoteTunes is running. To be sure: leave it open in night mode '
                '(the moon button), with the phone charging.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          key: const Key('sch-save'),
          onPressed: () => Navigator.pop(context, _s.copyWith(mixId: mixId)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
