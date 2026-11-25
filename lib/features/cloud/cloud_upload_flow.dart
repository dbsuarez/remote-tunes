import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../data/repositories/library_repository.dart';
import '../../providers/library_providers.dart';
import 'cloud_config_store.dart';
import 'cloud_library_view.dart';
import 'cloud_models.dart';
import 'cloud_service.dart';
import 'cloud_settings_screen.dart';
import 'r2_client.dart';

/// A library song that could go to the cloud, with what is known about it before it does.
class UploadCandidate {
  UploadCandidate({
    required this.songId,
    required this.title,
    required this.path,
    required this.size,
    this.artist = '',
    this.album = '',
    this.genre = '',
    this.year,
    this.track,
    this.durationSeconds = 0,
    this.artPath,
    this.duplicate,
    this.problem,
  });

  final int songId;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final int? year;
  final int? track;
  final int durationSeconds;
  final String path;
  final int size;
  final String? artPath;

  /// The song already in the cloud that this seems to be (so it is not ticked by default).
  final CloudSong? duplicate;

  /// Why it cannot be uploaded (the file is gone, or it is not a file on this phone).
  final String? problem;

  bool get canUpload => problem == null;

  /// Ticked by default: something that can go up and is not already there.
  bool get tickedByDefault => canUpload && duplicate == null;
}

/// Looks at library songs and says what an upload of each would be. [existing] is the cloud catalog, to
/// spot songs already there.
Future<List<UploadCandidate>> loadUploadCandidates(LibraryRepository library, List<int> ids, CloudCatalog existing) async {
  String known(String? s) {
    final t = (s ?? '').trim();
    return t.toLowerCase().startsWith('unknown') ? '' : t;
  }

  final out = <UploadCandidate>[];
  for (final id in ids) {
    final s = await library.songById(id);
    if (s == null) continue;
    final path = s.filePath;
    String? problem;
    var size = 0;
    if (path == null) {
      problem = 'Not a file on this phone';
    } else {
      final f = File(path);
      if (!f.existsSync()) {
        problem = 'The file is missing';
      } else {
        size = f.lengthSync();
      }
    }
    final artist = known(s.artist), album = known(s.album);
    out.add(UploadCandidate(
      songId: id,
      title: s.title,
      artist: artist,
      album: album,
      genre: (s.genre ?? '').trim(),
      year: s.year,
      track: s.trackNumber,
      durationSeconds: s.durationSeconds ?? 0,
      path: path ?? '',
      size: size,
      artPath: s.albumArtPath,
      duplicate: existing.duplicateOf(title: s.title, artist: artist, durationSeconds: s.durationSeconds ?? 0),
      problem: problem,
    ));
  }
  return out;
}

/// Turns the chosen candidates into uploads: the file read as a stream, the cover read from its file.
Future<List<CloudUpload>> toUploads(List<UploadCandidate> chosen) async {
  final out = <CloudUpload>[];
  for (final c in chosen) {
    Uint8List? art;
    var artExt = 'jpg';
    final ap = c.artPath;
    if (ap != null && ap.isNotEmpty) {
      try {
        final f = File(ap);
        if (f.existsSync() && f.lengthSync() < 3 * 1024 * 1024) {
          art = await f.readAsBytes();
          artExt = p.extension(ap).toLowerCase() == '.png' ? 'png' : 'jpg';
        }
      } catch (_) {
        art = null; // no cover is better than no upload
      }
    }
    out.add(CloudUpload(
      title: c.title,
      artist: c.artist,
      album: c.album,
      genre: c.genre,
      year: c.year,
      track: c.track,
      durationSeconds: c.durationSeconds,
      ext: p.extension(c.path).replaceAll('.', ''),
      length: c.size,
      art: art,
      artExt: artExt,
      open: () => File(c.path).openRead(),
    ));
  }
  return out;
}

/// Shows what would go up, and lets the user tick what to upload. Null if cancelled.
Future<List<UploadCandidate>?> showUploadReview(BuildContext context, List<UploadCandidate> candidates, {int cloudBytes = 0}) =>
    showDialog<List<UploadCandidate>>(
      context: context,
      builder: (_) => CloudUploadReview(candidates: candidates, cloudBytes: cloudBytes),
    );

class CloudUploadReview extends StatefulWidget {
  const CloudUploadReview({super.key, required this.candidates, this.cloudBytes = 0});

  final List<UploadCandidate> candidates;

  /// What the cloud already holds.
  final int cloudBytes;

  @override
  State<CloudUploadReview> createState() => _CloudUploadReviewState();
}

class _CloudUploadReviewState extends State<CloudUploadReview> {
  late final Set<int> _ticked = {for (final c in widget.candidates) if (c.tickedByDefault) c.songId};

  static String _size(int b) => b < 1024 * 1024 * 1024 ? '${(b / (1024 * 1024)).toStringAsFixed(1)} MB' : '${(b / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chosen = [for (final c in widget.candidates) if (_ticked.contains(c.songId)) c];
    final total = chosen.fold<int>(0, (s, c) => s + c.size);
    final over = widget.cloudBytes + total > CloudLibraryView.freeBytes;
    return AlertDialog(
      title: const Text('Upload to the cloud'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Only upload songs you own or may share. Fix a song\'s tags first (Edit info, Tag cleanup): '
              'they are what the cloud shows.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in widget.candidates)
                    CheckboxListTile(
                      key: ValueKey('upload-${c.songId}'),
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                      value: _ticked.contains(c.songId),
                      onChanged: c.canUpload
                          ? (v) => setState(() => v == true ? _ticked.add(c.songId) : _ticked.remove(c.songId))
                          : null,
                      title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(
                        [
                          if (c.artist.isNotEmpty) c.artist else 'no artist',
                          if (c.album.isNotEmpty) c.album,
                          if (c.canUpload) _size(c.size),
                          if (c.problem != null) c.problem!,
                          if (c.duplicate != null) 'seems to be in the cloud already',
                        ].join(' · '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.problem != null ? theme.colorScheme.error : null),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${chosen.length} song${chosen.length == 1 ? '' : 's'} · ${_size(total)}',
              key: const Key('upload-total'),
              style: theme.textTheme.titleSmall,
            ),
            if (over)
              Text(
                'That is more than the free 10 GB of R2 storage together with what is already there.',
                key: const Key('upload-over'),
                style: TextStyle(color: theme.colorScheme.error),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          key: const Key('upload-go'),
          onPressed: chosen.isEmpty ? null : () => Navigator.pop(context, chosen),
          child: Text(chosen.isEmpty ? 'Upload' : 'Upload ${chosen.length}'),
        ),
      ],
    );
  }
}

/// The whole flow, from the Library's Select: set-up check, review, upload with progress and Stop, result.
Future<void> uploadSongsToCloud(BuildContext context, WidgetRef ref, List<int> ids) async {
  final config = await ref.read(cloudConfigProvider.future);
  if (!context.mounted) return;
  if (!config.canWrite) {
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Set up uploading first'),
        content: const Text(
          'Uploading needs your Cloudflare R2 keys (kept on this phone only). Open the Cloud Library settings '
          'to add them.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Not now')),
          FilledButton(key: const Key('upload-open-settings'), onPressed: () => Navigator.pop(ctx, true), child: const Text('Open the settings')),
        ],
      ),
    );
    if (open == true && context.mounted) {
      await Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const CloudSettingsScreen()));
    }
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
  final candidates = await loadUploadCandidates(ref.read(libraryRepositoryProvider), ids, catalog);
  if (!context.mounted) return;
  if (candidates.isEmpty) return;
  final chosen = await showUploadReview(context, candidates, cloudBytes: catalog.totalBytes);
  if (chosen == null || chosen.isEmpty || !context.mounted) return;

  final uploads = await toUploads(chosen);
  if (!context.mounted) return;
  final progress = ValueNotifier<({int done, int total, String? name})>((done: 0, total: uploads.length, name: null));
  var stop = false;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Uploading'),
        content: ValueListenableBuilder(
          valueListenable: progress,
          builder: (context, p, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: p.total == 0 ? null : p.done / p.total),
              const SizedBox(height: 8),
              Text('${p.done} of ${p.total}', key: const Key('upload-progress')),
              if (p.name != null) Text(p.name!, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        actions: [TextButton(key: const Key('upload-stop'), onPressed: () => stop = true, child: const Text('Stop'))],
      ),
    ),
  );
  CloudUploadResult? result;
  try {
    result = await service.upload(
      uploads,
      cancelled: () => stop,
      onProgress: (d, t, n) => progress.value = (done: d, total: t, name: n),
    );
  } catch (_) {
    result = null;
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  progress.dispose();
  if (!context.mounted) return;
  final r = result;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(r == null ? 'The upload failed' : 'Uploaded ${r.uploaded.length} song${r.uploaded.length == 1 ? '' : 's'}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (r == null) const Text('Something went wrong. What went up is kept; try again.'),
            if (r != null) Text('${(r.bytes / (1024 * 1024)).toStringAsFixed(1)} MB sent.'),
            if (r?.stoppedBecause != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(r!.stoppedBecause!, key: const Key('upload-stopped'))),
            if (r != null && r.failed.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${r.failed.length} failed:', style: Theme.of(ctx).textTheme.labelLarge),
              for (final f in r.failed.take(8)) Text(f, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            if (note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(note)),
          ],
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ),
  );
}
