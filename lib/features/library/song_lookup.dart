import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;

import '../../core/protocol/library_models.dart';
import '../../data/database/app_database.dart';
import '../player/lyrics_service.dart';
import 'lookup_models.dart';

export 'lookup_models.dart';

/// Looks up one song on the internet, on request: its details (MusicBrainz), its cover (Cover Art
/// Archive) and its lyrics (the same sources as the lyrics view). Only the title, artist, album and
/// length are sent. One request a second (MusicBrainz's rule).
class SongLookup implements SongLookupService {
  SongLookup({
    required this.db,
    required this.lyrics,
    required this.artDir,
    http.Client? client,
    this.gap = const Duration(milliseconds: 1100),
    this.timeout = const Duration(seconds: 12),
  }) : _client = client ?? http.Client();

  final AppDatabase db;
  final LyricsService lyrics;

  /// Where cover pictures are kept.
  final Future<Directory> Function() artDir;
  final http.Client _client;
  final Duration gap;
  final Duration timeout;

  static const _userAgent = 'RemoteTunes (https://github.com/dbsuarez/remote-tunes)';
  static const _maxBytes = 3 * 1024 * 1024;

  DateTime? _last;

  Future<http.Response?> _get(Uri uri) async {
    final last = _last;
    if (last != null) {
      final wait = gap - DateTime.now().difference(last);
      if (wait > Duration.zero) await Future<void>.delayed(wait);
    }
    _last = DateTime.now();
    try {
      return await _client.get(uri, headers: const {'User-Agent': _userAgent}).timeout(timeout);
    } catch (_) {
      throw const LookupException('No internet connection, or MusicBrainz did not answer.');
    }
  }

  static String _q(String s) => s.replaceAll('"', ' ').replaceAll(r'\', ' ').trim();

  static bool _unknown(String s) {
    final l = s.trim().toLowerCase();
    return l.isEmpty || l.startsWith('unknown') || l == '<unknown>';
  }

  /// Up to six possible matches for the song, the best first (closest in length, then by
  /// MusicBrainz's own score). Empty if there is nothing.
  @override
  Future<List<LookupMatch>> search({
    required String title,
    String artist = '',
    String album = '',
    int durationSeconds = 0,
  }) async {
    if (title.trim().isEmpty) return const [];
    final parts = <String>['recording:"${_q(title)}"'];
    if (!_unknown(artist)) parts.add('artist:"${_q(artist)}"');
    final res = await _get(Uri.https('musicbrainz.org', '/ws/2/recording/',
        {'query': parts.join(' AND '), 'fmt': 'json', 'limit': '8'}));
    if (res == null) return const [];
    if (res.statusCode == 503 || res.statusCode == 429) {
      throw const LookupException('MusicBrainz is busy. Try again in a moment.');
    }
    if (res.statusCode != 200) {
      throw const LookupException('MusicBrainz did not answer. Try again later.');
    }
    final Object? body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      return const [];
    }
    final recordings = body is Map ? body['recordings'] : null;
    if (recordings is! List) return const [];

    final out = <LookupMatch>[];
    final seen = <String>{};
    for (final r in recordings.whereType<Map>()) {
      final rTitle = r['title'];
      if (rTitle is! String || rTitle.trim().isEmpty) continue;
      final credit = r['artist-credit'];
      final rArtist = credit is List
          ? credit
              .whereType<Map>()
              .map((c) => (c['name'] ?? (c['artist'] is Map ? (c['artist'] as Map)['name'] : '')))
              .whereType<String>()
              .join('')
          : '';
      final score = r['score'] is num ? (r['score'] as num).toInt() : 0;
      final length = r['length'] is num ? ((r['length'] as num) / 1000).round() : null;
      final releases = r['releases'];
      final list = releases is List ? releases.whereType<Map>().toList() : <Map>[];
      // A recording with no release still gives title and artist.
      if (list.isEmpty) list.add(const {});
      for (final rel in list.take(3)) {
        final relTitle = rel['title'] is String ? rel['title'] as String : '';
        final date = rel['date'] is String ? rel['date'] as String : '';
        final year = date.length >= 4 ? int.tryParse(date.substring(0, 4)) : null;
        int? track;
        final media = rel['media'];
        if (media is List && media.isNotEmpty && media.first is Map) {
          final tracks = (media.first as Map)['track'];
          if (tracks is List && tracks.isNotEmpty && tracks.first is Map) {
            track = int.tryParse('${(tracks.first as Map)['number'] ?? ''}');
          }
        }
        final id = rel['id'];
        final key = '${rTitle.toLowerCase()}|${rArtist.toLowerCase()}|${relTitle.toLowerCase()}|$year';
        if (!seen.add(key)) continue;
        out.add(LookupMatch(
          title: rTitle.trim(),
          artist: rArtist.trim(),
          album: relTitle.trim(),
          year: year,
          trackNumber: track,
          releaseId: id is String && RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id) ? id : null,
          score: score,
          lengthSeconds: length,
        ));
      }
    }
    // The ones that sound like this song first: same length (within 3 s), then the album named.
    int closeness(LookupMatch m) {
      var c = 0;
      if (durationSeconds > 0 && m.lengthSeconds != null && (m.lengthSeconds! - durationSeconds).abs() <= 3) {
        c += 2;
      }
      if (!_unknown(album) && m.album.toLowerCase() == album.trim().toLowerCase()) c += 1;
      return c;
    }

    final indexed = out.asMap().entries.toList()
      ..sort((a, b) {
        final byClose = closeness(b.value).compareTo(closeness(a.value));
        if (byClose != 0) return byClose;
        final byScore = b.value.score.compareTo(a.value.score);
        return byScore != 0 ? byScore : a.key.compareTo(b.key);
      });
    return [for (final e in indexed.take(6)) e.value];
  }

  /// The front cover of the match's album, if the Cover Art Archive has one.
  @override
  Future<LookupCover?> coverFor(LookupMatch m) async {
    final id = m.releaseId;
    if (id == null) return null;
    final res = await _get(Uri.https('coverartarchive.org', '/release/$id/front-500'));
    if (res == null || res.statusCode != 200) return null;
    final b = res.bodyBytes;
    if (b.length < 100 || b.length > _maxBytes) return null;
    if (b[0] == 0xFF && b[1] == 0xD8) return LookupCover(b, 'jpg');
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return LookupCover(b, 'png');
    return null;
  }

  /// Looks the lyrics up again, even if a miss was remembered (and keeps what it finds).
  @override
  Future<RemoteLyrics> lyricsFor(int songId) => lyrics.forSong(songId, refresh: true);

  /// Forgets the lyrics found for the song (the user did not want these).
  @override
  Future<void> discardLyrics(int songId) => lyrics.discard(songId);

  /// Makes [cover] the picture of every song that shares [songId]'s artist and album, and keeps
  /// the file. Returns how many songs got it.
  @override
  Future<int> applyCover(int songId, LookupCover cover) async {
    final row = await db.customSelect(
      'SELECT artist, album FROM songs WHERE id = ?',
      variables: [Variable<int>(songId)],
    ).getSingleOrNull();
    if (row == null) return 0;
    final artist = row.readNullable<String>('artist') ?? '';
    final album = row.readNullable<String>('album') ?? '';
    final dir = await artDir();
    await dir.create(recursive: true);
    var h = 0x811c9dc5;
    for (final u in '$artist|$album|${DateTime.now().millisecondsSinceEpoch}'.toLowerCase().codeUnits) {
      h = ((h ^ u) * 0x01000193) & 0x7fffffff;
    }
    final file = File('${dir.path}${Platform.pathSeparator}cover_$h.${cover.ext}');
    await file.writeAsBytes(cover.bytes, flush: true);
    return db.customUpdate(
      'UPDATE songs SET album_art_path = ? WHERE lower(IFNULL(artist, \'\')) = lower(?) '
      'AND lower(IFNULL(album, \'\')) = lower(?)',
      variables: [Variable<String>(file.path), Variable<String>(artist), Variable<String>(album)],
      updates: {db.songs},
    );
  }
}
