import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/features/cloud/cloud_models.dart';
import 'package:remote_tunes/features/cloud/cloud_service.dart';
import 'package:remote_tunes/features/cloud/r2_client.dart';

import 'cloud_test.dart' show FakeR2, song;

CloudSong s(String id, String title, {String artist = 'Ann', String album = 'First', String genre = 'Rock', int? track, int? year, String? art}) =>
    CloudSong(id: id, title: title, artist: artist, album: album, genre: genre, track: track, year: year, audioKey: 'songs/$id.mp3', artKey: art);

void main() {
  group('artists and albums', () {
    final cat = CloudCatalog([
      s('1', 'Zed Song', artist: 'Ann', album: 'First', track: 2, year: 1999, art: 'artwork/a.jpg'),
      s('2', 'Alpha Song', artist: 'Ann', album: 'First', track: 1),
      s('3', 'Other', artist: 'ann', album: 'Second'),
      s('4', 'Solo', artist: 'Bob', album: 'First'),
      s('5', 'No Artist', artist: '', album: ''),
    ]);

    test('artists are counted without minding capitals, by name, with their albums', () {
      final a = cat.artists;
      expect(a.map((x) => x.name), ['Ann', 'Bob']);
      expect((a[0].songs, a[0].albums), (3, 2));
      expect((a[1].songs, a[1].albums), (1, 1));
    });

    test('albums are an artist and a title; the same title by another artist is another album', () {
      final al = cat.albums;
      expect(al.map((x) => '${x.title}/${x.artist}/${x.songs}'), ['First/Ann/2', 'First/Bob/1', 'Second/ann/1']);
      final first = al.first;
      expect(first.artKey, 'artwork/a.jpg', reason: 'a cover from any of its songs');
      expect(first.year, 1999);
    });

    test('the songs of an artist: by album, then track', () {
      expect(cat.songsOfArtist('ANN').map((x) => x.id), ['2', '1', '3']);
      expect(cat.songsOfArtist('nobody'), isEmpty);
    });

    test('the songs of an album: in track order, songs with no number last, then by title', () {
      expect(cat.songsOfAlbum(cat.albums.first).map((x) => x.title), ['Alpha Song', 'Zed Song']);
      final c = CloudCatalog([s('a', 'B', track: null), s('b', 'A', track: null), s('c', 'Z', track: 1)]);
      expect(c.songsOfAlbum(c.albums.single).map((x) => x.title), ['Z', 'A', 'B']);
    });

    test('an empty catalog has none', () {
      expect(const CloudCatalog().artists, isEmpty);
      expect(const CloudCatalog().albums, isEmpty);
    });
  });

  group('playlists in the catalog', () {
    test('are written and read back, in order', () {
      final c = CloudCatalog([s('1', 'A'), s('2', 'B')], const [CloudPlaylist(id: 'p', name: 'Gym', songIds: ['2', '1'])]);
      final back = CloudCatalog.fromJson(jsonDecode(jsonEncode(c.toJson())));
      expect(back.playlists.single.name, 'Gym');
      expect(back.playlists.single.songIds, ['2', '1']);
      expect(back.songsOfPlaylist(back.playlists.single).map((x) => x.title), ['B', 'A']);
    });

    test('a catalog with no playlists does not write the key, and an older file reads as none', () {
      expect(CloudCatalog([s('1', 'A')]).toJson().containsKey('playlists'), isFalse);
      expect(CloudCatalog.fromJson({'songs': []}).playlists, isEmpty);
    });

    test('damaged playlists are skipped', () {
      final c = CloudCatalog.fromJson({
        'songs': [
          {'id': '1', 'title': 'A', 'audio': 'songs/1.mp3'}
        ],
        'playlists': [
          {'id': 'ok', 'name': 'Fine', 'songs': ['1', 5, '', 'gone']},
          {'id': '', 'name': 'No id'},
          {'id': 'x', 'name': '  '},
          'junk',
        ],
      });
      expect(c.playlists.map((p) => p.name), ['Fine']);
      expect(c.playlists.single.songIds, ['1', 'gone']);
      expect(c.songsOfPlaylist(c.playlists.single).map((x) => x.id), ['1'], reason: 'an id that is no song is skipped');
    });

    test('taking a song out of the catalog takes it out of the playlists, and the playlists stay', () {
      final c = CloudCatalog([s('1', 'A'), s('2', 'B')], const [CloudPlaylist(id: 'p', name: 'L', songIds: ['1', '2'])]);
      final next = c.changed(remove: ['1']);
      expect(next.playlists.single.songIds, ['2']);
      expect(c.changed(add: [s('3', 'C')]).playlists.single.songIds, ['1', '2'], reason: 'adding keeps them');
    });

    test('replacing a song keeps the playlists', () {
      final c = CloudCatalog([s('1', 'A')], const [CloudPlaylist(id: 'p', name: 'L', songIds: ['1'])]);
      final next = c.withSong(s('1', 'Renamed'));
      expect(next.songs.single.title, 'Renamed');
      expect(next.playlists, hasLength(1));
      expect(c.withSong(s('9', 'Not there')).songs.single.title, 'A');
    });
  });

  group('the service edits the catalog', () {
    late FakeR2 r2;
    late CloudLibraryService svc;
    setUp(() async {
      r2 = FakeR2();
      svc = r2.service();
      await svc.upload([song('One'), song('Two', artist: 'Bob'), song('Three')]);
    });

    test('a song\'s details can be changed; the file and the cover stay', () async {
      final one = r2.catalog.songs.first;
      final next = await svc.updateSong(one.copyWith(title: 'One (Live)', artist: 'Ann Smith', album: 'Concert', genre: 'Pop', year: 2001, track: 5));
      final back = r2.catalog.songs.first;
      expect((back.title, back.artist, back.album, back.genre, back.year, back.track), ('One (Live)', 'Ann Smith', 'Concert', 'Pop', 2001, 5));
      expect((back.audioKey, back.sizeBytes), (one.audioKey, one.sizeBytes));
      expect(next.songs.first.title, 'One (Live)');
      expect(r2.catalog.songs, hasLength(3));
    });

    test('a title cannot be emptied, and a song that is gone is left alone', () async {
      final one = r2.catalog.songs.first;
      await expectLater(svc.updateSong(one.copyWith(title: '   ')), throwsA(isA<R2Exception>()));
      await svc.updateSong(s('nope', 'Ghost'));
      expect(r2.catalog.songs.map((x) => x.title), ['One', 'Two', 'Three']);
    });

    test('the year and track can be cleared', () async {
      final one = r2.catalog.songs.first;
      await svc.updateSong(one.copyWith(year: 1999, track: 3));
      await svc.updateSong(r2.catalog.songs.first.copyWith(clearYear: true, clearTrack: true));
      expect((r2.catalog.songs.first.year, r2.catalog.songs.first.track), (null, null));
    });

    test('a playlist is made with songs, the unknown ones left out, the name trimmed', () async {
      final ids = r2.catalog.songs.map((x) => x.id).toList();
      final made = await svc.createPlaylist('  Gym  ', [ids[2], ids[0], 'ghost', ids[2]]);
      final p = r2.catalog.playlists.single;
      expect((p.id, p.name), (made.id, 'Gym'));
      expect(p.songIds, [ids[2], ids[0]]);
      expect(made.catalog.playlists.single.id, made.id);
    });

    test('a playlist needs a name, and a long one is cut', () async {
      await expectLater(svc.createPlaylist('   '), throwsA(isA<R2Exception>()));
      await svc.createPlaylist('x' * 80);
      expect(r2.catalog.playlists.single.name, hasLength(60));
    });

    test('songs are added to the end, never twice, and only known ones', () async {
      final ids = r2.catalog.songs.map((x) => x.id).toList();
      final p = (await svc.createPlaylist('L', [ids[0]])).id;
      await svc.addToPlaylist(p, [ids[1], ids[0], 'ghost', ids[1]]);
      expect(r2.catalog.playlists.single.songIds, [ids[0], ids[1]]);
      await svc.addToPlaylist('no-such-list', [ids[2]]);
      expect(r2.catalog.playlists.single.songIds, [ids[0], ids[1]]);
    });

    test('songs are taken out of a playlist, it can be renamed, and deleted (the songs stay)', () async {
      final ids = r2.catalog.songs.map((x) => x.id).toList();
      final p = (await svc.createPlaylist('L', ids)).id;
      await svc.removeFromPlaylist(p, [ids[1]]);
      expect(r2.catalog.playlists.single.songIds, [ids[0], ids[2]]);
      await svc.renamePlaylist(p, 'Renamed');
      expect(r2.catalog.playlists.single.name, 'Renamed');
      await expectLater(svc.renamePlaylist(p, ''), throwsA(isA<R2Exception>()));
      await svc.deletePlaylist(p);
      expect(r2.catalog.playlists, isEmpty);
      expect(r2.catalog.songs, hasLength(3));
    });

    test('deleting a song from the cloud takes it out of the playlists', () async {
      final songs = r2.catalog.songs;
      final p = (await svc.createPlaylist('L', songs.map((x) => x.id))).id;
      await svc.remove([songs[0]]);
      expect(r2.catalog.playlists.single.songIds, [songs[1].id, songs[2].id]);
      expect(r2.catalog.playlists.single.id, p);
    });

    test('uploading more songs keeps the playlists', () async {
      await svc.createPlaylist('Keep me', [r2.catalog.songs.first.id]);
      final later = r2.service(ids: () => 'later');
      await later.upload([song('Four')]);
      expect(r2.catalog.playlists.single.name, 'Keep me');
      expect(r2.catalog.songs, hasLength(4));
    });

    test('a change reads the newest catalog first, so another phone\'s change is not undone', () async {
      // Another phone adds a song after this one last looked.
      final other = r2.service(ids: () => 'other');
      await other.upload([song('From the other phone')]);
      final ids = r2.catalog.songs.map((x) => x.id).toList();
      await svc.createPlaylist('Mine', [ids.first]);
      expect(r2.catalog.songs, hasLength(4), reason: 'the other phone\'s song is still there');
      expect(r2.catalog.playlists.single.name, 'Mine');
    });

    test('without the keys nothing can be changed', () async {
      final reader = r2.service(cfg: const CloudConfig(publicUrl: 'https://pub-123.r2.dev'));
      await expectLater(reader.createPlaylist('X'), throwsA(isA<R2Exception>()));
      await expectLater(reader.updateSong(s('1', 'T')), throwsA(isA<R2Exception>()));
    });
  });
}
