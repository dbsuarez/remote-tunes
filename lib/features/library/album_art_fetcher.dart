import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;

import '../../data/database/app_database.dart';

/// What a run of the album-art finder did.
class ArtFetchResult {
  const ArtFetchResult({
    this.albums = 0,
    this.found = 0,
    this.notFound = 0,
    this.failed = 0,
    this.cancelled = false,
  });

  /// Albums that were missing a cover.
  final int albums;
  final int found;
  final int notFound;

  /// Albums skipped because the internet could not be reached.
  final int failed;
  final bool cancelled;
}

/// Finds covers for songs that have none, on request.
///
/// For each album without a cover it asks MusicBrainz for the release and the
/// Cover Art Archive for its front picture, and saves the picture on this
/// phone. Only the artist and album names are sent. One request a second
/// (MusicBrainz's rule), and only when the user starts it.
class AlbumArtFetcher {
  AlbumArtFetcher({
    required this.db,
    required this.directory,
    http.Client? client,
    this.gap = const Duration(milliseconds: 1100),
    this.timeout = const Duration(seconds: 12),
  }) : _client = client ?? http.Client();

  final AppDatabase db;

  /// Where pictures are saved.
  final Future<Directory> Function() directory;
  final http.Client _client;
  final Duration gap;
  final Duration timeout;

  static const _userAgent = 'RemoteTunes (https://github.com/dbsuarez/remote-tunes)';
  static const _maxBytes = 3 * 1024 * 1024;

  /// Songs with a file and no cover, grouped by album.
  Future<Map<({String artist, String album}), List<int>>> missing() async {
    final rows = await db.customSelect(
      "SELECT id, artist, album FROM songs WHERE file_path IS NOT NULL "
      "AND (album_art_path IS NULL OR album_art_path = '')",
    ).get();
    final out = <({String artist, String album}), List<int>>{};
    for (final r in rows) {
      final album = _clean(r.readNullable<String>('album'));
      final artist = _clean(r.readNullable<String>('artist'));
      if (album.isEmpty || artist.isEmpty) continue; // nothing to look up by
      out.putIfAbsent((artist: artist, album: album), () => []).add(r.read<int>('id'));
    }
    return out;
  }

  static String _clean(String? s) {
    final t = (s ?? '').trim();
    final l = t.toLowerCase();
    return (l.startsWith('unknown') || l == '<unknown>') ? '' : t;
  }

  /// How many albums are missing a cover (for the button's label).
  Future<int> missingAlbums() async => (await missing()).length;

  /// Runs over every album that has no cover. [onProgress] gets (done, total).
  /// Stops early when [isCancelled] returns true.
  Future<ArtFetchResult> run({
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final todo = await missing();
    final total = todo.length;
    var done = 0, found = 0, notFound = 0, failed = 0;
    var first = true;
    for (final e in todo.entries) {
      if (isCancelled?.call() ?? false) {
        return ArtFetchResult(
            albums: total, found: found, notFound: notFound, failed: failed, cancelled: true);
      }
      if (!first) await Future<void>.delayed(gap);
      first = false;
      try {
        final pic = await _findCover(e.key.artist, e.key.album);
        if (pic == null) {
          notFound++;
        } else {
          final path = await _save(e.key.artist, e.key.album, pic);
          await _apply(e.value, path);
          found++;
        }
      } on _NetworkTrouble {
        failed++;
      }
      done++;
      onProgress?.call(done, total);
    }
    return ArtFetchResult(albums: total, found: found, notFound: notFound, failed: failed);
  }

  Future<void> _apply(List<int> ids, String path) async {
    await db.customUpdate(
      'UPDATE songs SET album_art_path = ? WHERE id IN (${ids.join(',')})',
      variables: [Variable<String>(path)],
      updates: {db.songs},
    );
  }

  Future<String> _save(String artist, String album, _Picture pic) async {
    final dir = await directory();
    await dir.create(recursive: true);
    var h = 0x811c9dc5;
    for (final u in '$artist|$album'.toLowerCase().codeUnits) {
      h = ((h ^ u) * 0x01000193) & 0x7fffffff;
    }
    final file = File('${dir.path}${Platform.pathSeparator}cover_$h.${pic.ext}');
    await file.writeAsBytes(pic.bytes, flush: true);
    return file.path;
  }

  Future<_Picture?> _findCover(String artist, String album) async {
    final query = 'release:"${_q(album)}" AND artist:"${_q(artist)}"';
    final res = await _get(Uri.https(
        'musicbrainz.org', '/ws/2/release/', {'query': query, 'fmt': 'json', 'limit': '3'}));
    if (res == null || res.statusCode != 200) {
      if (res != null && res.statusCode >= 500) throw _NetworkTrouble();
      return null;
    }
    final Object? body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      return null;
    }
    final releases = body is Map ? body['releases'] : null;
    if (releases is! List) return null;
    for (final r in releases.whereType<Map>().take(3)) {
      final id = r['id'];
      if (id is! String || !RegExp(r'^[0-9a-fA-F-]{36}$').hasMatch(id)) continue;
      await Future<void>.delayed(gap);
      final pic = await _get(Uri.https('coverartarchive.org', '/release/$id/front-500'));
      if (pic == null || pic.statusCode != 200) continue;
      final p = _asPicture(pic.bodyBytes);
      if (p != null) return p;
    }
    return null;
  }

  /// Quotes made safe for the search text.
  static String _q(String s) => s.replaceAll('"', ' ').replaceAll(r'\', ' ');

  Future<http.Response?> _get(Uri uri) async {
    try {
      return await _client.get(uri, headers: const {'User-Agent': _userAgent}).timeout(timeout);
    } catch (_) {
      throw _NetworkTrouble();
    }
  }

  /// Only real pictures of a sensible size are kept.
  _Picture? _asPicture(Uint8List b) {
    if (b.length < 100 || b.length > _maxBytes) return null;
    if (b[0] == 0xFF && b[1] == 0xD8) return _Picture(b, 'jpg');
    if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) return _Picture(b, 'png');
    return null;
  }
}

class _Picture {
  const _Picture(this.bytes, this.ext);
  final Uint8List bytes;
  final String ext;
}

class _NetworkTrouble implements Exception {}
