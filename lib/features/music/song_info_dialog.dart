import 'package:flutter/material.dart';

import '../../core/protocol/library_models.dart';

/// New title, artist, album and track number for a song.
class SongInfoEdit {
  const SongInfoEdit({
    required this.title,
    required this.artist,
    required this.album,
    this.trackNumber,
  });

  final String title;
  final String artist;
  final String album;
  final int? trackNumber;
}

/// Asks for new details for [song]; null if cancelled.
Future<SongInfoEdit?> showSongInfoDialog(BuildContext context, RemoteSong song) {
  return showDialog<SongInfoEdit>(
    context: context,
    builder: (_) => _SongInfoDialog(song: song),
  );
}

class _SongInfoDialog extends StatefulWidget {
  const _SongInfoDialog({required this.song});

  final RemoteSong song;

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
            const SizedBox(height: 8),
            Text(
              'Changes how the song is listed in RemoteTunes. The music file is not changed.',
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
