import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart' show sha256;

import 'group_follower_core.dart';

/// How to ask the Player for a song's audio: its address and the headers that
/// prove this Controller joined (the session id and token).
typedef GroupAudioRequest = ({Uri uri, Map<String, String> headers})?;

/// Downloads the playing song from the Player over the local network into a
/// temporary folder on this phone, checks its SHA-256, and keeps only the last
/// few songs. The folder is emptied when group play ends.
///
/// The audio never goes through the internet or any server: it is a direct
/// request from this phone to the Player on the same Wi-Fi.
class GroupAudioCache implements GroupAudioSource {
  GroupAudioCache({
    required this.requestFor,
    required this.folder,
    this.keepSongs = 6,
    this.retryAfter = const Duration(seconds: 5),
    this.timeout = const Duration(minutes: 3),
  });

  final GroupAudioRequest Function(int songId) requestFor;
  final Future<Directory> Function() folder;
  final int keepSongs;
  final Duration retryAfter;
  final Duration timeout;

  final Map<int, String> _ready = {};
  final Map<int, Future<void>> _fetching = {};
  final Map<int, String> _failures = {};
  final Map<int, DateTime> _failedAt = {};
  final Map<int, double> _progress = {};
  final List<int> _order = [];

  /// Bumped by [clear]: downloads that started before it stop quietly.
  int _epoch = 0;

  @override
  String? pathIfReady(int songId) {
    final p = _ready[songId];
    if (p == null) return null;
    if (!File(p).existsSync()) {
      _ready.remove(songId);
      return null;
    }
    return p;
  }

  @override
  String? failureOf(int songId) => _failures[songId];

  @override
  double? progressOf(int songId) => _progress[songId];

  @override
  Future<void> fetch(int songId) {
    if (pathIfReady(songId) != null) return Future.value();
    final running = _fetching[songId];
    if (running != null) return running;
    final failedAt = _failedAt[songId];
    if (failedAt != null && DateTime.now().difference(failedAt) < retryAfter) {
      return Future.value(); // do not hammer the Player after a failure
    }
    final job = _download(songId).whenComplete(() => _fetching.remove(songId));
    _fetching[songId] = job;
    return job;
  }

  Future<void> _download(int songId) async {
    _failures.remove(songId);
    final epoch = _epoch;
    final req = requestFor(songId);
    if (req == null) {
      _fail(songId, 'This phone is not connected to the Player on the local network.');
      return;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    File? part;
    try {
      final dir = await folder();
      if (!dir.existsSync()) dir.createSync(recursive: true);
      final request = await client.getUrl(req.uri);
      req.headers.forEach(request.headers.set);
      final response = await request.close().timeout(const Duration(seconds: 15));
      if (response.statusCode == 403) {
        _fail(songId, 'The Player did not allow this phone to fetch the song.');
        await response.drain<void>();
        return;
      }
      if (response.statusCode == 404) {
        _fail(songId, 'The Player no longer has that song.');
        await response.drain<void>();
        return;
      }
      if (response.statusCode != 200) {
        _fail(songId, 'The Player could not send the song (error ${response.statusCode}).');
        await response.drain<void>();
        return;
      }
      final total = response.contentLength;
      final wantedHash = response.headers.value('x-rt-sha256');
      final extRaw = response.headers.value('x-rt-ext') ?? 'audio';
      final ext = RegExp(r'^[a-z0-9]{1,5}$').hasMatch(extRaw) ? extRaw : 'audio';

      part = File('${dir.path}${Platform.pathSeparator}$songId.part');
      // A plain file handle (not an IOSink): if the folder disappears under it
      // (group play ended), every failure is an ordinary awaited exception.
      final out = await part.open(mode: FileMode.write);
      var got = 0;
      _progress[songId] = 0;
      try {
        await for (final chunk in response.timeout(const Duration(seconds: 20))) {
          if (epoch != _epoch) return; // cleared meanwhile: stop quietly
          await out.writeFrom(chunk);
          got += chunk.length;
          if (total > 0) _progress[songId] = got / total;
        }
      } finally {
        await out.close();
      }
      if (epoch != _epoch) return;
      if (total > 0 && got != total) {
        _fail(songId, 'The song did not arrive completely. Try again.');
        return;
      }
      if (wantedHash != null) {
        final actual = (await sha256.bind(part.openRead()).first).toString();
        if (actual != wantedHash) {
          _fail(songId, 'The song arrived damaged. Try again.');
          return;
        }
      }
      if (epoch != _epoch) return;
      final done = File('${dir.path}${Platform.pathSeparator}$songId.$ext');
      if (done.existsSync()) done.deleteSync();
      part = await part.rename(done.path);
      _ready[songId] = done.path;
      _order.remove(songId);
      _order.add(songId);
      _prune();
      _failedAt.remove(songId);
    } on TimeoutException {
      _fail(songId, 'The Player took too long to send the song.');
    } on SocketException {
      _fail(songId, "Couldn't reach the Player to fetch the song.");
    } on HttpException {
      _fail(songId, "The Player's answer couldn't be read.");
    } on FileSystemException {
      // (Also what happens if the folder was removed because group play ended.)
      if (epoch == _epoch) {
        _fail(songId, "Couldn't save the song on this phone (is the storage full?).");
      }
    } finally {
      _progress.remove(songId);
      client.close(force: true);
      try {
        if (part != null && part.path.endsWith('.part') && part.existsSync()) part.deleteSync();
      } catch (_) {}
    }
  }

  void _fail(int songId, String message) {
    _failures[songId] = message;
    _failedAt[songId] = DateTime.now();
  }

  void _prune() {
    while (_order.length > keepSongs) {
      final old = _order.removeAt(0);
      final p = _ready.remove(old);
      if (p != null) {
        try {
          File(p).deleteSync();
        } catch (_) {}
      }
    }
  }

  /// Deletes everything downloaded (group play ended).
  Future<void> clear() async {
    _epoch++;
    _ready.clear();
    _order.clear();
    _failures.clear();
    _failedAt.clear();
    _progress.clear();
    try {
      final dir = await folder();
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
  }
}
