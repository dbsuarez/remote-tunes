import 'dart:convert';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remote_tunes/core/lyrics/lrc.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/music/lyrics_view.dart';
import 'package:remote_tunes/features/player/lyrics_service.dart';

const _lrc = '''
[ar:Someone]
[ti:A song]
[offset:0]
[00:12.50] First line
[00:20.00]Second line
[00:05.1][01:00.00]Chorus
[01:30]Last
''';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('reading LRC', () {
    test('lines come back in time order with their words', () {
      final l = parseLrc(_lrc);
      expect(l.map((e) => e.text), ['Chorus', 'First line', 'Second line', 'Chorus', 'Last']);
      expect(l.map((e) => e.ms), [5100, 12500, 20000, 60000, 90000]);
    });

    test('fractions are read as fractions of a second', () {
      expect(parseLrc('[00:01.5] a').single.ms, 1500);
      expect(parseLrc('[00:01.05] a').single.ms, 1050);
      expect(parseLrc('[00:01.123] a').single.ms, 1123);
      expect(parseLrc('[00:01] a').single.ms, 1000);
    });

    test('the offset tag moves every time', () {
      final l = parseLrc('[offset:+500]\n[00:10.00] a');
      expect(l.single.ms, 10500);
      expect(parseLrc('[offset:-2000]\n[00:01.00] a').single.ms, 0);
    });

    test('tags with no time, blank text and Windows line ends are fine', () {
      final l = parseLrc('[ti:x]\r\n[00:01.00]\r\n[00:02.00] hi\r\njunk line');
      expect(l.map((e) => e.text), ['', 'hi']);
    });

    test('nothing readable gives an empty list', () {
      expect(parseLrc(''), isEmpty);
      expect(parseLrc('just words\nno times'), isEmpty);
    });

    test('finding the line being sung', () {
      final l = parseLrc('[00:10.00] a\n[00:20.00] b\n[00:30.00] c');
      expect(currentLyricLine(l, 0), -1);
      expect(currentLyricLine(l, 9999), -1);
      expect(currentLyricLine(l, 10000), 0);
      expect(currentLyricLine(l, 25000), 1);
      expect(currentLyricLine(l, 999999), 2);
      expect(currentLyricLine(const [], 1000), -1);
    });
  });

  group('the lyrics service', () {
    late AppDatabase db;
    late LibraryRepository repo;
    late int songId;
    late List<Uri> asked;
    late DateTime now;
    var enabled = true;

    LyricsService make(http.Response Function(Uri) answer) => LyricsService(
          library: repo,
          db: db,
          client: MockClient((r) async {
            asked.add(r.url);
            return answer(r.url);
          }),
          isEnabled: () async => enabled,
          now: () => now,
        );

    http.Response json(Object body, [int status = 200]) =>
        http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json; charset=utf-8'});

    setUp(() async {
      enabled = true;
      asked = [];
      now = DateTime(2026, 11, 24);
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = LibraryRepository(db);
      songId = await repo.addSong(
        title: 'A Song',
        artist: 'The Band',
        album: 'The Album',
        filePath: '/private/music/a.mp3',
        durationSeconds: 215,
      );
    });

    tearDown(() => db.close());

    test('synced lyrics come from LRCLIB with only title, artist, album and length', () async {
      final svc = make((u) => json({'syncedLyrics': _lrc, 'plainLyrics': 'plain'}));
      final l = await svc.forSong(songId);
      expect(l.found, isTrue);
      expect(l.synced, contains('First line'));
      expect(l.source, 'LRCLIB');
      final u = asked.single;
      expect(u.host, 'lrclib.net');
      expect(u.path, '/api/get');
      expect(u.queryParameters, {
        'track_name': 'A Song',
        'artist_name': 'The Band',
        'album_name': 'The Album',
        'duration': '215',
      });
      expect(u.toString(), isNot(contains('private')), reason: 'no file names leave the phone');
    });

    test('a second look is answered from the Player, without the internet', () async {
      final svc = make((u) => json({'plainLyrics': 'hello'}));
      await svc.forSong(songId);
      final again = await svc.forSong(songId);
      expect(again.plain, 'hello');
      expect(asked, hasLength(1));
    });

    test('lyrics are looked up again after 30 days', () async {
      final svc = make((u) => json({'plainLyrics': 'hello'}));
      await svc.forSong(songId);
      now = now.add(const Duration(days: 31));
      await svc.forSong(songId);
      expect(asked, hasLength(2));
    });

    test('when LRCLIB has no exact match, its search is tried', () async {
      final svc = make((u) => u.path == '/api/get'
          ? json({'message': 'not found'}, 404)
          : json([
              {'plainLyrics': 'only plain'},
              {'syncedLyrics': _lrc, 'plainLyrics': 'p'},
            ]));
      final l = await svc.forSong(songId);
      expect(l.synced, isNotEmpty, reason: 'a synced result is preferred');
      expect(asked.map((u) => u.path), ['/api/get', '/api/search']);
    });

    test('then lyrics.ovh gives plain text', () async {
      final svc = make((u) => switch (u.host) {
            'lrclib.net' => json({}, 404),
            _ => json({'lyrics': 'words from ovh'}),
          });
      final l = await svc.forSong(songId);
      expect(l.plain, 'words from ovh');
      expect(l.synced, isEmpty);
      expect(l.source, 'lyrics.ovh');
    });

    test('nothing anywhere: not found, and remembered for a day', () async {
      final svc = make((u) => json({}, 404));
      final l = await svc.forSong(songId);
      expect(l.found, isFalse);
      expect(l.failed, isFalse);
      final count = asked.length;
      await svc.forSong(songId);
      expect(asked.length, count, reason: 'the miss is remembered');
      now = now.add(const Duration(days: 2));
      await svc.forSong(songId);
      expect(asked.length, greaterThan(count), reason: 'tried again a day later');
    });

    test('no internet: reported, and not remembered as "no lyrics"', () async {
      final svc = LyricsService(
        library: repo,
        db: db,
        client: MockClient((_) async => throw http.ClientException('offline')),
        now: () => now,
      );
      final l = await svc.forSong(songId);
      expect(l.failed, isTrue);
      expect(l.found, isFalse);
      // A working connection afterwards does find them.
      final ok = make((u) => json({'plainLyrics': 'back online'}));
      expect((await ok.forSong(songId)).plain, 'back online');
    });

    test('a server error is not remembered either', () async {
      final svc = make((u) => http.Response('oops', 500));
      expect((await svc.forSong(songId)).failed, isTrue);
    });

    test('switched off: nothing is sent anywhere', () async {
      enabled = false;
      final svc = make((u) => json({'plainLyrics': 'x'}));
      final l = await svc.forSong(songId);
      expect(l.disabled, isTrue);
      expect(asked, isEmpty);
    });

    test('an instrumental song says so', () async {
      final svc = make((u) => json({'instrumental': true}));
      final l = await svc.forSong(songId);
      expect(l.found, isTrue);
      expect(l.instrumental, isTrue);
      expect(l.hasText, isFalse);
    });

    test('an unknown artist is not sent as a name', () async {
      final id = await repo.addSong(
          title: 'Mystery', artist: 'Unknown artist', album: 'Unknown album', filePath: '/m/x.mp3');
      final svc = make((u) => json({}, 404));
      await svc.forSong(id);
      for (final u in asked) {
        expect(u.queryParameters.containsKey('artist_name'), isFalse);
        expect(u.toString().toLowerCase(), isNot(contains('unknown')));
      }
      expect(asked.every((u) => u.host == 'lrclib.net'), isTrue,
          reason: 'lyrics.ovh needs an artist, so it is skipped');
    });

    test('a song that is not in the library gives nothing', () async {
      final svc = make((u) => json({'plainLyrics': 'x'}));
      expect((await svc.forSong(9999)).found, isFalse);
      expect(asked, isEmpty);
    });

    test('two asks at the same time share one lookup', () async {
      final svc = make((u) => json({'plainLyrics': 'x'}));
      await Future.wait([svc.forSong(songId), svc.forSong(songId)]);
      expect(asked, hasLength(1));
    });
  });

  group('the lyrics panel', () {
    Widget host(
      Future<RemoteLyrics> Function(int) fetch, {
      int position = 0,
      int? songId = 5,
      ValueChanged<int>? onSeek,
    }) =>
        MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(
            body: SingleChildScrollView(
              child: LyricsSection(
                songId: songId,
                positionSeconds: position,
                isPlaying: false,
                fetch: fetch,
                onSeek: onSeek,
              ),
            ),
          ),
        );

    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.text('Lyrics'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('closed until asked: nothing is fetched', (tester) async {
      final asked = <int>[];
      await tester.pumpWidget(host((id) async {
        asked.add(id);
        return const RemoteLyrics();
      }));
      expect(find.text('Lyrics'), findsOneWidget);
      expect(asked, isEmpty);
    });

    testWidgets('no button for a song without a library id (internet tracks)', (tester) async {
      await tester.pumpWidget(host((id) async => const RemoteLyrics(), songId: null));
      expect(find.text('Lyrics'), findsNothing);
      await tester.pumpWidget(host((id) async => const RemoteLyrics(), songId: -1));
      expect(find.text('Lyrics'), findsNothing);
    });

    testWidgets('synced lyrics show with the current line first', (tester) async {
      await tester.pumpWidget(host(
          (id) async => const RemoteLyrics(found: true, synced: _lrc, source: 'LRCLIB'),
          position: 13));
      await open(tester);
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('First line'), findsOneWidget);
      expect(find.text('Lyrics: LRCLIB'), findsOneWidget, reason: 'credit is shown');
    });

    testWidgets('tapping a line jumps the song there', (tester) async {
      final seeks = <int>[];
      await tester.pumpWidget(host(
          (id) async => const RemoteLyrics(found: true, synced: _lrc),
          onSeek: seeks.add));
      await open(tester);
      await tester.tap(find.text('Second line'));
      expect(seeks, [20]);
    });

    testWidgets('plain lyrics are just shown', (tester) async {
      await tester.pumpWidget(host(
          (id) async => const RemoteLyrics(found: true, plain: 'La la la\nHey hey')));
      await open(tester);
      expect(find.textContaining('La la la'), findsOneWidget);
    });

    testWidgets('not found, switched off, offline and a failing Player all say so',
        (tester) async {
      await tester.pumpWidget(host((id) async => const RemoteLyrics()));
      await open(tester);
      expect(find.text('No lyrics found for this song.'), findsOneWidget);

      await tester.pumpWidget(host((id) async => const RemoteLyrics(disabled: true), songId: 6));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('switched off'), findsOneWidget);

      await tester.pumpWidget(host((id) async => const RemoteLyrics(failed: true), songId: 7));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining("Couldn't reach"), findsOneWidget);
      expect(find.text('Try again'), findsOneWidget);

      await tester.pumpWidget(host((id) async => throw StateError('x'), songId: 8));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining("Couldn't get the lyrics"), findsOneWidget);
    });

    testWidgets('a new song loads its own lyrics', (tester) async {
      final asked = <int>[];
      Future<RemoteLyrics> fetch(int id) async {
        asked.add(id);
        return RemoteLyrics(found: true, plain: 'words of $id');
      }

      await tester.pumpWidget(host(fetch, songId: 1));
      await open(tester);
      expect(find.text('words of 1'), findsOneWidget);
      await tester.pumpWidget(host(fetch, songId: 2));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('words of 2'), findsOneWidget);
      expect(asked, [1, 2]);
    });

    test('lyrics survive the trip through the protocol', () {
      const l = RemoteLyrics(
          found: true, plain: 'p', synced: 's', instrumental: true, source: 'LRCLIB');
      final back = RemoteLyrics.fromJson(jsonDecode(jsonEncode(l.toJson())) as Map<String, dynamic>);
      expect(back.found, isTrue);
      expect(back.plain, 'p');
      expect(back.synced, 's');
      expect(back.instrumental, isTrue);
      expect(back.source, 'LRCLIB');
    });
  });
}
