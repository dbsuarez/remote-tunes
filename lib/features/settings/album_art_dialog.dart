import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../providers/providers.dart';
import '../library/album_art_fetcher.dart';

/// Builds the fetcher (overridden in tests).
final albumArtFetcherProvider = Provider<AlbumArtFetcher>((ref) {
  return AlbumArtFetcher(
    db: ref.watch(databaseProvider),
    directory: () async {
      final docs = await getApplicationDocumentsDirectory();
      return Directory(p.join(docs.path, 'album_art'));
    },
  );
});

/// Settings row that finds covers for songs that have none.
class AlbumArtTile extends ConsumerWidget {
  const AlbumArtTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: const Icon(Icons.image_search_rounded),
      title: const Text('Find missing album art'),
      subtitle: const Text(
          'Looks up covers for songs that have none (MusicBrainz and Cover Art Archive).'),
      onTap: () => showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlbumArtDialog(),
      ),
    );
  }
}

class AlbumArtDialog extends ConsumerStatefulWidget {
  const AlbumArtDialog({super.key});

  @override
  ConsumerState<AlbumArtDialog> createState() => _AlbumArtDialogState();
}

enum _Phase { asking, working, done }

class _AlbumArtDialogState extends ConsumerState<AlbumArtDialog> {
  _Phase _phase = _Phase.asking;
  int? _missing;
  int _done = 0;
  int _total = 0;
  bool _cancel = false;
  ArtFetchResult? _result;

  @override
  void initState() {
    super.initState();
    ref.read(albumArtFetcherProvider).missingAlbums().then((n) {
      if (mounted) setState(() => _missing = n);
    }).catchError((Object _) {
      if (mounted) setState(() => _missing = 0);
    });
  }

  Future<void> _start() async {
    setState(() => _phase = _Phase.working);
    final r = await ref.read(albumArtFetcherProvider).run(
          onProgress: (d, t) {
            if (!mounted) return;
            setState(() {
              _done = d;
              _total = t;
            });
          },
          isCancelled: () => _cancel,
        );
    if (!mounted) return;
    setState(() {
      _result = r;
      _phase = _Phase.done;
    });
  }

  @override
  Widget build(BuildContext context) {
    final m = _missing;
    switch (_phase) {
      case _Phase.asking:
        return AlertDialog(
          title: const Text('Find missing album art'),
          content: m == null
              ? const SizedBox(height: 40, child: Center(child: CircularProgressIndicator()))
              : Text(m == 0
                  ? 'Every album with a known artist already has a cover.'
                  : '$m album${m == 1 ? '' : 's'} have no cover.\n\n'
                      'The names of the artist and album are sent to MusicBrainz and the '
                      'Cover Art Archive to find the picture. Nothing else leaves this phone. '
                      'It takes about 2 seconds per album.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
            if (m != null && m > 0) FilledButton(onPressed: _start, child: const Text('Start')),
          ],
        );
      case _Phase.working:
        return AlertDialog(
          title: const Text('Finding covers…'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
              const SizedBox(height: 12),
              Text('$_done of ${_total == 0 ? '…' : _total} albums'),
            ],
          ),
          actions: [
            TextButton(
                onPressed: _cancel ? null : () => setState(() => _cancel = true),
                child: Text(_cancel ? 'Stopping…' : 'Stop')),
          ],
        );
      case _Phase.done:
        final r = _result!;
        return AlertDialog(
          title: Text(r.cancelled ? 'Stopped' : 'Done'),
          content: Text('Found ${r.found} cover${r.found == 1 ? '' : 's'}'
              '${r.notFound > 0 ? ', ${r.notFound} not found' : ''}'
              '${r.failed > 0 ? ', ${r.failed} skipped (no internet)' : ''}.'
              '${r.found > 0 ? '\n\nThey show on the next song you play.' : ''}'),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK')),
          ],
        );
    }
  }
}
