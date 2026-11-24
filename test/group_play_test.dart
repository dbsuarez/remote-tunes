import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/protocol/protocol.dart';
import 'package:remote_tunes/core/transport/local_websocket_transport.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
import 'package:remote_tunes/features/group/clock_sync.dart';
import 'package:remote_tunes/features/group/group_audio_cache.dart';
import 'package:remote_tunes/features/group/group_follower_service.dart';
import 'package:remote_tunes/features/group/group_models.dart';
import 'package:remote_tunes/features/group/group_native.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';
import 'package:remote_tunes/features/player/server/player_library.dart';
import 'package:remote_tunes/features/player/server/player_server.dart';

import 'helpers/fake_audio_backend.dart';

Future<void> waitFor(bool Function() c,
    {String? reason, Duration timeout = const Duration(seconds: 8)}) async {
  final end = DateTime.now().add(timeout);
  while (!c()) {
    if (DateTime.now().isAfter(end)) fail('Timed out: $reason');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class _MemNudge implements NudgeStore {
  final byRoute = <String, int>{};
  int get value => byRoute['speaker'] ?? 0;
  set value(int v) => byRoute['speaker'] = v;
  @override
  Future<int> load(String route) async => byRoute[route] ?? 0;
  @override
  Future<void> save(String route, int ms) async => byRoute[route] = ms;
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late Directory tmp;
  late AppDatabase db;
  late LibraryRepository repo;
  late FakeAudioBackend playerBackend;
  late QueuePlaybackEngine engine;
  late PlayerServer server;
  late ControllerClient client;
  final ids = <String, int>{};
  final bytesOf = <String, Uint8List>{};

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('rt_group_');
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
    for (final name in ['One', 'Two']) {
      // Not real audio: the Player never decodes it here, it only serves it.
      final data = Uint8List.fromList(List.generate(70000, (i) => (i * 7 + name.length) % 256));
      final f = File('${tmp.path}/$name.mp3')..writeAsBytesSync(data);
      bytesOf[name] = data;
      ids[name] = await repo.addSong(
          title: name, artist: 'A', album: 'B', filePath: f.path, durationSeconds: 100);
    }
    playerBackend = FakeAudioBackend();
    engine = QueuePlaybackEngine(backend: playerBackend, fileExists: (_) => true);
    server = PlayerServer(
      engine: engine,
      deviceName: 'P',
      port: 0,
      bindAddress: InternetAddress.loopbackIPv4,
      library: RepositoryPlayerLibrary(repo),
    );
    await server.start();
    client = ControllerClient(
      transportFactory: (h, p) => LocalWebSocketTransport(host: h, port: p),
      heartbeatInterval: const Duration(milliseconds: 200),
    );
    await client.connect(
        host: '127.0.0.1', port: server.current.port!, deviceName: 'Phone');
    final code = server.current.pending!.code;
    server.acceptPairing();
    await client.submitCode(code);
    await waitFor(() => client.current.isConnected, reason: 'paired');
  });

  tearDown(() async {
    await client.dispose();
    await server.stop();
    await engine.dispose();
    await db.close();
    await tmp.delete(recursive: true);
  });

  Future<void> playOne({int positionMs = 12345}) async {
    final songs = await repo.songsByIds([ids['One']!, ids['Two']!]);
    await engine.playSongs([for (final s in songs) s.toPlayable()!]);
    playerBackend.position = Duration(milliseconds: positionMs);
  }

  group('the clock probe', () {
    test('the Player answers with its clock, and the offset is about zero in one process',
        () async {
      final sync = ClockSync();
      for (var i = 0; i < 12; i++) {
        final p = await client.syncProbe();
        expect(p.t1, lessThanOrEqualTo(p.t2));
        expect(p.t3, greaterThanOrEqualTo(p.t0));
        sync.add(p.t0, p.t1, p.t2, p.t3);
      }
      // Both "phones" here share one clock, so the true offset is 0.
      expect(sync.offsetMs!.abs(), lessThan(5));
      expect(sync.rttMs!, lessThan(50));
    });

    test('probes need a paired session', () async {
      final stranger = ControllerClient(
        transportFactory: (h, p) => LocalWebSocketTransport(host: h, port: p),
      );
      await stranger.connect(
          host: '127.0.0.1', port: server.current.port!, deviceName: 'X');
      await expectLater(stranger.syncProbe(), throwsA(isA<ControllerException>()));
      await stranger.dispose();
    });
  });

  group('what the Player says while a Controller has joined', () {
    test('nothing is sent until it joins', () async {
      final got = <RemoteMessage>[];
      final sub = client.groupMessages.listen(got.add);
      await playOne();
      await client.sendCommand('pause');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(got, isEmpty);
      await sub.cancel();
    });

    test('once joined: song, exact position, clock stamp and next song', () async {
      await playOne(positionMs: 12345);
      final got = <GroupSync>[];
      final sub = client.groupMessages
          .listen((m) => got.add(GroupSync.fromPayload(m.payload)!));
      await client.setGroupJoin(true);
      await waitFor(() => got.isNotEmpty, reason: 'a group_sync');
      final m = got.first;
      expect(m.songId, ids['One']);
      expect(m.positionMs, 12345, reason: 'the live position, not a whole second');
      expect(m.playing, isTrue);
      expect(m.speed, 1.0);
      expect(m.nextSongId, ids['Two']);
      expect(m.atMs, greaterThan(0));
      await sub.cancel();
    });

    test('it follows what the Player does (pause, speed, other song)', () async {
      await playOne();
      final got = <GroupSync>[];
      final sub = client.groupMessages
          .listen((m) => got.add(GroupSync.fromPayload(m.payload)!));
      await client.setGroupJoin(true);
      await waitFor(() => got.isNotEmpty);

      got.clear();
      await client.sendCommand('pause');
      await waitFor(() => got.any((m) => !m.playing), reason: 'paused update');

      got.clear();
      await client.setSpeed(1.5);
      await waitFor(() => got.any((m) => m.speed == 1.5), reason: 'speed update');

      got.clear();
      await client.sendCommand('next');
      await waitFor(() => got.any((m) => m.songId == ids['Two']), reason: 'next song');
      await sub.cancel();
    });

    test('with nothing playing no song id is sent', () async {
      final got = <GroupSync>[];
      final sub = client.groupMessages
          .listen((m) => got.add(GroupSync.fromPayload(m.payload)!));
      await client.setGroupJoin(true);
      await waitFor(() => got.isNotEmpty);
      expect(got.first.songId, isNull);
      expect(got.first.playing, isFalse);
      await sub.cancel();
    });

    test('leaving stops the messages', () async {
      await playOne();
      final got = <RemoteMessage>[];
      final sub = client.groupMessages.listen(got.add);
      await client.setGroupJoin(true);
      await waitFor(() => got.isNotEmpty);
      await client.setGroupJoin(false);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      got.clear();
      await client.sendCommand('pause');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(got, isEmpty);
      await sub.cancel();
    });
  });

  group('downloading the song for the other phone', () {
    Future<({int status, List<int> body, Map<String, String> headers})> get(
        Uri uri, Map<String, String> headers) async {
      final c = HttpClient();
      try {
        final req = await c.getUrl(uri);
        headers.forEach(req.headers.set);
        final res = await req.close();
        final body = <int>[];
        await for (final chunk in res) {
          body.addAll(chunk);
        }
        final h = <String, String>{};
        res.headers.forEach((k, v) => h[k] = v.join(','));
        return (status: res.statusCode, body: body, headers: h);
      } finally {
        c.close(force: true);
      }
    }

    test('a joined Controller gets the exact file, with its checksum', () async {
      await client.setGroupJoin(true);
      final req = client.groupAudioRequest(ids['One']!)!;
      expect(req.uri.path, '/group/audio/${ids['One']}');
      final r = await get(req.uri, req.headers);
      expect(r.status, 200);
      expect(r.body, bytesOf['One']);
      expect(r.headers['x-rt-sha256'], sha256.convert(bytesOf['One']!).toString());
      expect(r.headers['x-rt-ext'], 'mp3');
      expect(r.headers['content-type'], 'audio/mpeg');
    });

    test('not allowed before joining, or with a wrong token', () async {
      final req = client.groupAudioRequest(ids['One']!)!;
      expect((await get(req.uri, req.headers)).status, 403, reason: 'not joined yet');
      await client.setGroupJoin(true);
      expect((await get(req.uri, {...req.headers, 'x-rt-token': 'wrong'})).status, 403);
      expect((await get(req.uri, {...req.headers, 'x-rt-session': 'nope'})).status, 403);
      expect((await get(req.uri, const {})).status, 403);
      expect((await get(req.uri, req.headers)).status, 200);
    });

    test('not allowed again after leaving', () async {
      final req = client.groupAudioRequest(ids['One']!)!;
      await client.setGroupJoin(true);
      expect((await get(req.uri, req.headers)).status, 200);
      await client.setGroupJoin(false);
      expect((await get(req.uri, req.headers)).status, 403);
    });

    test('only library songs can be asked for', () async {
      await client.setGroupJoin(true);
      final base = client.groupAudioRequest(ids['One']!)!;
      Uri at(String path) => base.uri.replace(path: path);
      expect((await get(at('/group/audio/999999'), base.headers)).status, 404);
      expect((await get(at('/group/audio/abc'), base.headers)).status, 404);
      expect((await get(at('/group/audio/-1'), base.headers)).status, 404);
      // A song whose file is gone.
      File('${tmp.path}/Two.mp3').deleteSync();
      expect((await get(at('/group/audio/${ids['Two']}'), base.headers)).status, 404);
    });

    test('the request is only offered over the local network', () async {
      // (Connected locally here, so it is offered; a lost connection is not.)
      expect(client.groupAudioRequest(ids['One']!), isNotNull);
      await client.disconnect();
      expect(client.groupAudioRequest(ids['One']!), isNull);
    });
  });

  group('the follower service end to end', () {
    late FakeAudioBackend follower;
    late GroupFollowerService service;
    late Directory cacheDir;
    late _MemNudge nudges;

    setUp(() {
      follower = FakeAudioBackend();
      nudges = _MemNudge();
      cacheDir = Directory('${tmp.path}/cache');
      service = GroupFollowerService(
        client: client,
        makeBackend: () => follower,
        audio: GroupAudioCache(
          requestFor: client.groupAudioRequest,
          folder: () async => cacheDir,
        ),
        nudges: nudges,
        native: const NoGroupNative(),
        resyncEvery: const Duration(seconds: 30),
      );
    });

    tearDown(() async => service.dispose());

    test('joins, fetches the song and starts it where the Player is', () async {
      await playOne(positionMs: 12345);
      await service.join();
      await waitFor(() => follower.playing, reason: 'follower playing');

      expect(follower.loaded.single, startsWith(cacheDir.path));
      expect(File(follower.loaded.single).readAsBytesSync(), bytesOf['One'],
          reason: 'the very same file, checked');
      // Started near the Player's position (a little later: it took a moment).
      expect(follower.position.inMilliseconds, inInclusiveRange(12345, 12345 + 2500));
      expect(service.status.phase, GroupPhase.playing);
      expect(service.status.offsetMs!.abs(), lessThan(10));
      expect(service.status.rttMs, isNotNull);
    });

    test('follows the Player pausing, and resumes', () async {
      await playOne();
      await service.join();
      await waitFor(() => follower.playing);
      await client.sendCommand('pause');
      await waitFor(() => !follower.playing, reason: 'follower paused');
      expect(service.status.message, contains('Paused'));
      await client.sendCommand('play');
      await waitFor(() => follower.playing, reason: 'follower resumed');
    });

    test('a new song on the Player starts on this phone too', () async {
      await playOne();
      await service.join();
      await waitFor(() => follower.playing);
      await client.sendCommand('next');
      await waitFor(() => follower.loaded.length == 2, reason: 'second song loaded');
      expect(File(follower.loaded.last).readAsBytesSync(), bytesOf['Two']);
    });

    test('the next song is fetched ahead of time', () async {
      await playOne();
      await service.join();
      await waitFor(() => follower.playing);
      await waitFor(
          () => cacheDir.existsSync() &&
              cacheDir.listSync().where((e) => e.path.endsWith('${ids['Two']}.mp3')).isNotEmpty,
          reason: 'second song already here');
    });

    test('leaving silences it, deletes the downloads and cuts off access', () async {
      await playOne();
      await service.join();
      await waitFor(() => follower.playing);
      final req = client.groupAudioRequest(ids['One']!)!;
      await service.leave();
      expect(follower.playing, isFalse);
      expect(service.status.phase, GroupPhase.off);
      expect(cacheDir.existsSync(), isFalse, reason: 'downloads are deleted');
      final c = HttpClient();
      final r = await (await c.getUrl(req.uri)
            ..headers.set('x-rt-session', req.headers['x-rt-session']!)
            ..headers.set('x-rt-token', req.headers['x-rt-token']!))
          .close();
      expect(r.statusCode, 403);
      c.close(force: true);
    });

    test('the fine-tune is saved on this phone and applied', () async {
      await playOne();
      await service.setNudgeMs(80);
      expect(nudges.value, 80);
      await service.setNudgeMs(9999);
      expect(nudges.value, 300, reason: 'kept within +/-300 ms');
      await service.setNudgeMs(-40);
      await service.join();
      await waitFor(() => follower.playing);
      expect(service.status.nudgeMs, -40);
    });

    test('cannot join when not connected', () async {
      await client.disconnect();
      await expectLater(service.join(), throwsA(isA<ControllerException>()));
      expect(service.status.phase, GroupPhase.off);
    });

    test('a song whose file vanished never crashes it', () async {
      await playOne();
      File('${tmp.path}/One.mp3').deleteSync();
      await service.join();
      await waitFor(() => service.status.phase == GroupPhase.problem || follower.playing,
          reason: 'a result');
      if (service.status.phase == GroupPhase.problem) {
        expect(service.status.message, isNotEmpty);
      }
    });

    test('status updates are published', () async {
      final seen = <GroupPhase>[];
      final sub = service.statusStream.listen((s) => seen.add(s.phase));
      await playOne();
      await service.join();
      await waitFor(() => follower.playing);
      await sub.cancel();
      expect(seen, contains(GroupPhase.syncing));
      expect(seen, contains(GroupPhase.playing));
    });
  });

  test('the sync message is plain JSON the other side can read back', () {
    final payload = {
      'songId': 7,
      'positionMs': 1500,
      'atMs': 123456.789,
      'playing': true,
      'speed': 1.25,
      'durationMs': 200000,
      'nextSongId': 8,
    };
    final m = GroupSync.fromPayload(jsonDecode(jsonEncode(payload)) as Map<String, dynamic>)!;
    expect(m.songId, 7);
    expect(m.positionMs, 1500);
    expect(m.atMs, closeTo(123456.789, 1e-6));
    expect(m.speed, 1.25);
    expect(m.nextSongId, 8);
    expect(GroupSync.fromPayload({'songId': 7}), isNull, reason: 'no position, no use');
    expect(GroupSync.fromPayload({'positionMs': 1, 'atMs': 2, 'speed': 99})!.speed, 2.0);
  });
}
