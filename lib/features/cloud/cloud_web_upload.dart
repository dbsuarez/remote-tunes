import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../tagging/tag_cleanup.dart' show parseFileName;
import 'cloud_config_store.dart';
import 'cloud_library_view.dart';
import 'cloud_models.dart';
import 'cloud_pickers.dart';
import 'cloud_service.dart';
import 'cloud_upload_ui.dart';
import 'r2_client.dart';

/// A song picked from the computer, with the details that will be uploaded with it. A browser cannot
/// read the tags inside the file, so they start from the file name (`01 - Artist - Title.mp3`) and are
/// edited here, with a field to fill the artist, album and genre of all of them at once.
class WebUploadCandidate {
  WebUploadCandidate(this.file, {this.duplicate}) {
    final guess = parseFileName(file.baseName);
    title = (guess?.title ?? file.baseName.replaceAll('_', ' ')).trim();
    artist = guess?.artist ?? '';
    track = guess?.track;
  }

  final PickedFile file;

  /// The song already in the cloud that this seems to be.
  final CloudSong? duplicate;

  late String title;
  String artist = '';
  String album = '';
  String genre = '';
  int? track;
  bool ticked = true;

  final titleField = TextEditingController();
  final artistField = TextEditingController();
  final albumField = TextEditingController();
  final genreField = TextEditingController();

  void startFields() {
    titleField.text = title;
    artistField.text = artist;
    albumField.text = album;
    genreField.text = genre;
  }

  void dispose() {
    titleField.dispose();
    artistField.dispose();
    albumField.dispose();
    genreField.dispose();
  }

  CloudUpload toUpload() => CloudUpload(
        title: titleField.text.trim().isEmpty ? title : titleField.text.trim(),
        artist: artistField.text.trim(),
        album: albumField.text.trim(),
        genre: genreField.text.trim(),
        track: track,
        ext: file.ext.isEmpty ? 'mp3' : file.ext,
        length: file.size,
        open: file.open,
      );
}

/// Songs that can be uploaded: audio files only.
bool isAudioName(String name) => RegExp(r'\.(mp3|m4a|aac|flac|ogg|opus|wav)$', caseSensitive: false).hasMatch(name);

/// Makes a candidate for each audio file; a song that seems to be in the cloud already starts unticked.
List<WebUploadCandidate> buildWebCandidates(List<PickedFile> files, CloudCatalog existing) {
  final out = <WebUploadCandidate>[];
  for (final f in files) {
    if (!isAudioName(f.name)) continue;
    final probe = WebUploadCandidate(f);
    final dup = existing.duplicateOf(title: probe.title, artist: probe.artist, durationSeconds: 0);
    final c = WebUploadCandidate(f, duplicate: dup)..ticked = dup == null;
    probe.dispose();
    c.startFields();
    out.add(c);
  }
  return out;
}

/// Shows the picked songs with their details to edit and tick. Returns the uploads, or null if cancelled.
Future<List<CloudUpload>?> showWebUploadReview(BuildContext context, List<WebUploadCandidate> candidates, {int cloudBytes = 0}) =>
    showDialog<List<CloudUpload>>(
      context: context,
      builder: (_) => CloudWebUploadReview(candidates: candidates, cloudBytes: cloudBytes),
    );

class CloudWebUploadReview extends StatefulWidget {
  const CloudWebUploadReview({super.key, required this.candidates, this.cloudBytes = 0});

  final List<WebUploadCandidate> candidates;
  final int cloudBytes;

  @override
  State<CloudWebUploadReview> createState() => _CloudWebUploadReviewState();
}

class _CloudWebUploadReviewState extends State<CloudWebUploadReview> {
  final _allArtist = TextEditingController();
  final _allAlbum = TextEditingController();
  final _allGenre = TextEditingController();

  @override
  void dispose() {
    _allArtist.dispose();
    _allAlbum.dispose();
    _allGenre.dispose();
    for (final c in widget.candidates) {
      c.dispose();
    }
    super.dispose();
  }

  static String _size(int b) => b < 1024 * 1024 * 1024 ? '${(b / (1024 * 1024)).toStringAsFixed(1)} MB' : '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';

  /// Puts what was typed in a "for all" field into every ticked song (an empty field changes nothing).
  void _fillAll() {
    setState(() {
      for (final c in widget.candidates) {
        if (!c.ticked) continue;
        if (_allArtist.text.trim().isNotEmpty) c.artistField.text = _allArtist.text.trim();
        if (_allAlbum.text.trim().isNotEmpty) c.albumField.text = _allAlbum.text.trim();
        if (_allGenre.text.trim().isNotEmpty) c.genreField.text = _allGenre.text.trim();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chosen = [for (final c in widget.candidates) if (c.ticked) c];
    final total = chosen.fold<int>(0, (s, c) => s + c.file.size);
    final over = widget.cloudBytes + total > CloudLibraryView.freeBytes;
    return AlertDialog(
      title: const Text('Upload to the cloud'),
      content: SizedBox(
        width: 640,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Only upload songs you own or may share. The title, artist, album and genre start from the file name; '
              'edit them here, because the cloud shows what you write.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(width: 150, child: TextField(key: const Key('all-artist'), controller: _allArtist, decoration: const InputDecoration(labelText: 'Artist for all', isDense: true))),
                SizedBox(width: 150, child: TextField(key: const Key('all-album'), controller: _allAlbum, decoration: const InputDecoration(labelText: 'Album for all', isDense: true))),
                SizedBox(width: 120, child: TextField(key: const Key('all-genre'), controller: _allGenre, decoration: const InputDecoration(labelText: 'Genre for all', isDense: true))),
                OutlinedButton(key: const Key('fill-all'), onPressed: _fillAll, child: const Text('Fill in')),
              ],
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: widget.candidates.length,
                itemBuilder: (context, i) {
                  final c = widget.candidates[i];
                  return Card(
                    key: ValueKey('web-upload-$i'),
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Checkbox(
                                key: ValueKey('web-tick-$i'),
                                value: c.ticked,
                                onChanged: (v) => setState(() => c.ticked = v ?? false),
                              ),
                              Expanded(
                                child: Text(
                                  '${c.file.name} · ${_size(c.file.size)}${c.duplicate != null ? ' · seems to be in the cloud already' : ''}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ],
                          ),
                          TextField(key: ValueKey('web-title-$i'), controller: c.titleField, decoration: const InputDecoration(labelText: 'Title', isDense: true)),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Expanded(child: TextField(key: ValueKey('web-artist-$i'), controller: c.artistField, decoration: const InputDecoration(labelText: 'Artist', isDense: true))),
                              const SizedBox(width: 6),
                              Expanded(child: TextField(key: ValueKey('web-album-$i'), controller: c.albumField, decoration: const InputDecoration(labelText: 'Album', isDense: true))),
                              const SizedBox(width: 6),
                              SizedBox(width: 90, child: TextField(key: ValueKey('web-genre-$i'), controller: c.genreField, decoration: const InputDecoration(labelText: 'Genre', isDense: true))),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text('${chosen.length} song${chosen.length == 1 ? '' : 's'} · ${_size(total)}', key: const Key('web-upload-total'), style: theme.textTheme.titleSmall),
            if (over)
              Text(
                'That is more than the free 10 GB of R2 storage together with what is already there.',
                key: const Key('web-upload-over'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          key: const Key('web-upload-go'),
          onPressed: chosen.isEmpty ? null : () => Navigator.pop(context, [for (final c in chosen) c.toUpload()]),
          child: Text(chosen.isEmpty ? 'Upload' : 'Upload ${chosen.length}'),
        ),
      ],
    );
  }
}

/// The whole flow on the web page: pick songs from the computer, check the settings, review and edit,
/// upload with progress. Needs the keys saved in this browser.
Future<void> uploadPickedSongs(BuildContext context, WidgetRef ref) async {
  final pick = ref.read(cloudSongPickerProvider);
  if (pick == null) return;
  final config = await ref.read(cloudConfigProvider.future);
  if (!context.mounted) return;
  if (!config.canWrite) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set up uploading first'),
        content: const Text('Uploading needs your Cloudflare R2 keys, saved in this browser only. Open the Cloud Library settings (the gear) to add them.'),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
    return;
  }
  final files = await pick();
  if (files.isEmpty || !context.mounted) return;
  final audio = files.where((f) => isAudioName(f.name)).toList();
  if (audio.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No songs picked'),
        content: const Text('Those files are not songs (mp3, m4a, aac, flac, ogg, opus or wav).'),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
    return;
  }
  final service = await ref.read(cloudServiceProvider.future);
  var catalog = const CloudCatalog();
  String? note;
  try {
    catalog = await service.fetchCatalog();
  } on R2Exception catch (e) {
    note = 'Could not look at what is in the cloud (${e.message}) so duplicates are not checked.';
  }
  if (!context.mounted) return;
  final uploads = await showWebUploadReview(context, buildWebCandidates(audio, catalog), cloudBytes: catalog.totalBytes);
  if (uploads == null || uploads.isEmpty || !context.mounted) return;
  await runCloudUpload(context, service, uploads, note: note);
}
