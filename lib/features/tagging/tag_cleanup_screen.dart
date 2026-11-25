import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/library_providers.dart';
import '../../providers/providers.dart';
import '../library/lookup_models.dart';
import '../settings/album_art_dialog.dart';
import 'tag_cleanup.dart';
import 'tag_cleanup_service.dart';
import 'tag_review_screen.dart';

final tagCleanupServiceProvider = Provider<TagCleanupService>((ref) {
  return TagCleanupService(
    db: ref.watch(databaseProvider),
    library: ref.watch(libraryRepositoryProvider),
  );
});

/// Settings > Library > Tag cleanup: what is missing in the library, and ways to fill it in that
/// you review first: from the file names, and from MusicBrainz by title and artist.
class TagCleanupScreen extends ConsumerStatefulWidget {
  const TagCleanupScreen({super.key});

  @override
  ConsumerState<TagCleanupScreen> createState() => _TagCleanupScreenState();
}

class _TagCleanupScreenState extends ConsumerState<TagCleanupScreen> {
  TagCleanupReport? _report;
  bool _searching = false;
  bool _stop = false;
  int _done = 0;
  int _total = 0;
  String? _current;

  TagCleanupService get _service => ref.read(tagCleanupServiceProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final r = await _service.report();
    if (mounted) setState(() => _report = r);
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _review(String title, List<TagChange> changes, {bool canSkip = false}) async {
    await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => TagReviewScreen(
        title: title,
        changes: changes,
        service: _service,
        canSkip: canSkip,
        coverLookup: ref.read(songLookupProvider),
      ),
    ));
    await _load();
  }

  Future<void> _fromFileNames() async {
    final changes = await _service.fileNameChanges();
    if (!mounted) return;
    if (changes.isEmpty) {
      _say('The file names have nothing to add.');
      return;
    }
    await _review('From file names', changes);
  }

  Future<void> _reviewSuggestions() async {
    final changes = await _service.suggestionChanges();
    if (!mounted) return;
    await _review('Suggestions', changes, canSkip: true);
  }

  Future<void> _search() async {
    setState(() {
      _searching = true;
      _stop = false;
      _done = 0;
      _total = 0;
      _current = null;
    });
    String? problem;
    try {
      await _service.findSuggestions(
        ref.read(songLookupProvider),
        cancelled: () => _stop,
        onProgress: (d, t, c) {
          if (mounted) {
            setState(() {
              _done = d;
              _total = t;
              _current = c;
            });
          }
        },
      );
    } on LookupException catch (e) {
      problem = '${e.message} What was found is kept; carry on later.';
    } catch (_) {
      problem = 'The search stopped. What was found is kept; carry on later.';
    }
    if (!mounted) return;
    setState(() => _searching = false);
    await _load();
    if (problem != null) _say(problem);
  }

  Future<void> _undo() async {
    final b = _report?.lastBatch;
    if (b == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Undo the last change?'),
        content: Text('This puts ${b.songs} song${b.songs == 1 ? '' : 's'} back as they were before the last '
            'batch you applied (in the library, and in the music files that were changed).'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Undo')),
        ],
      ),
    );
    if (ok != true) return;
    final r = await _service.undoLast();
    await _load();
    if (r != null) _say('Put ${r.applied} song${r.applied == 1 ? '' : 's'} back.');
  }

  Widget _row(String label, int n) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          children: [
            Expanded(child: Text(label)),
            Text('$n', style: Theme.of(context).textTheme.titleSmall),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _report;
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Scaffold(
      appBar: AppBar(title: const Text('Tag cleanup')),
      body: SafeArea(
        child: r == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Finds what is missing in your music and fills it in, with you approving every change. '
                    'A tag that is already there is never replaced. Audiobooks are left out.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  Text('What is missing', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  _row('Songs', r.songs),
                  _row('Artist and album known', r.complete),
                  _row('No artist', r.noArtist),
                  _row('No album', r.noAlbum),
                  _row('No genre', r.noGenre),
                  _row('No year', r.noYear),
                  _row('No cover', r.noCover),
                  const Divider(height: 32),
                  Text('Fill in from the file names', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Reads names like "01 - Artist - Title" for a missing title, artist or track number. '
                    'Nothing leaves your phone.',
                    style: muted,
                  ),
                  const SizedBox(height: 8),
                  FilledButton.tonalIcon(
                    key: const Key('from-filenames'),
                    onPressed: _searching ? null : _fromFileNames,
                    icon: const Icon(Icons.drive_file_rename_outline_rounded),
                    label: Text('Review ${r.fromFileNames} song${r.fromFileNames == 1 ? '' : 's'}'),
                  ),
                  const Divider(height: 32),
                  Text('Find missing details online', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Asks MusicBrainz about songs that lack an album, a year or a genre, by title, artist, album and '
                    'length (about one song a second; 2,000 songs take roughly half an hour). You can stop '
                    'and carry on later. Nothing is changed until you approve it.',
                    style: muted,
                  ),
                  const SizedBox(height: 8),
                  if (_searching) ...[
                    LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
                    const SizedBox(height: 4),
                    Text('$_done of $_total${_current == null ? '' : ' · $_current'}',
                        maxLines: 1, overflow: TextOverflow.ellipsis, style: muted),
                    TextButton(
                      key: const Key('search-stop'),
                      onPressed: () => setState(() => _stop = true),
                      child: Text(_stop ? 'Stopping…' : 'Stop'),
                    ),
                  ] else
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          key: const Key('search-online'),
                          onPressed: _search,
                          icon: const Icon(Icons.travel_explore_rounded),
                          label: const Text('Search online'),
                        ),
                        if (r.pendingSuggestions > 0)
                          FilledButton.icon(
                            key: const Key('review-suggestions'),
                            onPressed: _reviewSuggestions,
                            icon: const Icon(Icons.fact_check_outlined),
                            label: Text('Review ${r.pendingSuggestions} suggestion${r.pendingSuggestions == 1 ? '' : 's'}'),
                          ),
                      ],
                    ),
                  if (r.noMatch > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('${r.noMatch} song${r.noMatch == 1 ? '' : 's'} had no match.', style: muted),
                    ),
                  const Divider(height: 32),
                  Text('Covers', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    '${r.noCover} song${r.noCover == 1 ? ' has' : 's have'} no cover. Sure matches from the online '
                    'search can bring their cover when you apply them; this finds covers for the rest, album '
                    'by album (MusicBrainz and the Cover Art Archive).',
                    style: muted,
                  ),
                  const AlbumArtTile(),
                  const Divider(height: 32),
                  Text('Undo', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    r.lastBatch == null
                        ? 'Nothing to undo.'
                        : 'The last batch changed ${r.lastBatch!.songs} song${r.lastBatch!.songs == 1 ? '' : 's'}.',
                    style: muted,
                  ),
                  if (r.lastBatch != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        key: const Key('undo-last'),
                        onPressed: _searching ? null : _undo,
                        child: const Text('Undo the last batch'),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
