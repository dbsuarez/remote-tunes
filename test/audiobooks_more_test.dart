import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/data/repositories/settings_repository.dart';
import 'package:remote_tunes/features/backup/backup_models.dart';
import 'package:remote_tunes/features/backup/backup_service.dart';
import 'package:remote_tunes/features/library/import_service.dart' show MemoryExclusionStore;
import 'package:remote_tunes/features/music/music_browser.dart';
import 'package:remote_tunes/features/player/audiobook_tracker.dart';
import 'package:remote_tunes/features/player/queue/playable_song.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';

import 'helpers/fake_audio_backend.dart';
import 'music_widgets_test.dart' show FakeMusicSource, host, settleUi;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late LibraryRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
  });
  tearDown(() => db.close());

  Future<int> add(String title, {String artist = 'Author', String album = 'Dune', int dur = 1000, String? path}) =>
      repo.addSong(title: title, artist: artist, album: album, filePath: path ?? '/m/$title.mp3', durationSeconds: dur);

  group('how far a book is listened to', () {
    test('a chapter in percent; finished is 100; not started is not listed', () async {
      final a = await add('C1');
      final b = await add('C2');
      final c = await add('C3');
      await repo.setAudiobook([a, b, c], true);
      await repo.saveAudiobookPosition(a, 250);
      await repo.saveAudiobookPosition(b, 0, finished: true);
      expect(await repo.audiobookProgress([a, b, c]), {a: 25, b: 100});
    });

    test('a place after finishing means it is being listened to again', () async {
      final a = await add('C1');
      await repo.setAudiobook([a], true);
      await repo.saveAudiobookPosition(a, 0, finished: true);
      await repo.saveAudiobookPosition(a, 100);
      expect(await repo.audiobookProgress([a]), {a: 10});
    });

    test('a book in percent: finished chapters count whole, the others by where they were left', () async {
      final a = await add('C1');
      final b = await add('C2');
      final c = await add('C3');
      final d = await add('C4');
      await repo.setAudiobook([a, b, c, d], true);
      await repo.saveAudiobookPosition(a, 0, finished: true);
      await repo.saveAudiobookPosition(b, 500);
      expect(await repo.bookProgress(['Dune']), {'Dune': 38}, reason: '(1000 + 500) of 4000');
      final books = await repo.groups(kind: GroupKind.audiobook);
      expect(books.items.single.percent, 38);
      expect(books.items.single.songCount, 4);
    });

    test('it travels with the song and with the book entry', () {
      final j = const RemoteSong(id: 1, title: 't', artist: 'a', album: 'b', audiobook: true, progress: 40).toJson();
      expect(RemoteSong.fromJson(j).progress, 40);
      expect(const RemoteSong(id: 1, title: 't', artist: 'a', album: 'b').toJson().containsKey('progress'), isFalse);
      final g = const RemoteGroup(name: 'Dune', songCount: 4, percent: 38).toJson();
      expect(RemoteGroup.fromJson(g).percent, 38);
    });
  });

  group('book rows', () {
    Future<void> open(WidgetTester tester, FakeMusicSource source) async {
      tester.view.physicalSize = const Size(500, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(MusicBrowser(source: source)));
      await settleUi(tester);
    }

    testWidgets('a chapter that was started shows its percent and a progress bar', (tester) async {
      await open(
        tester,
        FakeMusicSource(songs: [
          const RemoteSong(id: 1, title: 'Ch 1', artist: 'Author', album: 'Dune', audiobook: true, progress: 40),
          const RemoteSong(id: 2, title: 'Ch 2', artist: 'Author', album: 'Dune', audiobook: true, progress: 100),
          const RemoteSong(id: 3, title: 'Ch 3', artist: 'Author', album: 'Dune', audiobook: true),
        ]),
      );
      expect(find.textContaining('40%'), findsOneWidget);
      expect(find.textContaining('finished'), findsOneWidget);
      expect(find.byKey(const Key('book-progress')), findsNWidgets(2));
      expect(tester.widget<LinearProgressIndicator>(find.byKey(const Key('book-progress')).first).value, 0.4);
    });

    testWidgets('the list of books shows chapters and how far', (tester) async {
      final source = FakeMusicSource(songs: []);
      source.groupsByKind[GroupKind.audiobook] = const [
        RemoteGroup(name: 'Dune', songCount: 12, percent: 34),
        RemoteGroup(name: 'Emma', songCount: 1),
        RemoteGroup(name: 'Old', songCount: 3, percent: 100),
      ];
      tester.view.physicalSize = const Size(500, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(host(MusicBrowser(
        source: source,
        homeList: true,
      )));
      await settleUi(tester);
      await tester.tap(find.text('Audiobooks'));
      await settleUi(tester);
      expect(find.text('12 chapters · 34%'), findsOneWidget);
      expect(find.text('1 chapter'), findsOneWidget);
      expect(find.text('3 chapters · finished'), findsOneWidget);
    });
  });

  group('a speed for each book', () {
    late FakeAudioBackend backend;
    late QueuePlaybackEngine engine;
    late AudiobookTracker tracker;
    late int music;
    late int bookA1;
    late int bookA2;
    late int bookB1;

    PlayableSong track(int id, String artist, String album) => PlayableSong(
          id: id,
          title: 'T$id',
          artist: artist,
          album: album,
          filePath: '/m/$id.mp3',
          durationSeconds: 1000,
        );

    setUp(() async {
      music = await add('Song', artist: 'Ann', album: 'Alpha');
      bookA1 = await add('A1', album: 'Dune');
      bookA2 = await add('A2', album: 'Dune');
      bookB1 = await add('B1', album: 'Emma');
      await repo.setAudiobook([bookA1, bookA2, bookB1], true);
      tracker = AudiobookTracker(repo);
      await tracker.load();
      backend = FakeAudioBackend();
      engine = QueuePlaybackEngine(backend: backend, fileExists: (_) => true, audiobooks: tracker);
    });
    tearDown(() => engine.dispose());

    Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 30));
    PlayableSong m() => track(music, 'Ann', 'Alpha');
    PlayableSong a1() => track(bookA1, 'Author', 'Dune');
    PlayableSong a2() => track(bookA2, 'Author', 'Dune');
    PlayableSong b1() => track(bookB1, 'Author', 'Emma');

    test('the speed set in a book is kept for the whole book, and music gets its own back', () async {
      await engine.playSongs([m()]);
      await settle();
      await engine.setSpeed(1.25); // music
      await engine.playSongs([a1(), a2()]);
      await settle();
      expect(backend.speed, 1.25, reason: 'a book with no speed plays at the speed music had');
      await engine.setSpeed(1.75);
      await settle();
      expect(await repo.bookSpeed(bookA2), 1.75, reason: 'kept for the whole book, every chapter');
      await engine.playSongs([m()]);
      await settle();
      expect(backend.speed, 1.25, reason: 'music has its speed back');
      await engine.playSongs([a2()]);
      await settle();
      expect(backend.speed, 1.75);
    });

    test('another book keeps its own speed', () async {
      await engine.playSongs([a1()]);
      await settle();
      await engine.setSpeed(1.5);
      await engine.playSongs([b1()]);
      await settle();
      expect(backend.speed, 1.0, reason: 'Emma has none: the speed music had');
      await engine.setSpeed(0.8);
      await engine.playSongs([a1()]);
      await settle();
      expect(backend.speed, 1.5);
    });

    test('with "remember" off nothing is kept', () async {
      final off = AudiobookTracker(repo, enabled: () => false);
      await off.load();
      final e = QueuePlaybackEngine(backend: backend, fileExists: (_) => true, audiobooks: off);
      addTearDown(e.dispose);
      await e.playSongs([a1()]);
      await settle();
      await e.setSpeed(1.5);
      await settle();
      expect(await repo.bookSpeed(bookA1), isNull);
    });
  });

  group('in the backup', () {
    BackupService service(AppDatabase d) => BackupService(
        db: d, settings: SettingsRepository(d), exclusions: MemoryExclusionStore(), copiedSongsDir: '/app/library');

    Future<BackupData> oldPhone() async {
      final other = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(other.close);
      final r = LibraryRepository(other);
      final a = await r.addSong(title: 'Ch 1', artist: 'Author', album: 'Dune', filePath: '/old/books/1.mp3', durationSeconds: 1000);
      final b = await r.addSong(title: 'Ch 2', artist: 'Author', album: 'Dune', filePath: '/old/books/2.mp3', durationSeconds: 1000);
      await r.addSong(title: 'Music', artist: 'Ann', album: 'Alpha', filePath: '/old/m.mp3', durationSeconds: 100);
      await r.setAudiobook([a, b], true);
      await r.saveAudiobookPosition(a, 0, finished: true);
      await r.saveAudiobookPosition(b, 420);
      await r.setBookSpeed(a, 1.5);
      return service(other).create();
    }

    test('the books are in the file with their place, finished flag and speed', () async {
      final data = await oldPhone();
      expect(data.books, hasLength(2));
      final back = BackupData.decode(data.encode());
      final ch2 = back.books.firstWhere((b) => back.songs[b.songIndex].title == 'Ch 2');
      expect((ch2.positionSeconds, ch2.finished, ch2.speed), (420, false, 1.5));
      final ch1 = back.books.firstWhere((b) => back.songs[b.songIndex].title == 'Ch 1');
      expect(ch1.finished, isTrue);
      expect(back.songs.where((s) => s.title == 'Music'), isEmpty, reason: 'music with nothing to keep is not in');
    });

    test('a restore marks them again, with the place, and keeps a place already here', () async {
      final data = await oldPhone();
      final a = await repo.addSong(title: 'Ch 1', artist: 'Author', album: 'Dune', filePath: '/new/1.mp3', durationSeconds: 1000);
      final b = await repo.addSong(title: 'Ch 2', artist: 'Author', album: 'Dune', filePath: '/new/2.mp3', durationSeconds: 1000);
      await repo.setAudiobook([b], true);
      await repo.saveAudiobookPosition(b, 77);
      final report = await service(db).restore(data);
      expect(report.booksRestored, 2);
      expect(await repo.audiobookIds(), {a, b});
      expect(await repo.audiobookProgress([a]), {a: 100});
      expect(await repo.audiobookPosition(b), 77, reason: 'what was listened to here stays');
      expect(await repo.bookSpeed(a), 1.5);
      await service(db).restore(data);
      expect(await repo.audiobookIds(), {a, b}, reason: 'again: nothing twice');
    });

    test('not in the backup when the activity switch is off', () async {
      final other = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(other.close);
      final r = LibraryRepository(other);
      final a = await r.addSong(title: 'Ch', artist: 'A', album: 'B', filePath: '/x.mp3', durationSeconds: 100);
      await r.setAudiobook([a], true);
      expect((await service(other).create(activity: false)).books, isEmpty);
    });

    test('damaged entries are skipped, odd values kept in range', () {
      final data = BackupData(created: DateTime(2026), songs: [
        BackupSong(title: 'A', artist: '', album: '', durationSeconds: 1),
      ], books: const [
        BackupBook(0, 10),
      ]);
      final json = data.toJson();
      json['books'] = <Object?>[
        for (final e in json['books'] as List) List<Object?>.from(e as List),
        ['x', 1, 0],
        [9, 5, 0],
        [0, 99999999, 0, 9.0],
      ];
      final back = BackupData.decode(_bytes(json));
      expect(back.books, hasLength(2));
      expect(back.books.last.speed, 2.0);
      expect(back.books.last.positionSeconds, 86400 * 7);
    });
  });
}

List<int> _bytes(Object json) => utf8.encode(jsonEncode(json));
