import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/library/song_lookup.dart';
import 'package:remote_tunes/features/music/song_info_dialog.dart';
import 'package:remote_tunes/features/music/song_lookup_sheet.dart';
import 'package:remote_tunes/features/player/lyrics_service.dart';

final _jpeg = Uint8List.fromList([0xFF, 0xD8, ...List.filled(200, 7)]);
final _png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, ...List.filled(200, 9)]);

const _release1 = '11111111-1111-1111-1111-111111111111';
const _release2 = '22222222-2222-2222-2222-222222222222';

Map<String, dynamic> _recording(String title, String artist, int score, int lengthMs,
        List<Map<String, dynamic>> releases) =>
    {
      'id': 'rec-$title',
      'title': title,
      'score': score,
      'length': lengthMs,
      'artist-credit': [
        {'name': artist}
      ],
      'releases': releases,
    };

Map<String, dynamic> _release(String id, String title, String date, String track) => {
      'id': id,
      'title': title,
      'date': date,
      'media': [
        {
          'track': [
            {'number': track}
          ]
        }
      ],
    };

String _results(List<Map<String, dynamic>> recordings) => jsonEncode({'recordings': recordings});

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late LibraryRepository repo;
  late Directory dir;
  late List<Uri> requests;
  late http.Response Function(Uri) respond;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = LibraryRepository(db);
    dir = Directory.systemTemp.createTempSync('lookup');
    requests = [];
    respond = (u) => http.Response('{}', 404);
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  SongLookup make({Object? failWith}) {
    final client = MockClient((r) async {
      requests.add(r.url);
      if (failWith != null) throw failWith;
      return respond(r.url);
    });
    return SongLookup(
      db: db,
      lyrics: LyricsService(library: repo, db: db, client: client),
      artDir: () async => Directory('${dir.path}/art'),
      client: client,
      gap: Duration.zero,
    );
  }

  group('finding the details', () {
    test('asks MusicBrainz for the recording by title and artist, and reads the matches', () async {
      respond = (u) => http.Response(
          _results([
            _recording('Here Without You', '3 Doors Down', 100, 238000,
                [_release(_release1, 'Away from the Sun', '2002-11-12', '3')]),
          ]),
          200);
      final m = await make().search(title: 'Here Without You', artist: '3 Doors Down');
      expect(m, hasLength(1));
      expect(m.single.title, 'Here Without You');
      expect(m.single.artist, '3 Doors Down');
      expect(m.single.album, 'Away from the Sun');
      expect(m.single.year, 2002);
      expect(m.single.trackNumber, 3);
      expect(m.single.releaseId, _release1);
      expect(m.single.label, contains('Away from the Sun (2002)'));
      final q = requests.single;
      expect(q.host, 'musicbrainz.org');
      expect(q.queryParameters['query'], contains('recording:"Here Without You"'));
      expect(q.queryParameters['query'], contains('artist:"3 Doors Down"'));
      expect(q.queryParameters['fmt'], 'json');
    });

    test('an unknown artist is not searched for, and quotes cannot break the query', () async {
      respond = (u) => http.Response(_results([]), 200);
      await make().search(title: 'Say "Hello"', artist: 'Unknown artist');
      final q = requests.single.queryParameters['query']!;
      expect(q, isNot(contains('artist:')));
      expect(q, isNot(contains('"Hello"')));
    });

    test('the ones of the right length come first, then the album that was named', () async {
      respond = (u) => http.Response(
          _results([
            _recording('Song', 'Band', 100, 400000, [_release(_release1, 'Live Album', '2001', '1')]),
            _recording('Song', 'Band', 90, 200000, [_release(_release2, 'Real Album', '1999', '2')]),
            _recording('Song', 'Band', 95, 200000, [_release(_release1, 'Other Album', '2005', '9')]),
          ]),
          200);
      final m = await make().search(title: 'Song', artist: 'Band', album: 'Real Album', durationSeconds: 201);
      expect(m.first.album, 'Real Album', reason: 'right length, and the album named');
      expect(m[1].album, 'Other Album');
      expect(m.last.album, 'Live Album', reason: 'a different length goes last');
    });

    test('the same match twice is shown once; at most six are offered', () async {
      respond = (u) => http.Response(
          _results([
            for (var i = 0; i < 10; i++)
              _recording('Song $i', 'Band', 100 - i, 200000, [_release(_release1, 'Album $i', '2000', '1')]),
            _recording('Song 0', 'Band', 50, 200000, [_release(_release1, 'Album 0', '2000', '1')]),
          ]),
          200);
      final m = await make().search(title: 'Song', artist: 'Band');
      expect(m, hasLength(6));
      expect(m.where((x) => x.title == 'Song 0'), hasLength(1));
    });

    test('the genre: MusicBrainz own genres first, else the most used tag that is a genre', () async {
      Map<String, dynamic> withTags(Map<String, dynamic> extra) =>
          {..._recording('Song', 'Band', 100, 200000, [_release(_release1, 'Alb', '2000', '1')]), ...extra};
      respond = (u) => http.Response(
          _results([
            withTags({
              'genres': [
                {'name': 'alternative rock', 'count': 3},
                {'name': 'rock', 'count': 9}
              ],
              'tags': [
                {'name': 'seen live', 'count': 50}
              ],
            }),
          ]),
          200);
      expect((await make().search(title: 'Song')).single.genre, 'Rock');
      respond = (u) => http.Response(
          _results([
            withTags({
              'tags': [
                {'name': 'seen live', 'count': 50},
                {'name': 'hip hop', 'count': 4},
                {'name': 'american', 'count': 20},
                {'name': 'rap', 'count': 2},
              ],
            }),
          ]),
          200);
      expect((await make().search(title: 'Song')).single.genre, 'Hip Hop', reason: 'junk tags are skipped');
      respond = (u) => http.Response(_results([withTags({'tags': []})]), 200);
      expect((await make().search(title: 'Song')).single.genre, isNull);
    });

    test('a recording with no release still gives the title and artist', () async {
      respond = (u) => http.Response(_results([_recording('Lone', 'Solo', 80, 100000, [])]), 200);
      final m = await make().search(title: 'Lone');
      expect(m.single.title, 'Lone');
      expect(m.single.album, '');
      expect(m.single.releaseId, isNull);
    });

    test('a silly release id is not trusted', () async {
      respond = (u) => http.Response(
          _results([_recording('X', 'Y', 90, 1000, [_release('../../evil', 'A', '2000', '1')])]), 200);
      expect((await make().search(title: 'X')).single.releaseId, isNull);
    });

    test('nothing found, junk answers and an empty title give an empty list', () async {
      respond = (u) => http.Response(_results([]), 200);
      expect(await make().search(title: 'Nothing'), isEmpty);
      respond = (u) => http.Response('not json', 200);
      expect(await make().search(title: 'Junk'), isEmpty);
      expect(await make().search(title: '   '), isEmpty);
    });

    test('a busy MusicBrainz and a failed connection are explained', () async {
      respond = (u) => http.Response('', 503);
      await expectLater(make().search(title: 'X'), throwsA(isA<LookupException>()));
      await expectLater(make(failWith: const SocketException('down')).search(title: 'X'),
          throwsA(predicate((e) => e is LookupException && e.message.contains('internet'))));
    });
  });

  group('finding the cover', () {
    const match = LookupMatch(title: 't', artist: 'a', album: 'b', releaseId: _release1);

    test('takes the front picture of the album', () async {
      respond = (u) => http.Response.bytes(_jpeg, 200);
      final c = await make().coverFor(match);
      expect(c!.ext, 'jpg');
      expect(c.bytes, _jpeg);
      expect(requests.single.host, 'coverartarchive.org');
      expect(requests.single.path, '/release/$_release1/front-500');
    });

    test('knows a PNG, and refuses what is not a picture, too small, or has no album', () async {
      respond = (u) => http.Response.bytes(_png, 200);
      expect((await make().coverFor(match))!.ext, 'png');
      respond = (u) => http.Response.bytes(Uint8List.fromList(List.filled(300, 1)), 200);
      expect(await make().coverFor(match), isNull);
      respond = (u) => http.Response.bytes(Uint8List.fromList([0xFF, 0xD8, 1]), 200);
      expect(await make().coverFor(match), isNull);
      respond = (u) => http.Response('', 404);
      expect(await make().coverFor(match), isNull);
      expect(await make().coverFor(const LookupMatch(title: 't', artist: 'a', album: 'b')), isNull);
    });

    test('a cover is put on every song of the album, and kept as a file', () async {
      final a = await repo.addSong(title: 'One', artist: 'Ann', album: 'First', filePath: '/m/1.mp3');
      await repo.addSong(title: 'Two', artist: 'Ann', album: 'First', filePath: '/m/2.mp3');
      await repo.addSong(title: 'Other', artist: 'Zed', album: 'Second', filePath: '/m/3.mp3');
      final n = await make().applyCover(a, LookupCover(_jpeg, 'jpg'));
      expect(n, 2);
      final rows = await db.customSelect('SELECT title, album_art_path AS p FROM songs').get();
      final by = {for (final r in rows) r.read<String>('title'): r.readNullable<String>('p')};
      expect(by['One'], isNotNull);
      expect(by['Two'], by['One']);
      expect(by['Other'], isNull);
      expect(File(by['One']!).readAsBytesSync(), _jpeg);
    });
  });

  group('the lyrics', () {
    test('a look-up is made again even when a miss was remembered, and can be forgotten',
        () async {
      final id = await repo.addSong(
          title: 'Song', artist: 'Band', album: 'Alb', filePath: '/m/s.mp3', durationSeconds: 200);
      var lrclib = 0;
      http.Response answer(Uri u) {
        if (u.host == 'lrclib.net') {
          lrclib++;
          return lrclib == 1
              ? http.Response('{}', 404)
              : http.Response(jsonEncode({'syncedLyrics': '[00:01.00] Hello there'}), 200);
        }
        return http.Response('{}', 404);
      }

      respond = answer;
      final lookup = make();
      final first = await lookup.lyrics.forSong(id);
      expect(first.found, isFalse, reason: 'a miss, which is remembered');
      expect((await lookup.lyrics.forSong(id)).found, isFalse, reason: 'from memory');
      final again = await lookup.lyricsFor(id);
      expect(again.found, isTrue, reason: 'asked again on purpose');
      await lookup.discardLyrics(id);
      final rows = await db.customSelect('SELECT COUNT(*) AS c FROM lyrics_cache').getSingle();
      expect(rows.read<int>('c'), 0);
    });
  });

  group('the look-up window', () {
    late _FakeLookup lookup;
    LookupChoice? choice;
    var answered = false;

    setUp(() {
      lookup = _FakeLookup(db, repo, dir);
      choice = null;
      answered = false;
    });

    Future<void> open(WidgetTester tester, {RemoteSong? song}) async {
      tester.view.physicalSize = const Size(500, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              choice = await showSongLookup(context,
                  lookup: lookup,
                  song: song ?? const RemoteSong(id: 5, title: 'Song', artist: 'Band', album: 'Alb'));
              answered = true;
            },
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows the matches, the cover and the lyrics together', (tester) async {
      await open(tester);
      expect(find.text('Look up this song'), findsOneWidget);
      expect(find.text('Details'), findsOneWidget);
      expect(find.byKey(const ValueKey('match-0')), findsOneWidget);
      expect(find.byKey(const ValueKey('match-1')), findsOneWidget);
      expect(find.text('Cover'), findsOneWidget);
      expect(find.byKey(const Key('cover-preview')), findsOneWidget);
      expect(find.textContaining('Found (LRCLIB, timed)'), findsOneWidget);
      expect(find.text('Hello there'), findsOneWidget, reason: 'the first lines, without their times');
    });

    testWidgets('Apply gives the chosen match, the cover and keeps the lyrics', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('lookup-apply')));
      await tester.pumpAndSettle();
      expect(choice!.match!.album, 'Real Album');
      expect(choice!.cover, isNotNull);
      expect(choice!.keepLyrics, isTrue);
      expect(lookup.discarded, isEmpty);
    });

    testWidgets('choosing another match asks for that one\'s cover', (tester) async {
      await open(tester);
      lookup.coverRequests.clear();
      await tester.tap(find.byKey(const ValueKey('match-1')));
      await tester.pumpAndSettle();
      expect(lookup.coverRequests, ['Other Album']);
      await tester.tap(find.byKey(const Key('lookup-apply')));
      await tester.pumpAndSettle();
      expect(choice!.match!.album, 'Other Album');
    });

    testWidgets('each part can be left out', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('use-details')));
      await tester.tap(find.byKey(const Key('use-cover')));
      await tester.tap(find.byKey(const Key('keep-lyrics')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('lookup-apply')));
      await tester.pumpAndSettle();
      expect(choice!.match, isNull);
      expect(choice!.cover, isNull);
      expect(choice!.keepLyrics, isFalse);
      expect(lookup.discarded, [5], reason: 'lyrics that were found but not wanted are forgotten');
    });

    testWidgets('Cancel gives nothing and forgets nothing', (tester) async {
      await open(tester);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(answered, isTrue);
      expect(choice, isNull);
    });

    testWidgets('no matches, no lyrics, no cover: it says so plainly', (tester) async {
      lookup.matches = [];
      lookup.fakeLyrics = const RemoteLyrics();
      await open(tester);
      expect(find.text('No matches found.'), findsOneWidget);
      expect(find.text('No lyrics found.'), findsOneWidget);
      expect(find.text('Cover'), findsNothing);
    });

    testWidgets('a failed look-up and switched-off lyrics are explained', (tester) async {
      lookup.matchError = const LookupException('MusicBrainz is busy. Try again in a moment.');
      lookup.fakeLyrics = const RemoteLyrics(disabled: true);
      await open(tester);
      expect(find.text('MusicBrainz is busy. Try again in a moment.'), findsOneWidget);
      expect(find.textContaining('switched off in Settings'), findsOneWidget);
    });

    testWidgets('a match with no cover says so', (tester) async {
      lookup.cover = null;
      await open(tester);
      expect(find.text('No cover found for this one.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('lookup-apply')));
      await tester.pumpAndSettle();
      expect(choice!.cover, isNull);
    });

    testWidgets('a link (not a library song) gets no lyrics look-up', (tester) async {
      await open(tester, song: const RemoteSong(id: 0, title: 'T', artist: 'A', album: 'B'));
      expect(find.textContaining('looked up for songs in the library'), findsOneWidget);
      expect(lookup.lyricsAsked, isEmpty);
    });
  });

  group('inside Edit info', () {
    late _FakeLookup lookup;
    SongInfoEdit? saved;

    setUp(() {
      lookup = _FakeLookup(db, repo, dir);
      saved = null;
    });

    Future<void> open(WidgetTester tester, {SongLookup? withLookup}) async {
      tester.view.physicalSize = const Size(500, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => saved = await showSongInfoDialog(
                context, const RemoteSong(id: 5, title: 'Song', artist: 'Band', album: 'Alb'),
                canWriteFile: true, lookup: withLookup),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
    }

    testWidgets('has the button only where a look-up is possible', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('look-up')), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('the look-up fills in the fields, and Save carries the cover', (tester) async {
      await open(tester, withLookup: lookup);
      await tester.tap(find.byKey(const Key('look-up')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('lookup-apply')));
      await tester.pumpAndSettle();
      expect(find.textContaining('details filled in · cover ready · lyrics kept'), findsOneWidget);
      expect(tester.widget<TextField>(find.widgetWithText(TextField, 'Real Title')).controller!.text, 'Real Title');
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved!.title, 'Real Title');
      expect(saved!.artist, 'Real Band');
      expect(saved!.album, 'Real Album');
      expect(saved!.trackNumber, 4);
      expect(saved!.cover, isNotNull);
    });

    testWidgets('cancelling the look-up leaves the fields alone', (tester) async {
      await open(tester, withLookup: lookup);
      await tester.tap(find.byKey(const Key('look-up')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(saved!.title, 'Song');
      expect(saved!.cover, isNull);
    });

    testWidgets('the look-up starts from what is typed now, not what was saved', (tester) async {
      await open(tester, withLookup: lookup);
      await tester.enterText(find.widgetWithText(TextField, 'Song'), 'Typed Title');
      await tester.tap(find.byKey(const Key('look-up')));
      await tester.pumpAndSettle();
      expect(lookup.searched.single, 'Typed Title');
    });
  });
}

/// A look-up with ready answers (no network).
class _FakeLookup extends SongLookup {
  _FakeLookup(AppDatabase db, LibraryRepository repo, Directory dir)
      : super(
          db: db,
          lyrics: LyricsService(library: repo, db: db),
          artDir: () async => Directory('${dir.path}/art'),
        );

  List<LookupMatch> matches = const [
    LookupMatch(
        title: 'Real Title',
        artist: 'Real Band',
        album: 'Real Album',
        year: 1999,
        trackNumber: 4,
        releaseId: _release1),
    LookupMatch(title: 'Real Title', artist: 'Real Band', album: 'Other Album', year: 2005, releaseId: _release2),
  ];
  LookupException? matchError;
  LookupCover? cover = LookupCover(_jpeg, 'jpg');
  RemoteLyrics fakeLyrics = const RemoteLyrics(found: true, synced: '[00:01.00] Hello there\n[00:05.00] More', source: 'LRCLIB');
  final searched = <String>[];
  final coverRequests = <String>[];
  final lyricsAsked = <int>[];
  final discarded = <int>[];

  @override
  Future<List<LookupMatch>> search({
    required String title,
    String artist = '',
    String album = '',
    int durationSeconds = 0,
  }) async {
    searched.add(title);
    if (matchError != null) throw matchError!;
    return matches;
  }

  @override
  Future<LookupCover?> coverFor(LookupMatch m) async {
    coverRequests.add(m.album);
    return cover;
  }

  @override
  Future<RemoteLyrics> lyricsFor(int songId) async {
    lyricsAsked.add(songId);
    return fakeLyrics;
  }

  @override
  Future<void> discardLyrics(int songId) async => discarded.add(songId);
}
