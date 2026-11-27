/// Arranging the ambience: the categories and their order, and within each the sounds and theirs.
library;

import 'package:flutter/material.dart';

import 'ambience_icons.dart';
import 'ambience_models.dart';
import 'ambience_style.dart';

/// "Play once · Play alone" of what is switched on.
String ambienceSwitchWords({required bool once, required bool alone, required bool headphones}) =>
    [if (once) 'Play once', if (alone) 'Play alone', if (headphones) 'Headphones'].join(' · ');

/// The three switches, for a sound or a whole category. [forced] ones are on and cannot be changed here.
class AmbienceSwitches extends StatefulWidget {
  const AmbienceSwitches(
      {super.key, required this.own, required this.set, this.forced = const {}, this.forcedBy = ''});

  /// What is switched on here now.
  final Set<String> Function() own;
  final Future<void> Function(String flag, bool on) set;
  final Set<String> forced;
  final String forcedBy;

  @override
  State<AmbienceSwitches> createState() => _AmbienceSwitchesState();
}

class _AmbienceSwitchesState extends State<AmbienceSwitches> {
  static const _words = {
    ambienceFlagOnce: ('Play once', 'From start to end, then it switches itself off'),
    ambienceFlagAlone: ('Play alone', 'Switching it on switches the others off'),
    ambienceFlagHeadphones: ('Needs headphones', 'Shows the headphone reminder'),
  };

  @override
  Widget build(BuildContext context) {
    final own = widget.own();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final e in _words.entries)
          SwitchListTile(
            key: Key('amb-flag-${e.key}'),
            dense: true,
            title: Text(e.value.$1),
            subtitle: Text(widget.forced.contains(e.key) ? widget.forcedBy : e.value.$2),
            value: widget.forced.contains(e.key) || own.contains(e.key),
            onChanged: widget.forced.contains(e.key)
                ? null
                : (on) async {
                    await widget.set(e.key, on);
                    if (mounted) setState(() {});
                  },
          ),
      ],
    );
  }
}

/// Asks for a name; null if cancelled.
Future<String?> _askName(BuildContext context, String title, [String initial = '']) =>
    showDialog<String>(context: context, builder: (_) => _NameField(title: title, initial: initial));

class _NameField extends StatefulWidget {
  const _NameField({required this.title, required this.initial});
  final String title;
  final String initial;

  @override
  State<_NameField> createState() => _NameFieldState();
}

class _NameFieldState extends State<_NameField> {
  late final _text = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    if (_text.text.trim().isNotEmpty) Navigator.pop(context, _text.text.trim());
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: Text(widget.title),
        content: TextField(
          key: const Key('amb-category-name'),
          controller: _text,
          autofocus: true,
          maxLength: 30,
          textCapitalization: TextCapitalization.sentences,
          onSubmitted: (_) => _save(),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(key: const Key('amb-category-save'), onPressed: _save, child: const Text('Save')),
        ],
      );
}

/// Runs a change; a refusal is shown in plain words.
Future<void> _try(BuildContext context, Future<void> Function() change) async {
  try {
    await change();
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text('$e')));
    }
  }
}

/// Asks which category to move to; [current] is ticked. Null if put away.
Future<String?> pickAmbienceCategory(BuildContext context, AmbienceOrganizer organizer, {String? current}) =>
    showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.75),
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final c in organizer.categories)
                ListTile(
                  key: ValueKey('amb-move-to-${c.id}'),
                  leading: CircleAvatar(backgroundColor: ambienceColor(c.id), radius: 12),
                  title: Text(c.name),
                  trailing: c.id == current ? const Icon(Icons.check_rounded) : null,
                  onTap: () => Navigator.pop(ctx, c.id),
                ),
            ],
          ),
        ),
      ),
    );

/// Every category, to arrange, rename, add and delete.
class AmbienceManageScreen extends StatelessWidget {
  const AmbienceManageScreen({
    super.key,
    required this.controls,
    required this.organizer,
    required this.onSound,
    required this.onAddSound,
    this.onBanner,
    this.bannerOf,
  });

  final AmbienceControls controls;
  final AmbienceOrganizer organizer;

  /// Opens a sound's menu (picture, loudness, file, move, switches...).
  final Future<void> Function(AmbienceSound sound) onSound;
  final Future<void> Function(String categoryId) onAddSound;

  /// Changes a category's banner picture (null: not offered).
  final Future<void> Function(String categoryId)? onBanner;
  final ImageProvider? Function(String categoryId)? bannerOf;

  Future<void> _newCategory(BuildContext context) async {
    final name = await _askName(context, 'New category');
    if (name != null && context.mounted) await _try(context, () => organizer.createCategory(name));
  }

  Future<void> _menu(BuildContext context, AmbienceCategory c, String choice) async {
    switch (choice) {
      case 'rename':
        final name = await _askName(context, 'Rename ${c.name}', c.name);
        if (name != null && context.mounted) await _try(context, () => organizer.renameCategory(c.id, name));
      case 'banner':
        await onBanner!(c.id);
      case 'switches':
        await showModalBottomSheet<void>(
          context: context,
          showDragHandle: true,
          isScrollControlled: true,
          builder: (_) => SafeArea(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text('Every sound in ${c.name}'),
                  ),
                  AmbienceSwitches(
                    own: () => organizer.categoryFlags(c.id),
                    set: (flag, on) => organizer.setCategoryFlag(c.id, flag, on),
                    // The app's own beats always need them.
                    forced: c.headphones && !organizer.categoryFlags(c.id).contains(ambienceFlagHeadphones)
                        ? const {ambienceFlagHeadphones}
                        : const {},
                    forcedBy: 'These always need them',
                  ),
                ],
              ),
            ),
          ),
        );
      case 'delete':
        final sure = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text('Delete ${c.name}?'),
            content: const Text('Its sounds are kept: they go back to where they came from.'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
              FilledButton(key: const Key('amb-category-delete-yes'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
            ],
          ),
        );
        if (sure == true && context.mounted) await _try(context, () => organizer.deleteCategory(c.id));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Categories and sounds')),
        floatingActionButton: FloatingActionButton.extended(
          key: const Key('amb-new-category'),
          onPressed: () => _newCategory(context),
          icon: const Icon(Icons.add_rounded),
          label: const Text('New category'),
        ),
        body: ListenableBuilder(
          listenable: controls,
          builder: (context, _) {
            final categories = organizer.categories;
            final sounds = controls.state.sounds;
            return ReorderableListView.builder(
              padding: const EdgeInsets.only(bottom: 96),
              buildDefaultDragHandles: false,
              header: const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Text('Drag a handle to change the order. Tap a category to arrange its sounds.'),
              ),
              itemCount: categories.length,
              onReorder: (from, to) {
                final ids = [for (final c in categories) c.id];
                final id = ids.removeAt(from);
                ids.insert(to > from ? to - 1 : to, id);
                _try(context, () => organizer.setCategoryOrder(ids));
              },
              itemBuilder: (context, i) {
                final c = categories[i];
                final count = sounds.where((s) => s.category == c.id).length;
                final switches = ambienceSwitchWords(once: c.once, alone: c.alone, headphones: c.headphones);
                return ListTile(
                  key: ValueKey('amb-manage-${c.id}'),
                  contentPadding: const EdgeInsets.only(left: 16),
                  leading: CircleAvatar(backgroundColor: ambienceColor(c.id), foregroundImage: bannerOf?.call(c.id)),
                  title: Text(c.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(
                      ['$count sound${count == 1 ? '' : 's'}', if (switches.isNotEmpty) switches].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => _CategorySounds(
                        controls: controls, organizer: organizer, id: c.id, onSound: onSound, onAddSound: onAddSound),
                  )),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PopupMenuButton<String>(
                        key: ValueKey('amb-manage-menu-${c.id}'),
                        onSelected: (choice) => _menu(context, c, choice),
                        itemBuilder: (_) => [
                          const PopupMenuItem(value: 'rename', child: Text('Rename')),
                          if (onBanner != null) const PopupMenuItem(value: 'banner', child: Text('Banner picture')),
                          const PopupMenuItem(value: 'switches', child: Text('Switches for all its sounds')),
                          if (c.custom) const PopupMenuItem(value: 'delete', child: Text('Delete')),
                        ],
                      ),
                      ReorderableDragStartListener(
                        index: i,
                        child: Padding(
                          key: ValueKey('amb-drag-${c.id}'),
                          padding: const EdgeInsets.all(12),
                          child: const Icon(Icons.drag_handle_rounded),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        ),
      );
}

/// The sounds of one category, to arrange; each opens its menu. Several can be picked (hold one) and
/// moved together.
class _CategorySounds extends StatefulWidget {
  const _CategorySounds(
      {required this.controls, required this.organizer, required this.id, required this.onSound, required this.onAddSound});

  final AmbienceControls controls;
  final AmbienceOrganizer organizer;
  final String id;
  final Future<void> Function(AmbienceSound sound) onSound;
  final Future<void> Function(String categoryId) onAddSound;

  @override
  State<_CategorySounds> createState() => _CategorySoundsState();
}

class _CategorySoundsState extends State<_CategorySounds> {
  /// The sounds picked; not null while picking.
  Set<String>? _picked;

  void _toggle(String id) => setState(() {
        final picked = _picked ??= {};
        if (!picked.remove(id)) picked.add(id);
      });

  Future<void> _move(List<AmbienceSound> sounds) async {
    // In the order they are listed.
    final ids = [for (final s in sounds) if (_picked!.contains(s.id)) s.id];
    final to = await pickAmbienceCategory(context, widget.organizer, current: widget.id);
    if (to == null || to == widget.id || !mounted) return;
    final name = widget.controls.state.categoryName(to);
    await _try(context, () => widget.organizer.moveSounds(ids, to));
    if (!mounted) return;
    setState(() => _picked = null);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text('Moved ${ids.length} sound${ids.length == 1 ? '' : 's'} to $name')));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: widget.controls,
        builder: (context, _) {
          final state = widget.controls.state;
          final sounds = [for (final s in state.sounds) if (s.category == widget.id) s];
          final picked = _picked;
          // Those that left meanwhile are no longer picked.
          picked?.retainAll([for (final s in sounds) s.id]);
          return PopScope(
            canPop: picked == null,
            onPopInvokedWithResult: (didPop, _) {
              if (!didPop) setState(() => _picked = null);
            },
            child: Scaffold(
              appBar: picked == null
                  ? AppBar(
                      title: Text(state.categoryName(widget.id)),
                      actions: [
                        if (sounds.isNotEmpty)
                          IconButton(
                            key: const Key('amb-select'),
                            tooltip: 'Select sounds',
                            icon: const Icon(Icons.checklist_rounded),
                            onPressed: () => setState(() => _picked = {}),
                          ),
                      ],
                    )
                  : AppBar(
                      leading: IconButton(
                        key: const Key('amb-select-done'),
                        tooltip: 'Stop selecting',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(() => _picked = null),
                      ),
                      title: Text('${picked.length} selected'),
                      actions: [
                        IconButton(
                          key: const Key('amb-select-all'),
                          tooltip: picked.length == sounds.length ? 'Select none' : 'Select all',
                          icon: const Icon(Icons.select_all_rounded),
                          onPressed: () => setState(() {
                            _picked = picked.length == sounds.length ? {} : {for (final s in sounds) s.id};
                          }),
                        ),
                        IconButton(
                          key: const Key('amb-select-move'),
                          tooltip: 'Move to another category',
                          icon: const Icon(Icons.drive_file_move_outline),
                          onPressed: picked.isEmpty ? null : () => _move(sounds),
                        ),
                      ],
                    ),
              floatingActionButton: picked != null
                  ? null
                  : FloatingActionButton.extended(
                      key: const Key('amb-manage-add'),
                      onPressed: () => widget.onAddSound(widget.id),
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Add a sound'),
                    ),
              body: sounds.isEmpty
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(24),
                        child: Text('Nothing here yet. Add a sound, or move some here: open another category, '
                            'hold a sound to select, then the move button.', textAlign: TextAlign.center),
                      ),
                    )
                  : ReorderableListView.builder(
                      padding: const EdgeInsets.only(bottom: 96),
                      buildDefaultDragHandles: false,
                      itemCount: sounds.length,
                      onReorder: (from, to) {
                        final ids = [for (final s in sounds) s.id];
                        final moved = ids.removeAt(from);
                        ids.insert(to > from ? to - 1 : to, moved);
                        _try(context, () => widget.organizer.setSoundOrder(widget.id, ids));
                      },
                      itemBuilder: (context, i) {
                        final s = sounds[i];
                        final words = [
                          if (s.own) 'Custom',
                          if (!s.available) 'No file yet',
                          ambienceSwitchWords(once: s.once, alone: s.alone, headphones: s.headphones),
                        ].where((w) => w.isNotEmpty).join(' · ');
                        final chosen = picked?.contains(s.id) ?? false;
                        return ListTile(
                          key: ValueKey('amb-manage-sound-${s.id}'),
                          contentPadding: const EdgeInsets.only(left: 16),
                          selected: chosen,
                          leading: AmbiencePicture(ambienceIconName(s), size: 28, faded: !s.available),
                          title: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: words.isEmpty ? null : Text(words, maxLines: 2, overflow: TextOverflow.ellipsis),
                          onTap: () => picked == null ? widget.onSound(s) : _toggle(s.id),
                          onLongPress: () => _toggle(s.id),
                          trailing: picked != null
                              ? Checkbox(
                                  key: ValueKey('amb-check-${s.id}'),
                                  value: chosen,
                                  onChanged: (_) => _toggle(s.id),
                                )
                              : ReorderableDragStartListener(
                                  index: i,
                                  child: Padding(
                                    key: ValueKey('amb-drag-${s.id}'),
                                    padding: const EdgeInsets.all(12),
                                    child: const Icon(Icons.drag_handle_rounded),
                                  ),
                                ),
                        );
                      },
                    ),
            ),
          );
        },
      );
}
