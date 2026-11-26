import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/features/cloud/cloud_history.dart';
import 'package:remote_tunes/features/cloud/cloud_models.dart';
import 'package:remote_tunes/features/cloud/cloud_service.dart';
import 'package:remote_tunes/features/cloud/r2_client.dart';

import 'cloud_test.dart' show FakeR2, song;

CloudSong s(String id, String title, {String artist = 'Ann', int dur = 100, DateTime? added, String album = 'A', int? track}) =>
    CloudSong(id: id, title: title, artist: artist, album: album, audioKey: 'songs/$id.mp3', durationSeconds: dur, added: added, track: track);

final jpg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 1, 2]);
final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 3, 4]);

void main() {
  group('sorting', () {
    final list = [
      s('1', 'banana', artist: 'Zed', dur: 50, added: DateTime(2026, 1, 2)),
      s('2', 'Apple', artist: 'bob', dur: 300, added: DateTime(2026, 3, 1)),
      s('3', 'cherry', artist: '', dur: 200),
      s('4', 'Date', artist: 'Bob', dur: 100, added: DateTime(2025, 1, 1), track: 1),
    ];
    List<String> ids(CloudSort sort, [List<String> recent = const []]) => [for (final x in sortCloudSongs(list, sort, recent)) x.id];

    test('by title, ignoring capitals', () => expect(ids(CloudSort.title), ['2', '1', '3', '4']));
    test('by artist, then album and track; no artist last', () => expect(ids(CloudSort.artist), ['4', '2', '1', '3']));
    test('newest and oldest; a song with no date is last', () {
      expect(ids(CloudSort.newest), ['2', '1', '4', '3']);
      expect(ids(CloudSort.oldest), ['4', '1', '2', '3']);
    });
    test('longest first', () => expect(ids(CloudSort.longest), ['2', '3', '4', '1']));
    test('recently played: only those, latest first; a deleted one is skipped', () {
      expect(ids(CloudSort.recent, ['3', 'gone', '1']), ['3', '1']);
      expect(ids(CloudSort.recent), isEmpty);
    });
    test('the list given is not changed', () {
      ids(CloudSort.longest);
      expect(list.first.id, '1');
    });
    test('a song played again moves to the front, and only 50 are kept', () {
      expect(CloudHistoryStore.played(['a', 'b', 'c'], 'c'), ['c', 'a', 'b']);
      final many = [for (var i = 0; i < 60; i++) '$i'];
      expect(CloudHistoryStore.played(many, 'new'), hasLength(50));
    });
  });

  group('the service', () {
    late FakeR2 r2;
    late CloudLibraryService svc;
    var n = 0;
    setUp(() async {
      n = 0;
      r2 = FakeR2();
      svc = r2.service(ids: () => 'x${++n}');
      await svc.upload([song('One', art: jpg), song('Two', art: jpg), song('Three', artist: 'Bob', album: 'Other')]);
    });
    List<String> idsNow() => [for (final x in r2.catalog.songs) x.id];

    test('several songs get the same details in one save; the rest stays', () async {
      final ids = idsNow();
      await svc.updateSongs([ids[0], ids[2]], artist: 'Cy', genre: 'Pop', year: 2020);
      final c = r2.catalog.songs;
      expect([for (final x in c) x.artist], ['Cy', 'Ann', 'Cy']);
      expect([for (final x in c) x.genre], ['Pop', 'Rock', 'Pop']);
      expect([for (final x in c) x.year], [2020, null, 2020]);
      expect([for (final x in c) x.album], ['Alpha', 'Alpha', 'Other']);
      expect([for (final x in c) x.title], ['One', 'Two', 'Three']);
    });

    test('a playlist is put in a new order; songs it does not name stay at the end', () async {
      final ids = idsNow();
      final p = (await svc.createPlaylist('L', ids)).id;
      await svc.reorderPlaylist(p, [ids[2], ids[0], 'ghost', ids[2]]);
      expect(r2.catalog.playlists.single.songIds, [ids[2], ids[0], ids[1]]);
    });

    test('a new cover goes to the chosen songs and the old file goes when nobody uses it', () async {
      final ids = idsNow();
      final old = r2.catalog.songs[0].artKey!;
      await svc.setCover([ids[0]], png);
      final first = r2.catalog.songs[0].artKey!;
      expect(first, isNot(old));
      expect(first, endsWith('.png'));
      expect(r2.files[first], png);
      expect(r2.files.containsKey(old), isTrue, reason: 'the second song still uses it');
      expect(r2.catalog.songs[1].artKey, old);
      await svc.setCover([ids[0], ids[1]], jpg);
      expect(r2.catalog.songs[0].artKey, r2.catalog.songs[1].artKey);
      expect(r2.files.containsKey(old), isFalse);
      expect(r2.files.containsKey(first), isFalse);
    });

    test('a song with no cover can be given one', () async {
      final id = idsNow()[2];
      await svc.setCover([id], jpg);
      expect(r2.files[r2.catalog.songById(id)!.artKey], jpg);
    });

    test('only a JPG or PNG up to 3 MB is taken, and nothing is sent otherwise', () async {
      final before = r2.puts;
      await expectLater(svc.setCover(idsNow(), Uint8List.fromList([1, 2, 3, 4, 5])), throwsA(isA<R2Exception>()));
      final big = Uint8List(CloudLibraryService.maxCoverBytes + 1)..setAll(0, jpg);
      await expectLater(svc.setCover(idsNow(), big), throwsA(isA<R2Exception>()));
      expect(r2.puts, before);
    });

    test("a later upload to the album gets the album's present cover", () async {
      await svc.setCover(idsNow().take(2), png);
      final cover = r2.catalog.songs[0].artKey;
      await svc.upload([song('Four', art: jpg)]);
      expect(r2.catalog.songs.last.artKey, cover);
    });
  });
}
