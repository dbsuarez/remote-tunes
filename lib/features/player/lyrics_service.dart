import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;

import '../../core/protocol/library_models.dart';
import '../../data/database/app_database.dart';
import '../../data/repositories/library_repository.dart';

/// Finds lyrics for a song, on demand and one song at a time, and remembers
/// them on the Player.
///
/// Sources, in order: LRCLIB (lrclib.net: free, no key, time-synced), then
/// lyrics.ovh (plain text). Only the song's title, artist, album and length are
/// sent, never a file name or path. Personal / open-source use; nothing is
/// downloaded in bulk.
class LyricsService {
  LyricsService({
    required this.library,
    required this.db,
    http.Client? client,
    Future<bool> Function()? isEnabled,
    DateTime Function()? now,
    this.timeout = const Duration(seconds: 6),
  })  : _client = client ?? http.Client(),
        _isEnabled = isEnabled ?? (() async => true),
        _now = now ?? DateTime.now;

  final LibraryRepository library;
  final AppDatabase db;
  final http.Client _client;
  final Future<bool> Function() _isEnabled;
  final DateTime Function() _now;
  final Duration timeout;

  /// Lyrics that were found are kept this long; "not found" is tried again
  /// sooner, since a song may get lyrics later.
  static const foundTtl = Duration(days: 30);
  static const missTtl = Duration(days: 1);

  static const _userAgent = 'RemoteTunes (https://github.com/dbsuarez/remote-tunes)';

  /// Songs being looked up right now, so two screens asking at once share one
  /// request.
  final Map<String, Future<RemoteLyrics>> _inFlight = {};

  /// Lyrics for a library song.
  Future<RemoteLyrics> forSong(int songId) async {
    if (!await _isEnabled()) return const RemoteLyrics(disabled: true);
    final song = await library.songById(songId);
    if (song == null) return const RemoteLyrics();
    final title = _clean(song.title);
    final artist = _clean(song.artist);
    if (title.isEmpty) return const RemoteLyrics();
    final album = _clean(song.album);
    final duration = song.durationSeconds ?? 0;
    final key = trackKey(title, artist, album, duration);

    final cached = await (db.select(db.lyricsCache)..where((t) => t.trackKey.equals(key)))
        .getSingleOrNull();
    if (cached != null) {
      final age = _now().difference(cached.fetchedAt);
      if (age < (cached.found ? foundTtl : missTtl)) return _fromRow(cached);
    }
    return _inFlight[key] ??= _lookup(key, title, artist, album, duration)
        .whenComplete(() {
      // (A block, so the removed Future is not waited on: it is this very one.)
      _inFlight.remove(key);
    });
  }

  /// Same song, same key, whatever the case or spacing.
  static String trackKey(String title, String artist, String album, int duration) =>
      [title, artist, album, duration.toString()]
          .map((s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim())
          .join('|');

  static String _clean(String? s) {
    final t = (s ?? '').trim();
    if (t.isEmpty) return '';
    final l = t.toLowerCase();
    if (l.startsWith('unknown') || l == '<unknown>') return '';
    return t;
  }

  Future<RemoteLyrics> _lookup(
      String key, String title, String artist, String album, int duration) async {
    var networkTrouble = false;
    RemoteLyrics? hit;

    // 1) LRCLIB, exact match first, then a search.
    try {
      hit = await _lrclibGet(title, artist, album, duration);
      hit ??= await _lrclibSearch(title, artist);
    } on _NetworkTrouble {
      networkTrouble = true;
    }
    // 2) lyrics.ovh (plain text only; needs an artist).
    if (hit == null && artist.isNotEmpty) {
      try {
        hit = await _lyricsOvh(title, artist);
      } on _NetworkTrouble {
        networkTrouble = true;
      }
    }

    if (hit == null) {
      // Do not remember a failure caused by the network: try again next time.
      if (networkTrouble) return const RemoteLyrics(failed: true);
      await _store(key, const RemoteLyrics(), '');
      return const RemoteLyrics();
    }
    await _store(key, hit, hit.source);
    return hit;
  }

  Future<void> _store(String key, RemoteLyrics l, String source) =>
      db.into(db.lyricsCache).insertOnConflictUpdate(LyricsCacheCompanion.insert(
            trackKey: key,
            found: Value(l.found),
            plainLyrics: Value(l.plain.isEmpty ? null : l.plain),
            syncedLyrics: Value(l.synced.isEmpty ? null : l.synced),
            instrumental: Value(l.instrumental),
            source: Value(source),
            fetchedAt: _now(),
          ));

  RemoteLyrics _fromRow(LyricsCacheData r) => RemoteLyrics(
        found: r.found,
        plain: r.plainLyrics ?? '',
        synced: r.syncedLyrics ?? '',
        instrumental: r.instrumental,
        source: r.source,
      );

  // ----------------------------------------------------------------- sources

  Future<Map<String, dynamic>?> _getJson(Uri uri) async {
    final http.Response res;
    try {
      res = await _client
          .get(uri, headers: const {'User-Agent': _userAgent}).timeout(timeout);
    } catch (_) {
      throw _NetworkTrouble();
    }
    if (res.statusCode == 404) return null;
    if (res.statusCode != 200) throw _NetworkTrouble();
    try {
      final v = jsonDecode(utf8.decode(res.bodyBytes));
      return v is Map<String, dynamic> ? v : {'_list': v};
    } catch (_) {
      return null;
    }
  }

  RemoteLyrics? _fromLrclib(Map<String, dynamic> j) {
    final synced = (j['syncedLyrics'] as String?)?.trim() ?? '';
    final plain = (j['plainLyrics'] as String?)?.trim() ?? '';
    final instrumental = j['instrumental'] == true;
    if (synced.isEmpty && plain.isEmpty && !instrumental) return null;
    return RemoteLyrics(
      found: true,
      plain: plain,
      synced: synced,
      instrumental: instrumental,
      source: 'LRCLIB',
    );
  }

  Future<RemoteLyrics?> _lrclibGet(
      String title, String artist, String album, int duration) async {
    // The exact lookup needs an artist; without one go straight to the search.
    if (artist.isEmpty) return null;
    final j = await _getJson(Uri.https('lrclib.net', '/api/get', {
      'track_name': title,
      'artist_name': artist,
      if (album.isNotEmpty) 'album_name': album,
      if (duration > 0) 'duration': '$duration',
    }));
    return j == null ? null : _fromLrclib(j);
  }

  Future<RemoteLyrics?> _lrclibSearch(String title, String artist) async {
    final j = await _getJson(Uri.https('lrclib.net', '/api/search', {
      'track_name': title,
      if (artist.isNotEmpty) 'artist_name': artist,
    }));
    final list = j?['_list'];
    if (list is! List) return null;
    RemoteLyrics? plainOnly;
    for (final e in list.whereType<Map<String, dynamic>>().take(5)) {
      final r = _fromLrclib(e);
      if (r == null) continue;
      if (r.synced.isNotEmpty || r.instrumental) return r;
      plainOnly ??= r;
    }
    return plainOnly;
  }

  Future<RemoteLyrics?> _lyricsOvh(String title, String artist) async {
    final j = await _getJson(Uri.https(
        'api.lyrics.ovh', '/v1/${Uri.encodeComponent(artist)}/${Uri.encodeComponent(title)}'));
    final text = (j?['lyrics'] as String?)?.trim() ?? '';
    if (text.isEmpty) return null;
    return RemoteLyrics(found: true, plain: text, source: 'lyrics.ovh');
  }
}

class _NetworkTrouble implements Exception {}
