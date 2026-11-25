import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import 'cloud_models.dart';
import 'r2_client.dart';

/// A song waiting to go up: its tags, how to read its file, and its cover.
class CloudUpload {
  const CloudUpload({
    required this.title,
    required this.open,
    required this.length,
    this.artist = '',
    this.album = '',
    this.genre = '',
    this.year,
    this.track,
    this.durationSeconds = 0,
    this.ext = 'mp3',
    this.art,
    this.artExt = 'jpg',
  });

  final String title;
  final String artist;
  final String album;
  final String genre;
  final int? year;
  final int? track;
  final int durationSeconds;

  /// Reads the file (called when it is uploaded).
  final Stream<List<int>> Function() open;
  final int length;
  final String ext;
  final Uint8List? art;
  final String artExt;
}

/// What an upload did.
class CloudUploadResult {
  final uploaded = <CloudSong>[];
  final failed = <String>[];
  int bytes = 0;

  /// MusicBrainz-style stop: the keys were refused or the connection is gone (what went up is kept).
  String? stoppedBecause;
}

typedef CloudProgress = void Function(int done, int total, String? current);

/// The personal Cloud Library: songs in one R2 bucket and a catalog file listing them. Anyone with the
/// public address can read the catalog and play; only the keys can write.
class CloudLibraryService {
  CloudLibraryService(
    this.config, {
    http.Client? client,
    R2Client? r2,
    String Function()? newId,
    DateTime Function()? now,
  })  : _client = client ?? http.Client(),
        _r2 = r2 ?? R2Client(config, client: client, now: now),
        _newId = newId ?? (() => const Uuid().v4()),
        _now = now ?? DateTime.now;

  final CloudConfig config;
  final http.Client _client;
  final R2Client _r2;
  final String Function() _newId;
  final DateTime Function() _now;

  static const _contentTypes = {
    'mp3': 'audio/mpeg',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
    'flac': 'audio/flac',
    'ogg': 'audio/ogg',
    'opus': 'audio/ogg',
    'wav': 'audio/wav',
  };

  static String _cleanExt(String ext) {
    final e = ext.toLowerCase().replaceAll('.', '');
    return RegExp(r'^[a-z0-9]{1,5}$').hasMatch(e) ? e : 'mp3';
  }

  /// The catalog as anyone can read it (the public address, no keys). Empty if there is none yet.
  Future<CloudCatalog> fetchCatalog() async {
    if (!config.canRead) throw const R2Exception('Set the public address of your bucket first.');
    try {
      final uri = Uri.parse('${config.urlFor(CloudCatalog.fileName)}?t=${_now().millisecondsSinceEpoch}');
      final res = await _client.get(uri).timeout(const Duration(seconds: 20));
      if (res.statusCode == 404) return const CloudCatalog();
      if (res.statusCode != 200) {
        throw R2Exception('The Cloud Library did not answer (error ${res.statusCode}). Check the public address.', status: res.statusCode);
      }
      return CloudCatalog.fromJson(jsonDecode(utf8.decode(res.bodyBytes)));
    } on R2Exception {
      rethrow;
    } catch (_) {
      throw const R2Exception('No internet connection, or the public address is wrong.');
    }
  }

  /// The catalog read with the keys (always the newest, before it is changed).
  Future<CloudCatalog> _fresh() async {
    final bytes = await _r2.get(CloudCatalog.fileName);
    if (bytes == null) return const CloudCatalog();
    try {
      return CloudCatalog.fromJson(jsonDecode(utf8.decode(bytes)));
    } catch (_) {
      return const CloudCatalog();
    }
  }

  Future<void> _save(CloudCatalog c) => _r2.putBytes(
        CloudCatalog.fileName,
        utf8.encode(jsonEncode(c.toJson())),
        contentType: 'application/json',
        cacheControl: 'no-cache',
      );

  /// Checks the keys (and the bucket) by reading the catalog with them. Returns how many songs it holds.
  Future<int> testKeys() async => (await _fresh()).songs.length;

  /// A name for a cover that every song of the same album shares.
  static String artKeyFor(String artist, String album, String ext) {
    var h = 0x811c9dc5;
    for (final u in '${artist.toLowerCase().trim()}|${album.toLowerCase().trim()}'.codeUnits) {
      h = ((h ^ u) * 0x01000193) & 0x7fffffff;
    }
    return 'artwork/${h.toRadixString(16).padLeft(8, '0')}.${ext == 'png' ? 'png' : 'jpg'}';
  }

  /// Uploads [items] one at a time and adds them to the catalog (saved every ten songs and at the
  /// end, so a stop loses nothing that went up). A song that fails is listed; the keys being refused
  /// or the connection going stops everything. [cancelled] is asked before each song.
  Future<CloudUploadResult> upload(
    List<CloudUpload> items, {
    CloudProgress? onProgress,
    bool Function()? cancelled,
  }) async {
    final result = CloudUploadResult();
    if (!config.canWrite) {
      result.stoppedBecause = 'Add your R2 keys in Settings first.';
      return result;
    }
    final pending = <CloudSong>[];
    final artDone = <String>{};
    CloudCatalog? known;

    Future<void> flush() async {
      if (pending.isEmpty) return;
      final fresh = await _fresh();
      await _save(fresh.changed(add: pending));
      pending.clear();
    }

    try {
      known = await _fresh();
      artDone.addAll([for (final s in known.songs) if (s.artKey != null) s.artKey!]);
      for (var i = 0; i < items.length; i++) {
        if (cancelled?.call() ?? false) break;
        final it = items[i];
        onProgress?.call(i, items.length, it.title);
        try {
          final id = _newId();
          final ext = _cleanExt(it.ext);
          final audioKey = 'songs/$id.$ext';
          await _r2.putStream(audioKey, it.open(), it.length, contentType: _contentTypes[ext] ?? 'application/octet-stream');
          String? artKey;
          final art = it.art;
          if (art != null && art.isNotEmpty) {
            artKey = artKeyFor(it.artist, it.album, it.artExt);
            if (artDone.add(artKey)) {
              try {
                await _r2.putBytes(artKey, art, contentType: artKey.endsWith('.png') ? 'image/png' : 'image/jpeg');
              } on R2Exception catch (e) {
                if (e.refused) rethrow;
                artKey = null; // a cover that fails is just left off
                artDone.remove(artKeyFor(it.artist, it.album, it.artExt));
              }
            }
          }
          final song = CloudSong(
            id: id,
            title: it.title,
            artist: it.artist,
            album: it.album,
            genre: it.genre,
            year: it.year,
            track: it.track,
            durationSeconds: it.durationSeconds,
            audioKey: audioKey,
            artKey: artKey,
            sizeBytes: it.length,
            added: _now(),
          );
          pending.add(song);
          result.uploaded.add(song);
          result.bytes += it.length;
          if (pending.length >= 10) await flush();
        } on R2Exception catch (e) {
          if (e.refused || e.status == 0) {
            result.stoppedBecause = e.message;
            break;
          }
          result.failed.add('${it.title}: ${e.message}');
        } catch (_) {
          result.failed.add('${it.title}: the file could not be read.');
        }
      }
    } on R2Exception catch (e) {
      result.stoppedBecause = e.message;
    }
    try {
      await flush();
    } on R2Exception catch (e) {
      result.stoppedBecause ??= '${e.message} The songs went up but are not in the catalog yet; upload again to list them.';
    }
    onProgress?.call(items.length, items.length, null);
    return result;
  }

  /// Takes songs out of the cloud: out of the catalog first, then their files (a cover only when no
  /// other song uses it).
  Future<int> remove(Iterable<CloudSong> songs) async {
    final list = songs.toList();
    if (list.isEmpty) return 0;
    final fresh = await _fresh();
    final gone = {for (final s in list) s.id};
    final after = fresh.changed(remove: gone);
    await _save(after);
    final stillArt = {for (final s in after.songs) if (s.artKey != null) s.artKey!};
    for (final s in list) {
      try {
        await _r2.delete(s.audioKey);
        final art = s.artKey;
        if (art != null && !stillArt.contains(art)) await _r2.delete(art);
      } on R2Exception {
        // The song is already out of the catalog; a file left behind is only wasted space.
      }
    }
    return list.length;
  }
}
