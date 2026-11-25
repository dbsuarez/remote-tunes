import 'package:drift/drift.dart';

import '../../data/database/app_database.dart';

/// One bar: a name and a number.
class InsightItem {
  const InsightItem(this.label, this.value, {this.detail = ''});
  final String label;
  final int value;

  /// A second line (for example the artist of a song).
  final String detail;
}

/// What the library says about itself, worked out on the phone from its own database. Nothing is
/// sent anywhere.
class LibraryInsights {
  const LibraryInsights({
    this.songs = 0,
    this.seconds = 0,
    this.bytes = 0,
    this.favorites = 0,
    this.neverPlayed = 0,
    this.playedThisWeek = 0,
    this.artists = 0,
    this.albums = 0,
    this.genres = const [],
    this.topArtists = const [],
    this.addedByMonth = const [],
    this.mostPlayed = const [],
    this.mostSkipped = const [],
    this.recentlyPlayed = const [],
    this.recentlyAdded = const [],
    this.playLog = const PlayLogInsights(),
  });

  final int songs;
  final int seconds;
  final int bytes;
  final int favorites;
  final int neverPlayed;
  final int playedThisWeek;
  final int artists;
  final int albums;

  /// Songs per genre, the biggest first.
  final List<InsightItem> genres;

  /// Songs per artist, the biggest first.
  final List<InsightItem> topArtists;

  /// Songs added in each of the last twelve months, oldest first (label "2026-11").
  final List<InsightItem> addedByMonth;
  final List<InsightItem> mostPlayed;
  final List<InsightItem> mostSkipped;
  final List<InsightItem> recentlyPlayed;
  final List<InsightItem> recentlyAdded;

  /// What the play log says (empty until songs have been played with it on).
  final PlayLogInsights playLog;

  bool get isEmpty => songs == 0;
}

/// What the play log says: how much was listened to, and when.
class PlayLogInsights {
  const PlayLogInsights({
    this.plays = 0,
    this.totalSeconds = 0,
    this.weekSeconds = 0,
    this.weekPlays = 0,
    this.finished = 0,
    this.skipped = 0,
    this.playsByDay = const [],
    this.minutesByDay = const [],
    this.minutesByGenre = const [],
    this.minutesByArtist = const [],
  });

  /// Plays in the log, and the time heard in all of them.
  final int plays;
  final int totalSeconds;

  /// The same for the last seven days.
  final int weekSeconds;
  final int weekPlays;

  /// How many ended at the end of the song, and how many were skipped.
  final int finished;
  final int skipped;

  /// The last 14 days, oldest first (label "11-25"): plays, and minutes heard.
  final List<InsightItem> playsByDay;
  final List<InsightItem> minutesByDay;

  /// Minutes heard per genre and per artist, the most first.
  final List<InsightItem> minutesByGenre;
  final List<InsightItem> minutesByArtist;

  bool get isEmpty => plays == 0;
}

/// Reads the numbers for the Insights screen. [now] is for tests.
Future<LibraryInsights> loadInsights(AppDatabase db, {DateTime? now}) async {
  final at = now ?? DateTime.now();

  Future<int> one(String sql, [List<Variable> vars = const []]) async =>
      (await db.customSelect(sql, variables: vars).getSingle()).read<int>('c');

  final totals = await db
      .customSelect(
        'SELECT COUNT(*) AS c, IFNULL(SUM(duration_seconds), 0) AS d, '
        'IFNULL(SUM(file_size_bytes), 0) AS b, '
        'SUM(CASE WHEN favorite = 1 THEN 1 ELSE 0 END) AS f, '
        'SUM(CASE WHEN play_count = 0 THEN 1 ELSE 0 END) AS n FROM songs',
      )
      .getSingle();
  final songs = totals.read<int>('c');
  if (songs == 0) return const LibraryInsights();

  final weekAgo = at.subtract(const Duration(days: 7));
  final playedThisWeek = await one(
    'SELECT COUNT(*) AS c FROM songs WHERE last_played_at IS NOT NULL AND last_played_at >= ?',
    [Variable<DateTime>(weekAgo)],
  );
  final artists = await one(
    "SELECT COUNT(DISTINCT lower(IFNULL(artist, ''))) AS c FROM songs",
  );
  final albums = await one(
    "SELECT COUNT(DISTINCT lower(IFNULL(artist, '')) || '|' || lower(IFNULL(album, ''))) AS c FROM songs",
  );

  List<InsightItem> items(Iterable<QueryRow> rows, {String detail = ''}) => [
        for (final r in rows)
          InsightItem(
            r.read<String>('name'),
            r.read<int>('n'),
            detail: detail.isEmpty ? '' : (r.readNullable<String>(detail) ?? ''),
          ),
      ];

  final genres = items(await db
      .customSelect(
        "SELECT genre AS name, COUNT(*) AS n FROM songs WHERE genre IS NOT NULL AND genre != '' "
        'GROUP BY lower(genre) ORDER BY n DESC, name LIMIT 8',
      )
      .get());
  final topArtists = items(await db
      .customSelect(
        "SELECT artist AS name, COUNT(*) AS n FROM songs WHERE artist IS NOT NULL AND artist != '' "
        "AND lower(artist) NOT LIKE 'unknown%' "
        'GROUP BY lower(artist) ORDER BY n DESC, name LIMIT 8',
      )
      .get());

  // The last twelve months, with the quiet ones as zero.
  final firstMonth = DateTime(at.year, at.month - 11);
  final perMonth = <String, int>{
    for (final r in await db
        .customSelect(
          "SELECT strftime('%Y-%m', added_at, 'unixepoch') AS m, COUNT(*) AS n FROM songs "
          'WHERE added_at >= ? GROUP BY m',
          variables: [Variable<DateTime>(firstMonth)],
        )
        .get())
      if (r.readNullable<String>('m') != null) r.read<String>('m'): r.read<int>('n'),
  };
  final addedByMonth = [
    for (var i = 0; i < 12; i++)
      () {
        final d = DateTime(firstMonth.year, firstMonth.month + i);
        final key = '${d.year}-${d.month.toString().padLeft(2, '0')}';
        return InsightItem(key, perMonth[key] ?? 0);
      }(),
  ];

  final mostPlayed = items(
      await db
          .customSelect(
            'SELECT title AS name, play_count AS n, artist FROM songs WHERE play_count > 0 '
            'ORDER BY play_count DESC, title LIMIT 5',
          )
          .get(),
      detail: 'artist');
  final mostSkipped = items(
      await db
          .customSelect(
            'SELECT title AS name, skip_count AS n, artist FROM songs WHERE skip_count > 0 '
            'ORDER BY skip_count DESC, title LIMIT 5',
          )
          .get(),
      detail: 'artist');
  final recentlyPlayed = items(
      await db
          .customSelect(
            'SELECT title AS name, play_count AS n, artist FROM songs WHERE last_played_at IS NOT NULL '
            'ORDER BY last_played_at DESC LIMIT 5',
          )
          .get(),
      detail: 'artist');
  final recentlyAdded = items(
      await db
          .customSelect(
            'SELECT title AS name, 0 AS n, artist FROM songs ORDER BY added_at DESC, id DESC LIMIT 5',
          )
          .get(),
      detail: 'artist');

  final playLog = await _loadPlayLog(db, at);

  return LibraryInsights(
    songs: songs,
    seconds: totals.read<int>('d'),
    bytes: totals.read<int>('b'),
    favorites: totals.read<int?>('f') ?? 0,
    neverPlayed: totals.read<int?>('n') ?? 0,
    playedThisWeek: playedThisWeek,
    artists: artists,
    albums: albums,
    genres: genres,
    topArtists: topArtists,
    addedByMonth: addedByMonth,
    mostPlayed: mostPlayed,
    mostSkipped: mostSkipped,
    recentlyPlayed: recentlyPlayed,
    recentlyAdded: recentlyAdded,
    playLog: playLog,
  );
}

Future<PlayLogInsights> _loadPlayLog(AppDatabase db, DateTime at) async {
  final week = at.subtract(const Duration(days: 7));
  final totals = await db
      .customSelect(
        'SELECT COUNT(*) AS c, IFNULL(SUM(heard_seconds), 0) AS s, '
        "SUM(CASE WHEN outcome = 'finished' THEN 1 ELSE 0 END) AS f, "
        "SUM(CASE WHEN outcome = 'skipped' THEN 1 ELSE 0 END) AS k, "
        'SUM(CASE WHEN started_at >= ? THEN 1 ELSE 0 END) AS wc, '
        'IFNULL(SUM(CASE WHEN started_at >= ? THEN heard_seconds ELSE 0 END), 0) AS ws '
        'FROM play_events',
        variables: [
          Variable<int>(week.millisecondsSinceEpoch ~/ 1000),
          Variable<int>(week.millisecondsSinceEpoch ~/ 1000),
        ],
      )
      .getSingle();
  final plays = totals.read<int>('c');
  if (plays == 0) return const PlayLogInsights();

  // The last 14 days, with the quiet ones as zero.
  final first = DateTime(at.year, at.month, at.day - 13);
  // Grouped by the phone's own days here (not in SQL, which may not know the time zone).
  final perDay = <String, (int, int)>{};
  for (final r in await db
      .customSelect(
        'SELECT started_at, heard_seconds FROM play_events WHERE started_at >= ?',
        variables: [Variable<int>(first.millisecondsSinceEpoch ~/ 1000)],
      )
      .get()) {
    final d = DateTime.fromMillisecondsSinceEpoch(r.read<int>('started_at') * 1000);
    final key = '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final old = perDay[key] ?? (0, 0);
    perDay[key] = (old.$1 + 1, old.$2 + r.read<int>('heard_seconds'));
  }
  final playsByDay = <InsightItem>[];
  final minutesByDay = <InsightItem>[];
  for (var i = 0; i < 14; i++) {
    final d = DateTime(first.year, first.month, first.day + i);
    final key = '${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final v = perDay[key] ?? (0, 0);
    playsByDay.add(InsightItem(key, v.$1));
    minutesByDay.add(InsightItem(key, (v.$2 / 60).round()));
  }

  List<InsightItem> minutes(Iterable<QueryRow> rows) => [
        for (final r in rows)
          if ((r.read<int>('s') / 60).round() > 0) InsightItem(r.read<String>('name'), (r.read<int>('s') / 60).round()),
      ];
  final byGenre = minutes(await db
      .customSelect(
        'SELECT s.genre AS name, SUM(e.heard_seconds) AS s FROM play_events e JOIN songs s ON s.id = e.song_id '
        "WHERE s.genre IS NOT NULL AND s.genre != '' GROUP BY lower(s.genre) ORDER BY s DESC, name LIMIT 6",
      )
      .get());
  final byArtist = minutes(await db
      .customSelect(
        'SELECT s.artist AS name, SUM(e.heard_seconds) AS s FROM play_events e JOIN songs s ON s.id = e.song_id '
        "WHERE s.artist IS NOT NULL AND s.artist != '' AND lower(s.artist) NOT LIKE 'unknown%' "
        'GROUP BY lower(s.artist) ORDER BY s DESC, name LIMIT 6',
      )
      .get());

  return PlayLogInsights(
    plays: plays,
    totalSeconds: totals.read<int>('s'),
    weekSeconds: totals.read<int>('ws'),
    weekPlays: totals.read<int?>('wc') ?? 0,
    finished: totals.read<int?>('f') ?? 0,
    skipped: totals.read<int?>('k') ?? 0,
    playsByDay: playsByDay,
    minutesByDay: minutesByDay,
    minutesByGenre: byGenre,
    minutesByArtist: byArtist,
  );
}
