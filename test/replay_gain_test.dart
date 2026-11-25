import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/library/import_service.dart';
import 'package:remote_tunes/features/library/metadata_extractor.dart';
import 'package:remote_tunes/features/player/queue/playable_song.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';

import 'helpers/fake_audio_backend.dart';

PlayableSong song(int id, {double? track, double? album}) => PlayableSong(
      id: id,
      title: 'S$id',
      artist: 'A',
      album: 'B',
      filePath: '/m/$id.mp3',
      durationSeconds: 100,
      replayGainDb: track,
      albumGainDb: album,
    );

class _Extractor implements MetadataExtractor {
  final byName = <String, ExtractedMetadata>{};
  @override
  Future<ExtractedMetadata> extract(String path) async =>
      byName[p.basename(path)] ?? const ExtractedMetadata();
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('reading a Replay Gain tag', () {
    test('the usual forms', () {
      expect(parseReplayGain('-6.54 dB'), -6.54);
      expect(parseReplayGain('+3.2 dB'), 3.2);
      expect(parseReplayGain('-7.00dB'), -7.0);
      expect(parseReplayGain('  -1.5 DB '), -1.5);
      expect(parseReplayGain('0.5'), 0.5);
      expect(parseReplayGain('-4,2 dB'), -4.2, reason: 'a decimal comma');
    });

    test('junk and absurd values are not a gain', () {
      expect(parseReplayGain(null), isNull);
      expect(parseReplayGain(''), isNull);
      expect(parseReplayGain('loud'), isNull);
      expect(parseReplayGain('-99 dB'), isNull);
      expect(parseReplayGain('NaN'), isNull);
      expect(parseReplayGain('1e9'), isNull);
    });
  });

  group('evening out loudness while playing', () {
    late FakeAudioBackend backend;
    late QueuePlaybackEngine engine;

    setUp(() {
      backend = FakeAudioBackend();
      engine = QueuePlaybackEngine(
          backend: backend, fileExists: (_) => true, initialVolume: 0.8);
    });

    tearDown(() => engine.dispose());

    double db(double x) => 0.8 * _pow10(x / 20);

    test('off: the volume is just what was chosen', () async {
      await engine.playSongs([song(1, track: -6)]);
      await settle();
      expect(backend.volume, closeTo(0.8, 1e-9));
    });

    test('by song: a loud song is turned down by its tag', () async {
      await engine.setReplayGainMode(ReplayGainMode.track);
      await engine.playSongs([song(1, track: -6)]);
      await settle();
      expect(backend.volume, closeTo(db(-6), 1e-6));
      expect(engine.state.volume, 0.8, reason: 'the volume shown is still the chosen one');
    });

    test('a song with no tag, or a positive one, is left alone (never turned up)', () async {
      await engine.setReplayGainMode(ReplayGainMode.track);
      await engine.playSongs([song(1), song(2, track: 4)]);
      await settle();
      expect(backend.volume, closeTo(0.8, 1e-9));
      await engine.next();
      await settle();
      expect(backend.volume, closeTo(0.8, 1e-9));
    });

    test('changing the volume keeps the adjustment', () async {
      await engine.setReplayGainMode(ReplayGainMode.track);
      await engine.playSongs([song(1, track: -6)]);
      await settle();
      await engine.setVolume(0.5);
      expect(backend.volume, closeTo(0.5 * _pow10(-6 / 20), 1e-6));
    });

    test('the next song gets its own adjustment, and one without goes back to full', () async {
      await engine.setReplayGainMode(ReplayGainMode.track);
      await engine.playSongs([song(1, track: -6), song(2, track: -3), song(3)]);
      await settle();
      await engine.next();
      await settle();
      expect(backend.volume, closeTo(db(-3), 1e-6));
      await engine.next();
      await settle();
      expect(backend.volume, closeTo(0.8, 1e-9));
    });

    test('a gapless change to the next song applies its tag too', () async {
      await engine.setReplayGainMode(ReplayGainMode.track);
      await engine.playSongs([song(1), song(2, track: -8)]);
      await settle();
      backend.advanceGapless();
      await settle();
      expect(backend.volume, closeTo(db(-8), 1e-6));
    });

    test('by album: the album tag is used, falling back to the song\'s', () async {
      await engine.setReplayGainMode(ReplayGainMode.album);
      await engine.playSongs([song(1, track: -2, album: -9), song(2, track: -4)]);
      await settle();
      expect(backend.volume, closeTo(db(-9), 1e-6));
      await engine.next();
      await settle();
      expect(backend.volume, closeTo(db(-4), 1e-6));
    });

    test('switching it on or off takes effect on the song playing', () async {
      await engine.playSongs([song(1, track: -6)]);
      await settle();
      expect(backend.volume, closeTo(0.8, 1e-9));
      await engine.setReplayGainMode(ReplayGainMode.track);
      expect(backend.volume, closeTo(db(-6), 1e-6));
      await engine.setReplayGainMode(ReplayGainMode.off);
      expect(backend.volume, closeTo(0.8, 1e-9));
    });

    test('internet tracks are never changed', () async {
      await engine.setReplayGainMode(ReplayGainMode.track);
      await engine.playSongs([
        PlayableSong.stream(url: 'https://x/a.mp3', title: 'T', artist: 'A', album: 'B'),
      ]);
      await settle();
      expect(backend.volume, closeTo(0.8, 1e-9));
    });
  });

  group('the tags in the library', () {
    late AppDatabase db;
    late LibraryRepository repo;
    late _Extractor extractor;
    late Directory root;
    late LibraryImportService service;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LibraryRepository(db);
      extractor = _Extractor();
      root = await Directory.systemTemp.createTemp('rt_rg_');
      service = LibraryImportService(
        library: repo,
        extractor: extractor,
        libraryDir: Directory(p.join(root.path, 'library')),
        artDir: Directory(p.join(root.path, 'art')),
      );
    });

    tearDown(() async {
      await db.close();
      await root.delete(recursive: true);
    });

    Future<String> file(String name) async {
      final f = File(p.join(root.path, 'source', name));
      await f.parent.create(recursive: true);
      await f.writeAsBytes(Uint8List.fromList(List.filled(16, 1)));
      return f.path;
    }

    test('new songs keep their gains and play with them', () async {
      final f = await file('a.mp3');
      extractor.byName['a.mp3'] = const ExtractedMetadata(
          title: 'A', artist: 'X', album: 'Y', replayGainDb: -7.5, albumGainDb: -6.0);
      await service.importFiles([f]);
      final s = (await repo.songs()).items.single;
      final dbSong = (await repo.songById(s.id))!;
      expect([dbSong.replayGainDb, dbSong.albumGainDb], [-7.5, -6.0]);
      final playable = dbSong.toPlayable()!;
      expect([playable.replayGainDb, playable.albumGainDb], [-7.5, -6.0]);
    });

    test('old songs get theirs on "Update tags from files"', () async {
      final f = await file('old.mp3');
      final id = await repo.addSong(title: 'T', artist: 'a', album: 'b', filePath: f);
      extractor.byName['old.mp3'] = const ExtractedMetadata(replayGainDb: -3.0);
      expect(await service.refreshTags(), 1);
      expect((await repo.songById(id))!.replayGainDb, -3.0);
    });
  });
}

double _pow10(double x) => math.pow(10, x).toDouble();
