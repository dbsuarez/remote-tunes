import 'package:flutter/material.dart';

import '../../core/protocol/library_models.dart';
import '../../core/utils/album_name.dart';
import '../library/lookup_models.dart';
import 'song_lookup_sheet.dart';

/// New title, artist, album and track number for a song.
class SongInfoEdit {
  SongInfoEdit({
    required this.title,
    required this.artist,
    required this.album,
    this.trackNumber,
    this.writeToFile = false,
    this.cover,
  });

  /// A cover chosen in the look-up: it becomes the picture of the song's album.
  final LookupCover? cover;

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
    {bool canWriteFile = false,
    SongLookupService? lookup,
    Future<LookupCover?> Function(BuildContext context)? pickCover}) {
  return showDialog<SongInfoEdit>(
    context: context,
    builder: (_) => _SongInfoDialog(song: song, canWriteFile: canWriteFile, lookup: lookup, pickCover: pickCover),
  );
}

class _SongInfoDialog extends StatefulWidget {
  const _SongInfoDialog({required this.song, required this.canWriteFile, this.lookup, this.pickCover});

  /// Chooses a picture on this phone as the cover (null: no button).
  final Future<LookupCover?> Function(BuildContext context)? pickCover;

  final RemoteSong song;
  final bool canWriteFile;

  /// Looks the song up on the internet (null: no button).
  final SongLookupService? lookup;

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

  /// Ticked from the start (where it is offered): the change goes into the file too. If Android
  /// does not allow that, it is still saved in the library and the message says so.
  bool _writeToFile = true;

  bool get _valid => _title.text.trim().isNotEmpty;

  LookupCover? _cover;
  String? _lookupNote;

  Future<void> _choosePicture() async {
    final cover = await widget.pickCover!(context);
    if (cover == null || !mounted) return;
    setState(() => _cover = cover);
  }

  /// Which songs a cover goes to.
  String get _coverNote {
    final songs = isRealAlbum(_album.text.trim()) ? 'every song of this album' : 'this song';
    final files = widget.canWriteFile && _writeToFile ? ', and into the music file${isRealAlbum(_album.text.trim()) ? 's' : ''}' : '';
    return 'Save puts this picture on $songs$files.';
  }

  /// Looks the song up, and fills in what was chosen (nothing is saved until Save).
  Future<void> _lookUp() async {
    final lookup = widget.lookup;
    if (lookup == null) return;
    final choice = await showSongLookup(
      context,
      lookup: lookup,
      song: RemoteSong(
        id: widget.song.id,
        title: _title.text.trim(),
        artist: _artist.text.trim(),
        album: _album.text.trim(),
        durationSeconds: widget.song.durationSeconds,
      ),
    );
    if (choice == null || !mounted) return;
    final parts = <String>[];
    setState(() {
      final m = choice.match;
      if (m != null) {
        _title.text = m.title;
        _artist.text = m.artist;
        if (m.album.isNotEmpty) _album.text = m.album;
        if (m.trackNumber != null) _track.text = '${m.trackNumber}';
        parts.add('details filled in');
      }
      if (choice.cover != null) {
        _cover = choice.cover;
        parts.add('cover ready');
      }
      if (choice.keepLyrics) parts.add('lyrics kept');
      _lookupNote = parts.isEmpty ? null : '${parts.join(' · ')} (Save to keep the details and the cover)';
    });
  }

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
        cover: _cover,
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
              onChanged: (_) => setState(() {}),
            ),
            TextField(
              controller: _track,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Track number'),
            ),
            if (widget.pickCover != null)
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  key: const Key('choose-cover'),
                  onPressed: _choosePicture,
                  icon: const Icon(Icons.image_rounded),
                  label: Text(_cover == null ? 'Choose a cover picture' : 'Choose another picture'),
                ),
              ),
            if (_cover != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
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
                    Expanded(child: Text(_coverNote, style: Theme.of(context).textTheme.bodySmall)),
                    IconButton(
                      key: const Key('cover-clear'),
                      tooltip: 'Keep the cover as it is',
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => setState(() => _cover = null),
                    ),
                  ],
                ),
              ),
            if (widget.lookup != null)
              Align(
                alignment: Alignment.centerLeft,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    OutlinedButton.icon(
                      key: const Key('look-up'),
                      onPressed: _lookUp,
                      icon: const Icon(Icons.search_rounded),
                      label: const Text('Look up this song'),
                    ),
                    if (_lookupNote != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _lookupNote!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: Theme.of(context).colorScheme.primary),
                        ),
                      ),
                  ],
                ),
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
