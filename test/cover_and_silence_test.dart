import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/features/ambience/ambience_banner.dart';
import 'package:remote_tunes/features/library/cover_picker.dart';
import 'package:remote_tunes/features/library/lookup_models.dart';
import 'package:remote_tunes/features/library/tag_writer.dart';
import 'package:remote_tunes/features/music/song_info_dialog.dart';
import 'package:remote_tunes/features/player/queue/playable_song.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';
import 'package:remote_tunes/features/player/silence_finder.dart';

import 'helpers/fake_audio_backend.dart';

Uint8List jpeg(int r, [int side = 40]) => img.encodeJpg(img.fill(img.Image(width: side, height: side), color: img.ColorRgb8(r, 20, 20)));

void main() {
  group('writing a cover into a music file', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('rt_cover'));
    tearDown(() => dir.deleteSync(recursive: true));

    String copyOf(String name) => File(p.join('test', 'fixtures', name)).copySync(p.join(dir.path, name)).path;

    for (final name in ['tone.mp3', 'tone.m4a', 'tone.flac']) {
      test('$name takes it, keeps its words and length, and takes another in its place', () {
        final path = copyOf(name);
        final before = readMetadata(File(path), getImage: true);
        expect(before.pictures, isEmpty);
        final first = jpeg(200);
        expect(const TagWriter().writeCover(path, first), TagWriteResult.written);
        final second = jpeg(60, 80);
        expect(const TagWriter().writeCover(path, second), TagWriteResult.written);
        final after = readMetadata(File(path), getImage: true);
        expect(after.pictures, hasLength(1));
        expect(after.pictures.single.bytes, second);
        expect((after.title, after.artist, after.album), ('Tone', 'Tester', 'Fixtures'));
        expect(after.duration?.inSeconds, before.duration?.inSeconds);
        expect(dir.listSync(), hasLength(1), reason: 'no leftover copy');
      });
    }

    for (final name in ['rich.mp3', 'rich.m4a', 'rich.flac']) {
      test('$name keeps every other tag, and its music, through a cover and new words', () {
        final path = copyOf(name);
        final original = File(path).readAsBytesSync();
        final seconds = readMetadata(File(path), getImage: false).duration?.inSeconds;
        String raw() => latin1.decode(File(path).readAsBytesSync(), allowInvalid: true);
        const others = ['la la lyrics', 'My note', 'The Band', 'A Composer', 'My right'];
        for (final word in others) {
          expect(latin1.decode(original), contains(word), reason: 'in the fixture');
        }
        expect(const TagWriter().writeCover(path, jpeg(5)), TagWriteResult.written);
        expect(const TagWriter().write(path, title: 'Neue Tön', artist: 'Someone', album: 'Else', trackNumber: 7),
            TagWriteResult.written);
        expect(const TagWriter().writeGroup(path, {'genre': 'Jazz', 'year': 1999}), TagWriteResult.written);
        final text = raw();
        for (final word in others) {
          expect(text, contains(word), reason: '$name lost it');
        }
        if (name != 'rich.m4a') expect(text, contains('-6.5 dB'), reason: 'loudness value');
        final after = readMetadata(File(path), getImage: true);
        expect((after.title, after.album, after.trackNumber), ('Neue Tön', 'Else', 7));
        expect(text, contains('Someone'), reason: 'the new artist');
        expect(text, isNot(contains('Tester')), reason: 'in place of the old one');
        expect(const TagWriter().writeGroup(path, {'artist': 'Another'}), TagWriteResult.written);
        expect(after.year?.year, 1999);
        expect(after.pictures.single.bytes, jpeg(5));
        expect(after.duration?.inSeconds, seconds);
        // The end of the file (the music of MP3 and FLAC) is as it was.
        if (name != 'rich.m4a') {
          final now = File(path).readAsBytesSync();
          expect(now.sublist(now.length - 2000), original.sublist(original.length - 2000));
        }
      });
    }

    test('taking a field away works, and a file that cannot be changed safely is left alone', () {
      final path = copyOf('rich.mp3');
      expect(const TagWriter().writeGroup(path, {'composer': null}), TagWriteResult.written);
      expect(latin1.decode(File(path).readAsBytesSync(), allowInvalid: true), isNot(contains('A Composer')));
      // An unsynchronised tag is not touched.
      final bytes = File(path).readAsBytesSync()..[5] = 0x80;
      File(path).writeAsBytesSync(bytes);
      expect(const TagWriter().writeCover(path, jpeg(5)), TagWriteResult.unsupported);
      expect(File(path).readAsBytesSync(), bytes);
      expect(dir.listSync(), hasLength(1));
    });

    test('what cannot take one is left exactly as it was', () {
      final other = File(p.join(dir.path, 'x.ogg'))..writeAsBytesSync(List.filled(500, 7));
      expect(const TagWriter().writeCover(other.path, jpeg(1)), isNot(TagWriteResult.written));
      expect(other.readAsBytesSync(), List.filled(500, 7));
      expect(dir.listSync(), hasLength(1));
      expect(const TagWriter().writeCover(p.join(dir.path, 'gone.mp3'), jpeg(1)), TagWriteResult.missing);
    });

    test('the message says what happened', () {
      expect(TagWriter.coverMessage([TagWriteResult.written]), 'Cover written into the music file');
      expect(TagWriter.coverMessage([TagWriteResult.written, TagWriteResult.written]), 'Cover written into 2 music files');
      expect(TagWriter.coverMessage([TagWriteResult.written, TagWriteResult.notAllowed]), contains('1 of 2'));
      expect(TagWriter.coverMessage([TagWriteResult.unsupported]), contains('RemoteTunes only'));
    });
  });

  group('cutting the picture square', () {
    testWidgets('a wide photo gives a square JPEG, never larger than needed', (tester) async {
      await tester.runAsync(() async {
        for (final (w, h, side) in [(1600, 1000, 800), (300, 200, 200)]) {
          final recorder = ui.PictureRecorder();
          Canvas(recorder).drawRect(Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()), Paint()..color = Colors.green);
          final photo = await recorder.endRecording().toImage(w, h);
          final out = img.decodeJpg(await renderCover(photo, const BannerFraming(aspect: 1)))!;
          expect((out.width, out.height), (side, side));
          expect(out.getPixel(side ~/ 2, side ~/ 2).g, greaterThan(100));
          photo.dispose();
        }
      });
    });

    test('a square frame stays square while it is moved and zoomed', () {
      const framing = BannerFraming(aspect: 1);
      final moved = framing.moved(const Size(1600, 1000), 400, const Offset(50, 0), zoom: 2);
      expect(moved.aspect, 1);
      final part = moved.partOf(const Size(1600, 1000));
      expect(part.width, closeTo(part.height, 0.001));
    });
  });

  group('Edit info', () {
    const song = RemoteSong(id: 1, title: 'Alpha', artist: 'Ann', album: 'First', durationSeconds: 100);

    Future<List<SongInfoEdit?>> open(WidgetTester tester, {bool pick = true}) async {
      final answers = <SongInfoEdit?>[];
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => answers.add(await showSongInfoDialog(context, song,
                canWriteFile: true, pickCover: pick ? (_) async => LookupCover(jpeg(9), 'jpg') : null)),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      return answers;
    }

    testWidgets('a chosen picture is shown, says where it goes, and is given back', (tester) async {
      final answers = await open(tester);
      await tester.tap(find.byKey(const Key('choose-cover')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cover-preview')), findsOneWidget);
      expect(find.text('Save puts this picture on every song of this album, and into the music files.'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Album'), '');
      await tester.pump();
      expect(find.text('Save puts this picture on this song, and into the music file.'), findsOneWidget);
      await tester.tap(find.text('Also write into the music file'));
      await tester.pump();
      expect(find.text('Save puts this picture on this song.'), findsOneWidget);
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(answers.single!.cover!.ext, 'jpg');
    });

    testWidgets('it can be taken back before saving; without a picker there is no button', (tester) async {
      final answers = await open(tester);
      await tester.tap(find.byKey(const Key('choose-cover')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cover-clear')));
      await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(answers.single!.cover, isNull);
      await open(tester, pick: false);
      expect(find.byKey(const Key('choose-cover')), findsNothing);
    });
  });

  group('skipping a silent end', () {
    late FakeAudioBackend backend;
    late QueuePlaybackEngine engine;
    final ends = <String, SoundEnd?>{};

    PlayableSong song(int id) =>
        PlayableSong(id: id, title: 'S$id', artist: 'A', album: 'B', filePath: '/m/$id.mp3', durationSeconds: 200);

    setUp(() {
      ends
        ..clear()
        ..['/m/1.mp3'] = (endMs: 150000, durationMs: 200000) // 50 s of silence
        ..['/m/2.mp3'] = (endMs: 197000, durationMs: 200000); // 3 s: kept
      backend = FakeAudioBackend();
      engine = QueuePlaybackEngine(backend: backend, fileExists: (_) => true, soundEnd: (path) async => ends[path]);
    });
    tearDown(() => engine.dispose());

    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));

    Future<void> at(int ms) async {
      backend.emitPosition(Duration(milliseconds: ms));
      await settle();
    }

    Future<void> start({bool skip = true}) async {
      await engine.setSkipSilence(skip);
      await engine.playSongs([song(1), song(2), song(3)]);
      await settle();
    }

    test('moves on a second after the sound stops, and counts the song as finished', () async {
      await start();
      await at(150500);
      expect(engine.state.title, 'S1');
      await at(151000);
      expect(engine.state.title, 'S2');
      expect(engine.state.isPlaying, isTrue);
    });

    test('a short silence, an unknown end, or the switch off: the song plays out', () async {
      await start();
      await at(151200);
      await at(198500);
      expect(engine.state.title, 'S2', reason: '3 seconds is not long');
      await engine.next();
      await settle();
      await at(199000);
      expect(engine.state.title, 'S3', reason: 'nothing known about it');
      await engine.dispose();
      backend = FakeAudioBackend();
      engine = QueuePlaybackEngine(backend: backend, fileExists: (_) => true, soundEnd: (path) async => ends[path]);
      await start(skip: false);
      await at(180000);
      expect(engine.state.title, 'S1');
      // Switched on while playing, it applies at once.
      await engine.setSkipSilence(true);
      await settle();
      await at(180500);
      expect(engine.state.title, 'S2');
    });

    test('does nothing while paused, and repeats one song each time round', () async {
      await start();
      await engine.pause();
      await at(160000);
      expect(engine.state.title, 'S1');
      await engine.setRepeatMode(RepeatMode.one);
      await engine.play();
      await at(160100);
      expect(engine.state.title, 'S1');
      expect(backend.position, Duration.zero, reason: 'from the start again');
      await at(10000);
      await at(152000);
      expect(backend.position, Duration.zero);
    });

    test('crossfade begins where the sound stops', () async {
      backend.canCrossfade = true;
      await engine.setCrossfade(4);
      await start();
      await at(140000);
      expect(backend.crossfades, isEmpty);
      await at(147000);
      expect(backend.crossfades.single.path, '/m/2.mp3');
      expect(backend.crossfadeImmediate.single, isTrue, reason: 'the file itself goes on');
    });
  });
}
