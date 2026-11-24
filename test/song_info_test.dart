import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/music/music_browser.dart';
import 'package:remote_tunes/features/music/song_info_dialog.dart';

import 'music_widgets_test.dart' show FakeMusicSource, host, settleUi, song;

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('saving new details', () {
    late AppDatabase db;
    late LibraryRepository repo;
    late int id;

    setUp(() async {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LibraryRepository(db);
      id = await repo.addSong(
          title: 'old', artist: 'Ann', album: 'Alpha', filePath: '/m/a.mp3', trackNumber: 3);
    });
    tearDown(() => db.close());

    test('the song is listed with the new details; the file path is untouched', () async {
      expect(
          await repo.updateSongInfo(id,
              title: '  New title ', artist: 'Bob', album: 'Beta', trackNumber: 7),
          isTrue);
      final s = (await repo.songById(id))!;
      expect([s.title, s.artist, s.album, s.trackNumber], ['New title', 'Bob', 'Beta', 7]);
      expect(s.filePath, '/m/a.mp3');
    });

    test('an empty title is refused and nothing changes', () async {
      expect(await repo.updateSongInfo(id, title: '   ', artist: 'x', album: 'y'), isFalse);
      expect((await repo.songById(id))!.title, 'old');
    });

    test('an empty artist or album becomes "Unknown"', () async {
      await repo.updateSongInfo(id, title: 't', artist: '', album: ' ');
      final s = (await repo.songById(id))!;
      expect([s.artist, s.album], ['Unknown artist', 'Unknown album']);
    });

    test('a silly track number is dropped; long text is cut', () async {
      await repo.updateSongInfo(id, title: 'x' * 500, artist: 'a', album: 'b', trackNumber: -4);
      final s = (await repo.songById(id))!;
      expect(s.trackNumber, isNull);
      expect(s.title.length, LibraryRepository.maxTagLength);
      await repo.updateSongInfo(id, title: 't', artist: 'a', album: 'b', trackNumber: 99999);
      expect((await repo.songById(id))!.trackNumber, isNull);
    });

    test('a song that is gone gives false', () async {
      expect(await repo.updateSongInfo(9999, title: 't', artist: 'a', album: 'b'), isFalse);
    });
  });

  group('the Edit info menu item', () {
    late FakeMusicSource source;

    setUp(() => source = FakeMusicSource(songs: [song(1, 'Old title')]));

    Future<void> openMenu(WidgetTester tester) async {
      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle();
    }

    testWidgets('is not offered on the Controller (no edit callback)', (tester) async {
      await tester.pumpWidget(host(MusicBrowser(source: source)));
      await settleUi(tester);
      await openMenu(tester);
      expect(find.text('Edit info'), findsNothing);
    });

    testWidgets('editing sends the new details', (tester) async {
      SongInfoEdit? sent;
      await tester.pumpWidget(host(MusicBrowser(
        source: source,
        onEditSong: (s, e) async {
          sent = e;
          return true;
        },
      )));
      await settleUi(tester);
      await openMenu(tester);
      await tester.tap(find.text('Edit info'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextField, 'Old title'), findsOneWidget);
      await tester.enterText(find.widgetWithText(TextField, 'Old title'), 'Fixed title');
      await tester.enterText(find.widgetWithText(TextField, 'Track number'), '5');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(sent?.title, 'Fixed title');
      expect(sent?.trackNumber, 5);
      expect(find.text('Saved'), findsOneWidget);
    });

    testWidgets('an empty title cannot be saved', (tester) async {
      var called = false;
      await tester.pumpWidget(host(MusicBrowser(
        source: source,
        onEditSong: (s, e) async {
          called = true;
          return true;
        },
      )));
      await settleUi(tester);
      await openMenu(tester);
      await tester.tap(find.text('Edit info'));
      await tester.pumpAndSettle();
      await tester.enterText(find.widgetWithText(TextField, 'Old title'), '');
      await tester.pump();
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Save')).onPressed,
          isNull);
      expect(called, isFalse);
    });

    testWidgets('cancelling changes nothing', (tester) async {
      var called = false;
      await tester.pumpWidget(host(MusicBrowser(
        source: source,
        onEditSong: (s, e) async {
          called = true;
          return true;
        },
      )));
      await settleUi(tester);
      await openMenu(tester);
      await tester.tap(find.text('Edit info'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(called, isFalse);
    });
  });
}
