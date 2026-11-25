import 'package:flutter/material.dart';

import '../../core/protocol/library_models.dart';

/// New title, artist, album and track number for a song.
class SongInfoEdit {
  SongInfoEdit({
    required this.title,
    required this.artist,
    required this.album,
    this.trackNumber,
    this.writeToFile = false,
  });

  /// Also change the tags inside the music file.
  final bool writeToFile;

  /// Said by whoever saves it: what happened to the file (shown after saving).
  String? fileNote;

  final String title;
  final String artist;
  final String album;
  final int? trackNumber;
}

/// Asks for new details for [song]; null if cancelled.
Future<SongInfoEdit?> showSongInfoDialog(BuildContext context, RemoteSong song,
    {bool canWriteFile = false}) {
  return showDialog<SongInfoEdit>(
    context: context,
    builder: (_) => _SongInfoDialog(song: song, canWriteFile: canWriteFile),
  );
}

class _SongInfoDialog extends StatefulWidget {
  const _SongInfoDialog({required this.song, required this.canWriteFile});

  final RemoteSong song;
  final bool canWriteFile;

  @override
  State<_SongInfoDialog> createState() => _SongInfoDialogState();
}

class _SongInfoDialogState extends State<_SongInfoDialog> {
  late final TextEditingController _title = TextEditingController(text: widget.song.title);
  late final TextEditingController _artist = TextEditingController(text: widget.song.artist);
  late final TextEditingController _album = TextEditingController(text: widget.song.album);
  late final TextEditingController _track =
      TextEditingController(text: widget.song.trackNumber?.toString() ?? '');

  @override
  void dispose() {
    _title.dispose();
    _artist.dispose();
    _album.dispose();
    _track.dispose();
    super.dispose();
  }

  bool _writeToFile = false;

  bool get _valid => _title.text.trim().isNotEmpty;

  void _save() {
    if (!_valid) return;
    Navigator.pop(
      context,
      SongInfoEdit(
        title: _title.text,
        artist: _artist.text,
        album: _album.text,
        trackNumber: int.tryParse(_track.text.trim()),
        writeToFile: widget.canWriteFile && _writeToFile,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Edit info'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _title,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Title'),
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _artist,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Artist'),
            ),
            TextField(
              controller: _album,
              maxLength: 200,
              decoration: const InputDecoration(labelText: 'Album'),
            ),
            TextField(
              controller: _track,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Track number'),
            ),
            if (widget.canWriteFile)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: const Text('Also write into the music file'),
                value: _writeToFile,
                onChanged: (v) => setState(() => _writeToFile = v ?? false),
              ),
            const SizedBox(height: 8),
            Text(
              widget.canWriteFile
                  ? 'Always changes how the song is listed in RemoteTunes. Writing into the file '
                      'keeps the change when the file is used elsewhere; Android may not allow it for every file.'
                  : 'Changes how the song is listed in RemoteTunes. The music file is not changed.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _valid ? _save : null, child: const Text('Save')),
      ],
    );
  }
}
