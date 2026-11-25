/// What a file name says about a song: "01 - Artist - Title", "03. Title", "Artist - Title".
class FileNameGuess {
  const FileNameGuess({required this.title, this.artist, this.track});

  final String title;
  final String? artist;
  final int? track;
}

/// Reads a file name (without its extension) for a track number, an artist and a title. Returns null
/// when it looks like nothing but a plain title (nothing to learn from it).
FileNameGuess? parseFileName(String base) {
  var s = base.replaceAll('_', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (s.isEmpty) return null;

  // "01 - Artist - Title" and "01. Artist - Title".
  var m = RegExp(r'^(\d{1,3})\s*[-._)]\s*(.+?)\s+-\s+(.+)$').firstMatch(s);
  if (m != null) {
    return FileNameGuess(track: int.parse(m.group(1)!), artist: m.group(2)!.trim(), title: m.group(3)!.trim());
  }
  // "01 - Title", "03. Title", "7) Title".
  m = RegExp(r'^(\d{1,3})\s*[-._)]\s*(.+)$').firstMatch(s);
  if (m != null) {
    return FileNameGuess(track: int.parse(m.group(1)!), title: m.group(2)!.trim());
  }
  // "Artist - Title".
  m = RegExp(r'^(.+?)\s+-\s+(.+)$').firstMatch(s);
  if (m != null) {
    return FileNameGuess(artist: m.group(1)!.trim(), title: m.group(2)!.trim());
  }
  return null;
}

/// What a song has now and what is proposed for it. A null in [next] means "leave it as it is".
/// Only empty fields are ever filled: a good tag is never replaced.
class TagChange {
  const TagChange({
    required this.songId,
    required this.label,
    required this.source,
    this.title,
    this.artist,
    this.album,
    this.year,
    this.track,
    this.high = false,
    this.was = const {},
  });

  final int songId;

  /// The song as it reads now ("Title - Artist"), for the list.
  final String label;

  /// `filename` or `musicbrainz`.
  final String source;

  final String? title;
  final String? artist;
  final String? album;
  final int? year;
  final int? track;

  /// A sure match (it can be approved in one go).
  final bool high;

  /// The values before the change, by field (`title`, `artist`, `album`, `year`, `track`).
  final Map<String, Object?> was;

  bool get isEmpty => title == null && artist == null && album == null && year == null && track == null;

  /// The fields that would change, by name.
  Map<String, Object> get fields => {
        if (title != null) 'title': title!,
        if (artist != null) 'artist': artist!,
        if (album != null) 'album': album!,
        if (year != null) 'year': year!,
        if (track != null) 'track': track!,
      };

  /// "artist: Unknown artist -> Ann" lines for the review.
  List<String> get lines => [
        for (final e in fields.entries) '${e.key}: ${_shown(was[e.key])} → ${e.value}',
      ];

  static String _shown(Object? v) => v == null || '$v'.isEmpty ? '(empty)' : '$v';
}

/// Do two names say the same thing? Ignores capitals, accents-free punctuation and spaces.
bool sameName(String a, String b) {
  String n(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  final x = n(a);
  return x.isNotEmpty && x == n(b);
}

/// What the cleanup found in the library.
class TagCleanupReport {
  const TagCleanupReport({
    this.songs = 0,
    this.complete = 0,
    this.noArtist = 0,
    this.noAlbum = 0,
    this.noGenre = 0,
    this.noYear = 0,
    this.noCover = 0,
    this.fromFileNames = 0,
    this.pendingSuggestions = 0,
    this.noMatch = 0,
    this.lastBatch,
  });

  final int songs;

  /// Songs with a known artist and album.
  final int complete;
  final int noArtist;
  final int noAlbum;
  final int noGenre;
  final int noYear;
  final int noCover;

  /// Songs whose file name can fill an empty field.
  final int fromFileNames;

  /// Suggestions found online that wait for a decision, and songs that had no match.
  final int pendingSuggestions;
  final int noMatch;

  /// The newest change that can be undone, and how many songs it holds.
  final ({int id, int songs, DateTime at})? lastBatch;
}
