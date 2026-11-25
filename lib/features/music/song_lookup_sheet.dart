import 'package:flutter/material.dart';

import '../../core/protocol/library_models.dart';
import '../library/lookup_models.dart';

/// What the user chose from the look-up of one song.
class LookupChoice {
  const LookupChoice({
    this.match,
    this.cover,
    this.keepLyrics = false,
    this.lyricsFound = false,
  });

  /// The details to fill in (null: not wanted).
  final LookupMatch? match;

  /// The cover to use (null: not wanted).
  final LookupCover? cover;

  /// The lyrics that were found stay (otherwise they are forgotten again).
  final bool keepLyrics;
  final bool lyricsFound;
}

/// Looks the song up (details, cover, lyrics) and lets the user pick what to use. Null if cancelled.
Future<LookupChoice?> showSongLookup(
  BuildContext context, {
  required SongLookupService lookup,
  required RemoteSong song,
}) {
  return showDialog<LookupChoice>(
    context: context,
    builder: (_) => SongLookupDialog(lookup: lookup, song: song),
  );
}

class SongLookupDialog extends StatefulWidget {
  const SongLookupDialog({super.key, required this.lookup, required this.song});

  final SongLookupService lookup;
  final RemoteSong song;

  @override
  State<SongLookupDialog> createState() => _SongLookupDialogState();
}

class _SongLookupDialogState extends State<SongLookupDialog> {
  List<LookupMatch>? _matches;
  String? _matchError;
  int _selected = 0;
  bool _useDetails = true;

  bool _coverLoading = false;
  LookupCover? _cover;
  bool _useCover = true;

  bool _lyricsLoading = true;
  RemoteLyrics? _lyrics;
  bool _keepLyrics = true;

  @override
  void initState() {
    super.initState();
    _searchDetails();
    _searchLyrics();
  }

  Future<void> _searchDetails() async {
    try {
      final m = await widget.lookup.search(
        title: widget.song.title,
        artist: widget.song.artist,
        album: widget.song.album,
        durationSeconds: widget.song.durationSeconds,
      );
      if (!mounted) return;
      setState(() => _matches = m);
      if (m.isNotEmpty) _loadCover();
    } on LookupException catch (e) {
      if (mounted) setState(() => _matchError = e.message);
    } catch (_) {
      if (mounted) {
        setState(() => _matchError = 'The look-up failed. Try again later.');
      }
    }
  }

  Future<void> _loadCover() async {
    final m = _matches;
    if (m == null || m.isEmpty) return;
    final wanted = m[_selected];
    setState(() {
      _coverLoading = true;
      _cover = null;
    });
    LookupCover? c;
    try {
      c = await widget.lookup.coverFor(wanted);
    } catch (_) {
      c = null;
    }
    // Only if the same match is still chosen.
    if (!mounted || m[_selected] != wanted) return;
    setState(() {
      _cover = c;
      _coverLoading = false;
    });
  }

  Future<void> _searchLyrics() async {
    if (widget.song.id <= 0) {
      setState(() => _lyricsLoading = false);
      return;
    }
    RemoteLyrics? l;
    try {
      l = await widget.lookup.lyricsFor(widget.song.id);
    } catch (_) {
      l = null;
    }
    if (mounted) {
      setState(() {
        _lyrics = l;
        _lyricsLoading = false;
      });
    }
  }

  LookupChoice _choice() {
    final m = _matches;
    final found = _lyrics?.found == true;
    return LookupChoice(
      match: (_useDetails && m != null && m.isNotEmpty) ? m[_selected] : null,
      cover: (_useCover && _cover != null) ? _cover : null,
      keepLyrics: found && _keepLyrics,
      lyricsFound: found,
    );
  }

  Future<void> _apply() async {
    final c = _choice();
    // Lyrics that were found but not wanted are forgotten again.
    if (c.lyricsFound && !c.keepLyrics) {
      try {
        await widget.lookup.discardLyrics(widget.song.id);
      } catch (_) {}
    }
    if (mounted) Navigator.pop(context, c);
  }

  Widget _section(ThemeData theme, String title, Widget body) => Padding(
    padding: const EdgeInsets.only(top: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleSmall?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 4),
        body,
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final m = _matches;
    final lyrics = _lyrics;
    final preview = lyrics == null
        ? const <String>[]
        : (lyrics.plain.isNotEmpty
                  ? lyrics.plain
                  : lyrics.synced.replaceAll(RegExp(r'\[[^\]]*\]\s*'), ''))
              .split('\n')
              .where((l) => l.trim().isNotEmpty)
              .take(4)
              .toList();

    return AlertDialog(
      title: const Text('Look up this song'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Only the title, artist, album and length are sent, to MusicBrainz (details), the Cover Art '
                'Archive (cover) and the lyrics sources.',
                style: muted,
              ),
              _section(
                theme,
                'Details',
                _matchError != null
                    ? Text(
                        _matchError!,
                        style: TextStyle(color: theme.colorScheme.error),
                      )
                    : m == null
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : m.isEmpty
                    ? const Text('No matches found.')
                    : Column(
                        children: [
                          RadioGroup<int>(
                            groupValue: _selected,
                            onChanged: (v) {
                              setState(() {
                                _selected = v ?? 0;
                                _useDetails = true;
                              });
                              _loadCover();
                            },
                            child: Column(
                              children: [
                                for (var i = 0; i < m.length; i++)
                                  RadioListTile<int>(
                                    key: ValueKey('match-$i'),
                                    contentPadding: EdgeInsets.zero,
                                    dense: true,
                                    value: i,
                                    title: Text(
                                      m[i].title,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    subtitle: Text(
                                      [
                                        m[i].artist,
                                        if (m[i].album.isNotEmpty) m[i].album,
                                        if (m[i].year != null) '${m[i].year}',
                                        if (m[i].trackNumber != null)
                                          'track ${m[i].trackNumber}',
                                      ].where((x) => x.isNotEmpty).join(' · '),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          CheckboxListTile(
                            key: const Key('use-details'),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text('Use these details'),
                            subtitle: const Text(
                              'Fills in the title, artist, album and track number',
                            ),
                            value: _useDetails,
                            onChanged: (v) =>
                                setState(() => _useDetails = v ?? true),
                          ),
                        ],
                      ),
              ),
              if (m != null && m.isNotEmpty)
                _section(
                  theme,
                  'Cover',
                  _coverLoading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 8),
                          child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        )
                      : _cover == null
                      ? const Text('No cover found for this one.')
                      : Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.memory(
                                _cover!.bytes,
                                key: const Key('cover-preview'),
                                width: 96,
                                height: 96,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => const SizedBox(
                                  width: 96,
                                  height: 96,
                                  child: Icon(Icons.broken_image_outlined),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: CheckboxListTile(
                                key: const Key('use-cover'),
                                contentPadding: EdgeInsets.zero,
                                dense: true,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                title: const Text('Use this cover'),
                                subtitle: const Text(
                                  'For every song of this album',
                                ),
                                value: _useCover,
                                onChanged: (v) =>
                                    setState(() => _useCover = v ?? true),
                              ),
                            ),
                          ],
                        ),
                ),
              _section(
                theme,
                'Lyrics',
                _lyricsLoading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : widget.song.id <= 0
                    ? Text(
                        'Lyrics are looked up for songs in the library.',
                        style: muted,
                      )
                    : lyrics == null
                    ? const Text('The lyrics could not be looked up.')
                    : lyrics.disabled
                    ? const Text(
                        'Lyrics from the internet are switched off in Settings.',
                      )
                    : lyrics.failed
                    ? const Text(
                        'No internet connection for the lyrics. Try again later.',
                      )
                    : !lyrics.found
                    ? const Text('No lyrics found.')
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            lyrics.instrumental
                                ? 'Instrumental (${lyrics.source})'
                                : 'Found (${lyrics.source}${lyrics.synced.isNotEmpty ? ', timed' : ''})',
                            style: muted,
                          ),
                          for (final l in preview)
                            Text(
                              l,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          CheckboxListTile(
                            key: const Key('keep-lyrics'),
                            contentPadding: EdgeInsets.zero,
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            title: const Text('Keep these lyrics'),
                            value: _keepLyrics,
                            onChanged: (v) =>
                                setState(() => _keepLyrics = v ?? true),
                          ),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          key: const Key('lookup-apply'),
          onPressed: _apply,
          child: const Text('Apply'),
        ),
      ],
    );
  }
}
