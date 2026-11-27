import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart' show Song;
import '../library/cover_picker.dart';
import '../library/lookup_models.dart' show LookupCover;
import 'song_art.dart';
import '../../providers/library_providers.dart';
import '../library/tag_writer.dart';

/// What was chosen in the group dialog: only the fields that were changed.
class GroupInfoEdit {
  const GroupInfoEdit({required this.changes, required this.writeToFile, this.cover});

  /// A picture for these songs, or null to leave their covers.
  final LookupCover? cover;

  /// Keys: `artist`, `album`, `albumArtist`, `genre`, `year` (an int), `composer`. A null value
  /// clears the field.
  final Map<String, Object?> changes;
  final bool writeToFile;
}

/// The fields several songs can share (never the title or the track number).
const groupFields = <({String key, String label})>[
  (key: 'artist', label: 'Artist'),
  (key: 'album', label: 'Album'),
  (key: 'albumArtist', label: 'Album artist'),
  (key: 'genre', label: 'Genre'),
  (key: 'year', label: 'Year'),
  (key: 'composer', label: 'Composer'),
];

/// The value of [key] on [song] as text ('' for none).
String groupValueOf(Song song, String key) => switch (key) {
      'artist' => song.artist ?? '',
      'album' => song.album ?? '',
      'albumArtist' => song.albumArtist ?? '',
      'genre' => song.genre ?? '',
      'year' => song.year?.toString() ?? '',
      _ => song.composer ?? '',
    };

/// Asks what to change on [songs]. Null if cancelled.
Future<GroupInfoEdit?> showGroupInfoDialog(BuildContext context, List<Song> songs,
    {bool canWriteFile = true, Future<LookupCover?> Function(BuildContext context)? pickCover}) {
  return showDialog<GroupInfoEdit>(
    context: context,
    builder: (_) => GroupInfoDialog(songs: songs, canWriteFile: canWriteFile, pickCover: pickCover),
  );
}

class GroupInfoDialog extends StatefulWidget {
  const GroupInfoDialog({super.key, required this.songs, this.canWriteFile = true, this.pickCover});

  /// Chooses a picture on this phone as their cover (null: no button).
  final Future<LookupCover?> Function(BuildContext context)? pickCover;

  final List<Song> songs;
  final bool canWriteFile;

  @override
  State<GroupInfoDialog> createState() => _GroupInfoDialogState();
}

class _GroupInfoDialogState extends State<GroupInfoDialog> {
  final _controllers = <String, TextEditingController>{};
  final _initial = <String, String>{};
  final _different = <String, bool>{};
  bool _write = true;
  LookupCover? _cover;

  Future<void> _choosePicture() async {
    final cover = await widget.pickCover!(context);
    if (cover == null || !mounted) return;
    setState(() => _cover = cover);
  }

  @override
  void initState() {
    super.initState();
    for (final f in groupFields) {
      final values = {for (final s in widget.songs) groupValueOf(s, f.key)};
      // The shared value when every song has the same, otherwise empty ("different").
      final common = values.length == 1 ? values.first : '';
      _initial[f.key] = common;
      _different[f.key] = values.length > 1;
      _controllers[f.key] = TextEditingController(text: common);
    }
  }

  @override
  void dispose() {
    for (final c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  bool _changed(String key) => _controllers[key]!.text.trim() != _initial[key];

  String? _yearProblem() {
    final t = _controllers['year']!.text.trim();
    if (t.isEmpty || !_changed('year')) return null;
    final y = int.tryParse(t);
    return (y == null || y < 1 || y > 9999) ? 'A year, like 1999' : null;
  }

  bool get _canSave =>
      (_cover != null || groupFields.any((f) => _changed(f.key))) && _yearProblem() == null;

  void _save() {
    final changes = <String, Object?>{};
    for (final f in groupFields) {
      if (!_changed(f.key)) continue;
      final t = _controllers[f.key]!.text.trim();
      changes[f.key] = f.key == 'year' ? (t.isEmpty ? null : int.parse(t)) : (t.isEmpty ? null : t);
    }
    Navigator.pop(context,
        GroupInfoEdit(changes: changes, writeToFile: widget.canWriteFile && _write, cover: _cover));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final n = widget.songs.length;
    return AlertDialog(
      title: Text('Edit info of $n song${n == 1 ? '' : 's'}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Only what these songs can share is here. A field left as it is stays as it is on every '
              'song; whatever you type goes on all of them. The titles and track numbers are not touched.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            for (final f in groupFields)
              TextField(
                key: ValueKey('group-${f.key}'),
                controller: _controllers[f.key],
                maxLength: f.key == 'year' ? 4 : 200,
                keyboardType: f.key == 'year' ? TextInputType.number : TextInputType.text,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: f.label,
                  hintText: _different[f.key]! ? '(different)' : '(none)',
                  errorText: f.key == 'year' ? _yearProblem() : null,
                  counterText: '',
                  // Marks the fields that will change.
                  suffixIcon: _changed(f.key)
                      ? Icon(Icons.edit_rounded, size: 18, color: theme.colorScheme.primary)
                      : null,
                ),
              ),
            if (widget.pickCover != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                key: const Key('choose-cover'),
                onPressed: _choosePicture,
                icon: const Icon(Icons.image_rounded),
                label: Text(_cover == null ? 'Choose a cover picture' : 'Choose another picture'),
              ),
            ],
            if (_cover != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(_cover!.bytes,
                          key: const Key('cover-preview'),
                          width: 64,
                          height: 64,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => const Icon(Icons.broken_image_outlined, size: 48)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Save puts this picture on ${n == 1 ? 'this song' : 'these $n songs'}'
                        '${widget.canWriteFile && _write ? ', and into the music file${n == 1 ? '' : 's'}' : ''}.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    IconButton(
                      key: const Key('cover-clear'),
                      tooltip: 'Keep the covers as they are',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => _cover = null),
                    ),
                  ],
                ),
              ),
            if (widget.canWriteFile)
              CheckboxListTile(
                key: const Key('group-write'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Also write into the music files'),
                value: _write,
                onChanged: (v) => setState(() => _write = v ?? true),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          key: const Key('group-save'),
          onPressed: _canSave ? _save : null,
          child: const Text('Save'),
        ),
      ],
    );
  }
}

/// Edit info for the songs picked in the Library: shows the dialog, changes the library, and (when
/// asked) the music files; then says what happened. Returns true if anything was changed.
Future<bool> editSelectedSongs(BuildContext context, WidgetRef ref, List<int> ids) async {
  final repo = ref.read(libraryRepositoryProvider);
  final songs = await repo.songsByIds(ids);
  if (songs.isEmpty || !context.mounted) return false;
  final edit = await showGroupInfoDialog(context, songs, pickCover: ref.read(coverPickerProvider));
  final cover = edit?.cover;
  if (edit == null || (edit.changes.isEmpty && cover == null)) return false;

  var changed = edit.changes.isEmpty ? 0 : await repo.updateGroupInfo(ids, edit.changes);
  // The picture goes on the songs picked (not on the rest of their albums).
  if (cover != null) {
    final import = await ref.read(importServiceProvider.future);
    await import.setCoverOf([for (final s in songs) s.id], cover.bytes, cover.ext);
    SongArt.forgetAll();
    if (changed == 0) changed = songs.length;
  }
  final covers = <TagWriteResult>[];
  var written = 0;
  var refused = 0;
  var other = 0;
  if (edit.writeToFile) {
    for (final s in songs) {
      final path = s.filePath;
      if (path == null) continue;
      if (edit.changes.isNotEmpty) {
        switch (const TagWriter().writeGroup(path, edit.changes)) {
          case TagWriteResult.written:
            written++;
          case TagWriteResult.notAllowed:
            refused++;
          case TagWriteResult.missing:
          case TagWriteResult.unsupported:
          case TagWriteResult.failed:
            other++;
        }
      }
      if (cover != null) {
        covers.add(const TagWriter().writeCover(path, cover.bytes));
        await Future<void>.delayed(Duration.zero); // the screen keeps moving
      }
    }
  }
  if (context.mounted) {
    final parts = <String>[
      'Changed $changed song${changed == 1 ? '' : 's'}',
      if (edit.writeToFile && written > 0) 'written into $written file${written == 1 ? '' : 's'}',
      if (refused > 0) '$refused refused by Android (Settings > Library > All files access)',
      if (other > 0) '$other could not be written (library only)',
      if (covers.isNotEmpty) TagWriter.coverMessage(covers),
    ];
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(parts.join(' · '))));
  }
  return changed > 0;
}
