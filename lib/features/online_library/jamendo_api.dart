import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../core/jamendo_url.dart';

/// What to search Jamendo for.
enum JamendoSearchMode {
  keyword('Keyword', 'Song, artist, album or tag'),
  genre('Genre', 'A genre, for example jazz or hiphop'),
  artist('Artist', 'Artist name'),
  album('Album', 'Album name');

  const JamendoSearchMode(this.label, this.hint);

  final String label;
  final String hint;
}

/// The ready-made lists on the Online Library home screen (Jamendo sorts them).
enum JamendoShelf {
  week('Popular this week', 'popularity_week'),
  month('Popular this month', 'popularity_month'),
  newest('Newest releases', 'releasedate_desc');

  const JamendoShelf(this.title, this.order);

  final String title;

  /// Jamendo's `order` value.
  final String order;
}

/// Genres offered as quick picks (Jamendo "tags").
const List<String> jamendoGenres = [
  'pop',
  'rock',
  'electronic',
  'hiphop',
  'jazz',
  'classical',
  'ambient',
  'folk',
  'metal',
  'reggae',
  'blues',
  'lounge',
];

class JamendoTrack {
  const JamendoTrack({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    required this.durationSeconds,
    required this.audioUrl,
    this.imageUrl,
    this.licenseUrl,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final int durationSeconds;

  /// The streaming address (sent to the Player, which plays it).
  final String audioUrl;
  final String? imageUrl;

  /// Link to the Creative Commons licence text.
  final String? licenseUrl;

  /// A short licence name such as "CC BY-NC-SA 3.0".
  String get licenseLabel => licenseLabelFor(licenseUrl);

  /// Parses one entry of Jamendo's `results`. Null if it has no usable title or
  /// stream, or points anywhere but Jamendo.
  static JamendoTrack? fromJson(Object? raw) {
    if (raw is! Map) return null;
    String s(String k) => raw[k] is String ? (raw[k] as String).trim() : '';
    final audio = _jamendoUrl(s('audio'));
    final title = s('name');
    final id = '${raw['id'] ?? ''}'.trim();
    if (audio == null || title.isEmpty || id.isEmpty) return null;
    final d = raw['duration'];
    final seconds = d is num ? d.toInt() : int.tryParse('$d') ?? 0;
    // Jamendo sometimes sends "image" and sometimes "album_image".
    final image = _jamendoUrl(s('image')) ?? _jamendoUrl(s('album_image'));
    final license = s('license_ccurl');
    return JamendoTrack(
      id: id,
      title: title,
      artist: s('artist_name').isEmpty ? 'Unknown artist' : s('artist_name'),
      album: s('album_name').isEmpty ? 'Unknown album' : s('album_name'),
      durationSeconds: seconds < 0 ? 0 : seconds,
      audioUrl: audio,
      imageUrl: image,
      licenseUrl: license.isEmpty ? null : license,
    );
  }

  /// Only https links on jamendo.com are accepted, whatever the response says.
  static String? _jamendoUrl(String url) => jamendoHttpsUrl(url);
}

/// "https://creativecommons.org/licenses/by-nc-sa/3.0/" -> "CC BY-NC-SA 3.0".
String licenseLabelFor(String? url) {
  if (url == null || url.isEmpty) return 'See Jamendo';
  final m = RegExp(r'/licenses/([a-z\-]+)/([0-9.]+)').firstMatch(url);
  if (m != null) return 'CC ${m.group(1)!.toUpperCase()} ${m.group(2)}';
  if (url.contains('publicdomain/zero')) return 'CC0';
  if (url.contains('publicdomain')) return 'Public domain';
  return 'See Jamendo';
}

class JamendoPage {
  const JamendoPage({required this.tracks, required this.hasMore});

  final List<JamendoTrack> tracks;
  final bool hasMore;
}

/// A search that failed, with a plain-language [message]. [offline] is true
/// when the cause is the internet connection on this phone.
class JamendoException implements Exception {
  JamendoException(this.message, {this.offline = false, this.badKey = false});

  final String message;
  final bool offline;

  /// Jamendo did not accept the client ID.
  final bool badKey;

  @override
  String toString() => 'JamendoException: $message';
}

/// Searches Jamendo's free, Creative Commons catalogue.
///
/// Nothing is stored and no history is kept: each search is one request to
/// api.jamendo.com with the user's own client ID. Pure Dart, so the web
/// Controller can use it too.
class JamendoApi {
  JamendoApi({
    http.Client? client,
    this.baseUrl = 'https://api.jamendo.com/v3.0',
    this.timeout = const Duration(seconds: 12),
    this.minGap = const Duration(seconds: 3),
    this.retryDelay = const Duration(seconds: 3),
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final String baseUrl;
  final Duration timeout;

  /// Jamendo quietly answers "success, 0 results" to searches that arrive
  /// within a couple of seconds of each other (found by testing the live API:
  /// spaced about 3 seconds apart every search worked). So requests are spaced
  /// at least this far apart...
  final Duration minGap;

  /// ...and a first page that comes back empty is asked for once more after
  /// this long before the app says "no tracks found".
  final Duration retryDelay;

  DateTime? _lastRequestAt;

  static const pageSize = 20;

  Future<JamendoPage> search({
    required String clientId,
    required JamendoSearchMode mode,
    required String text,
    int offset = 0,
  }) async {
    final q = text.trim();
    if (q.isEmpty) {
      throw JamendoException('Type something to search for.');
    }
    var first = await _fetch(clientId, _params(mode, q, offset));
    if (first.isEmpty && offset == 0) {
      // Maybe throttled rather than really empty: ask once more.
      await Future<void>.delayed(retryDelay);
      first = await _fetch(clientId, _params(mode, q, offset));
    }
    // Artist and album filters match names closely. If nothing matched, look
    // wider and keep results whose name contains what was typed.
    if (first.isEmpty && offset == 0 &&
        (mode == JamendoSearchMode.artist || mode == JamendoSearchMode.album)) {
      final wide = await _fetch(clientId, _params(JamendoSearchMode.keyword, q, 0));
      final needle = q.toLowerCase();
      final kept = [
        for (final t in wide)
          if ((mode == JamendoSearchMode.artist ? t.artist : t.album)
              .toLowerCase()
              .contains(needle))
            t,
      ];
      return JamendoPage(tracks: kept, hasMore: false);
    }
    return JamendoPage(tracks: first, hasMore: first.length >= pageSize);
  }

  /// One of the ready-made lists, with no search.
  Future<JamendoPage> browse({
    required String clientId,
    required JamendoShelf shelf,
    int limit = 15,
  }) async {
    final tracks = await _fetch(clientId, {
      'format': 'json',
      'limit': '$limit',
      'offset': '0',
      'imagesize': '200',
      'audioformat': 'mp32',
      'order': shelf.order,
    });
    return JamendoPage(tracks: tracks, hasMore: false);
  }

  Map<String, String> _params(JamendoSearchMode mode, String q, int offset) => {
        'format': 'json',
        'limit': '$pageSize',
        'offset': '$offset',
        'imagesize': '200',
        'audioformat': 'mp32',
        'order': 'popularity_total',
        switch (mode) {
          JamendoSearchMode.keyword => 'search',
          JamendoSearchMode.genre => 'tags',
          JamendoSearchMode.artist => 'artist_name',
          JamendoSearchMode.album => 'album_name',
        // Jamendo genres are single words ("hiphop", "triphop", "newage"), so
        // "Hip Hop" is sent as "hiphop".
        }: mode == JamendoSearchMode.genre
            ? q.toLowerCase().replaceAll(RegExp(r'\s+'), '')
            : q,
      };

  Future<List<JamendoTrack>> _fetch(String clientId, Map<String, String> params) async {
    final uri = Uri.parse('$baseUrl/tracks/')
        .replace(queryParameters: {'client_id': clientId, ...params});
    final last = _lastRequestAt;
    if (last != null) {
      final wait = minGap - DateTime.now().difference(last);
      if (!wait.isNegative && wait > Duration.zero) await Future<void>.delayed(wait);
    }
    _lastRequestAt = DateTime.now();
    final http.Response response;
    try {
      response = await _client.get(uri).timeout(timeout);
    } on TimeoutException {
      throw JamendoException(
        'Jamendo took too long to answer. Check this phone\'s internet '
        'connection and try again.',
        offline: true,
      );
    } catch (_) {
      throw JamendoException(
        'No internet connection. The Online Library needs the internet on this '
        'phone. Your own music still works.',
        offline: true,
      );
    }
    if (response.statusCode != 200) {
      throw JamendoException(
          'Jamendo is not answering right now (error ${response.statusCode}). '
          'Try again later.');
    }
    final Object? body;
    try {
      body = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException {
      throw JamendoException("Jamendo's answer couldn't be read. Try again later.");
    }
    if (body is! Map) {
      throw JamendoException("Jamendo's answer couldn't be read. Try again later.");
    }
    final headers = body['headers'];
    if (headers is Map && headers['status'] != 'success') {
      final code = headers['code'];
      if (code == 5) {
        throw JamendoException(
          'Jamendo did not accept this client ID. Check it, or paste a new one.',
          badKey: true,
        );
      }
      final msg = headers['error_message'];
      throw JamendoException(msg is String && msg.isNotEmpty
          ? 'Jamendo said: ${msg.length > 160 ? msg.substring(0, 160) : msg}'
          : 'Jamendo could not run that search.');
    }
    final results = body['results'];
    if (results is! List) return const [];
    return [
      for (final r in results)
        if (JamendoTrack.fromJson(r) != null) JamendoTrack.fromJson(r)!,
    ];
  }

  void close() => _client.close();
}
