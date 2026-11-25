import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/database/app_database.dart' show Song;
import '../../providers/library_providers.dart';
import '../library/tag_writer.dart';

/// What was chosen in the group dialog: only the fields that were changed.
class GroupInfoEdit {
  const GroupInfoEdit({required this.changes, required this.writeToFile});

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
    {bool canWriteFile = true}) {
  return showDialog<GroupInfoEdit>(
    context: context,
    builder: (_) => GroupInfoDialog(songs: songs, canWriteFile: canWriteFile),
  );
}

class GroupInfoDialog extends StatefulWidget {
  const GroupInfoDialog({super.key, required this.songs, this.canWriteFile = true});

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
      groupFields.any((f) => _changed(f.key)) && _yearProblem() == null;

  void _save() {
    final changes = <String, Object?>{};
    for (final f in groupFields) {
      if (!_changed(f.key)) continue;
      final t = _controllers[f.key]!.text.trim();
      changes[f.key] = f.key == 'year' ? (t.isEmpty ? null : int.parse(t)) : (t.isEmpty ? null : t);
    }
    Navigator.pop(context, GroupInfoEdit(changes: changes, writeToFile: widget.canWriteFile && _write));
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
  final edit = await showGroupInfoDialog(context, songs);
  if (edit == null || edit.changes.isEmpty) return false;

  final changed = await repo.updateGroupInfo(ids, edit.changes);
  var written = 0;
  var refused = 0;
  var other = 0;
  if (edit.writeToFile) {
    for (final s in songs) {
      final path = s.filePath;
      if (path == null) continue;
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
  }
  if (context.mounted) {
    final parts = <String>[
      'Changed $changed song${changed == 1 ? '' : 's'}',
      if (edit.writeToFile && written > 0) 'written into $written file${written == 1 ? '' : 's'}',
      if (refused > 0) '$refused refused by Android (Settings > Library > All files access)',
      if (other > 0) '$other could not be written (library only)',
    ];
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(parts.join(' · '))));
  }
  return changed > 0;
}
