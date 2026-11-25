import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// A backup file that cannot be used, with a sentence to show.
class BackupException implements Exception {
  const BackupException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Lower case, one space between words: the same song written two ways matches.
String backupNorm(String s) => s.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();

/// A song as the backup remembers it: where it was (relative to the music root) and
/// what it was called, so it can be found again on another phone.
class BackupSong {
  BackupSong({
    required this.title,
    required this.artist,
    required this.album,
    required this.durationSeconds,
    this.relativePath,
    this.sizeBytes,
    this.favorite = false,
    this.plays = 0,
    this.skips = 0,
    this.lastPlayed,
    this.edited = false,
    this.trackNumber,
  });

  final String title;
  final String artist;
  final String album;
  final int durationSeconds;

  /// Path below the music root, with `/` (null: the file was a copy kept inside the app).
  final String? relativePath;
  final int? sizeBytes;
  final bool favorite;
  final int plays;
  final int skips;
  final DateTime? lastPlayed;

  /// The title, artist, album or track number was edited by hand on the old phone.
  final bool edited;
  final int? trackNumber;

  /// Same title, artist, album (and length to the second) means the same song.
  String keyFor(int duration) =>
      '${backupNorm(title)}|${backupNorm(artist)}|${backupNorm(album)}|$duration';

  String get titleArtistKey => '${backupNorm(title)}|${backupNorm(artist)}';

  Map<String, dynamic> toJson() => {
        't': title,
        'a': artist,
        'al': album,
        'd': durationSeconds,
        if (relativePath != null) 'p': relativePath,
        if (sizeBytes != null) 'sz': sizeBytes,
        if (favorite) 'fav': true,
        if (plays > 0) 'pl': plays,
        if (skips > 0) 'sk': skips,
        if (lastPlayed != null) 'lp': lastPlayed!.millisecondsSinceEpoch ~/ 1000,
        if (edited) 'ed': true,
        if (trackNumber != null) 'tn': trackNumber,
      };

  static BackupSong? fromJson(Object? j) {
    if (j is! Map) return null;
    final t = j['t'];
    if (t is! String || t.trim().isEmpty) return null;
    int n(Object? v) => v is num ? v.toInt() : 0;
    final lp = j['lp'];
    return BackupSong(
      title: t,
      artist: j['a'] is String ? j['a'] as String : '',
      album: j['al'] is String ? j['al'] as String : '',
      durationSeconds: n(j['d']),
      relativePath: j['p'] is String ? j['p'] as String : null,
      sizeBytes: j['sz'] is num ? (j['sz'] as num).toInt() : null,
      favorite: j['fav'] == true,
      plays: n(j['pl']),
      skips: n(j['sk']),
      lastPlayed: lp is num ? DateTime.fromMillisecondsSinceEpoch(lp.toInt() * 1000) : null,
      edited: j['ed'] == true,
      trackNumber: j['tn'] is num ? (j['tn'] as num).toInt() : null,
    );
  }
}

class BackupPlaylist {
  const BackupPlaylist(this.name, this.songIndexes);

  final String name;

  /// Positions in [BackupData.songs], in the playlist's order.
  final List<int> songIndexes;
}

class BackupLyric {
  const BackupLyric({
    required this.trackKey,
    required this.plain,
    required this.synced,
    required this.instrumental,
    required this.source,
  });

  final String trackKey;
  final String plain;
  final String synced;
  final bool instrumental;
  final String source;
}

/// A cover picture: one per album, found again by artist and album.
class BackupArt {
  const BackupArt({required this.artist, required this.album, required this.bytes, this.ext = 'jpg'});

  final String artist;
  final String album;
  final Uint8List bytes;

  /// `jpg` or `png`.
  final String ext;

  String get key => '${backupNorm(artist)}|${backupNorm(album)}';
}

/// Everything a backup file holds. No audio, no secrets.
class BackupData {
  BackupData({
    required this.created,
    this.root = '',
    this.songs = const [],
    this.playlists = const [],
    this.leftOutRelative = const [],
    this.leftOutAbsolute = const [],
    this.lyrics = const [],
    this.settings = const {},
    this.art = const [],
  });

  static const format = 2;
  static const appName = 'RemoteTunes';

  final DateTime created;

  /// The folder the songs' relative paths are below, on the phone it came from.
  final String root;
  final List<BackupSong> songs;
  final List<BackupPlaylist> playlists;

  /// Folders and files left out of the library: below the root, or elsewhere.
  final List<String> leftOutRelative;
  final List<String> leftOutAbsolute;
  final List<BackupLyric> lyrics;
  final Map<String, String> settings;

  /// Cover pictures (when the backup was made with them).
  final List<BackupArt> art;

  int get edited => songs.where((s) => s.edited).length;
  int get favorites => songs.where((s) => s.favorite).length;
  int get withCounts => songs.where((s) => s.plays > 0 || s.skips > 0).length;
  int get leftOut => leftOutRelative.length + leftOutAbsolute.length;

  Map<String, dynamic> toJson() => {
        'app': appName,
        'format': format,
        'created': created.toUtc().toIso8601String(),
        'root': root,
        'songs': [for (final s in songs) s.toJson()],
        'playlists': [
          for (final p in playlists) {'name': p.name, 'songs': p.songIndexes},
        ],
        'leftOutRel': leftOutRelative,
        'leftOutAbs': leftOutAbsolute,
        'lyrics': [
          for (final l in lyrics)
            {
              'k': l.trackKey,
              if (l.plain.isNotEmpty) 'p': l.plain,
              if (l.synced.isNotEmpty) 's': l.synced,
              if (l.instrumental) 'i': true,
              if (l.source.isNotEmpty) 'src': l.source,
            },
        ],
        'settings': settings,
        'art': [
          for (var i = 0; i < art.length; i++)
            {'artist': art[i].artist, 'album': art[i].album, 'f': 'art/$i.${art[i].ext}'},
        ],
      };

  /// The file's bytes: a zip with `backup.json` and the cover pictures.
  Uint8List encode() {
    final archive = Archive();
    final json = utf8.encode(jsonEncode(toJson()));
    archive.addFile(ArchiveFile('backup.json', json.length, json));
    for (var i = 0; i < art.length; i++) {
      archive.addFile(ArchiveFile('art/$i.${art[i].ext}', art[i].bytes.length, art[i].bytes));
    }
    return Uint8List.fromList(ZipEncoder().encode(archive));
  }

  /// Reads a backup file. Throws a [BackupException] with a plain sentence when it is not one.
  static BackupData decode(List<int> bytes) {
    // Small files are checked before they are unpacked (nobody backs up 200 MB of metadata).
    if (bytes.isEmpty) throw const BackupException('That file is empty.');
    if (bytes.length > 100 * 1024 * 1024) throw const BackupException('That file is too big to be a backup.');
    final String text;
    final images = <String, Uint8List>{};
    try {
      if (bytes.length > 4 && bytes[0] == 0x50 && bytes[1] == 0x4b) {
        // A zip: the JSON and the pictures.
        final archive = ZipDecoder().decodeBytes(bytes);
        List<int>? json;
        for (final f in archive) {
          if (!f.isFile) continue;
          if (f.name == 'backup.json') {
            json = f.content;
          } else if (f.name.startsWith('art/')) {
            images[f.name] = Uint8List.fromList(f.content);
          }
        }
        if (json == null) throw const BackupException('That is not a RemoteTunes backup.');
        text = utf8.decode(json);
      } else {
        final raw = (bytes.length > 2 && bytes[0] == 0x1f && bytes[1] == 0x8b)
            ? gzip.decode(bytes)
            : bytes;
        text = utf8.decode(raw);
      }
    } on BackupException {
      rethrow;
    } catch (_) {
      throw const BackupException('That is not a RemoteTunes backup.');
    }
    final Object? j;
    try {
      j = jsonDecode(text);
    } catch (_) {
      throw const BackupException('That is not a RemoteTunes backup.');
    }
    if (j is! Map || j['app'] != appName) {
      throw const BackupException('That is not a RemoteTunes backup.');
    }
    final f = j['format'];
    if (f is! num || f.toInt() > format) {
      throw const BackupException(
          'That backup was made by a newer version of RemoteTunes. Update the app first.');
    }
    final songs = <BackupSong>[];
    // Bad entries are skipped; the position of the others must not move.
    final indexMap = <int, int>{};
    final rawSongs = j['songs'];
    if (rawSongs is List) {
      for (var i = 0; i < rawSongs.length; i++) {
        final s = BackupSong.fromJson(rawSongs[i]);
        if (s != null) {
          indexMap[i] = songs.length;
          songs.add(s);
        }
      }
    }
    final playlists = <BackupPlaylist>[];
    final rawLists = j['playlists'];
    if (rawLists is List) {
      for (final p in rawLists) {
        if (p is! Map || p['name'] is! String || (p['name'] as String).trim().isEmpty) continue;
        final idx = <int>[];
        final rs = p['songs'];
        if (rs is List) {
          for (final i in rs) {
            final m = i is num ? indexMap[i.toInt()] : null;
            if (m != null) idx.add(m);
          }
        }
        playlists.add(BackupPlaylist((p['name'] as String).trim(), idx));
      }
    }
    List<String> strings(Object? v) =>
        v is List ? [for (final e in v) if (e is String && e.isNotEmpty) e] : const [];
    final lyrics = <BackupLyric>[];
    final rawLyrics = j['lyrics'];
    if (rawLyrics is List) {
      for (final l in rawLyrics) {
        if (l is! Map || l['k'] is! String) continue;
        lyrics.add(BackupLyric(
          trackKey: l['k'] as String,
          plain: l['p'] is String ? l['p'] as String : '',
          synced: l['s'] is String ? l['s'] as String : '',
          instrumental: l['i'] == true,
          source: l['src'] is String ? l['src'] as String : '',
        ));
      }
    }
    final settings = <String, String>{};
    final rawSettings = j['settings'];
    if (rawSettings is Map) {
      rawSettings.forEach((k, v) {
        if (k is String && v is String) settings[k] = v;
      });
    }
    final art = <BackupArt>[];
    final rawArt = j['art'];
    if (rawArt is List) {
      for (final a in rawArt) {
        if (a is! Map || a['f'] is! String) continue;
        final bytes = images[a['f'] as String];
        if (bytes == null || bytes.isEmpty) continue;
        final name = a['f'] as String;
        art.add(BackupArt(
          artist: a['artist'] is String ? a['artist'] as String : '',
          album: a['album'] is String ? a['album'] as String : '',
          bytes: bytes,
          ext: name.toLowerCase().endsWith('.png') ? 'png' : 'jpg',
        ));
      }
    }
    DateTime created;
    try {
      created = DateTime.parse(j['created'] as String).toLocal();
    } catch (_) {
      created = DateTime.fromMillisecondsSinceEpoch(0);
    }
    return BackupData(
      created: created,
      root: j['root'] is String ? j['root'] as String : '',
      songs: songs,
      playlists: playlists,
      leftOutRelative: strings(j['leftOutRel']),
      leftOutAbsolute: strings(j['leftOutAbs']),
      lyrics: lyrics,
      settings: settings,
      art: art,
    );
  }
}
