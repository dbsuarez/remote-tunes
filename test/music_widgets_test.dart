import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/features/music/music_browser.dart';
import 'package:remote_tunes/features/music/music_source.dart';
import 'package:remote_tunes/features/music/queue_view.dart';

RemoteSong song(int id, String title,
        {String artist = 'Ann', String album = 'Alpha', bool available = true}) =>
    RemoteSong(
      id: id,
      title: title,
      artist: artist,
      album: album,
      durationSeconds: 125,
      available: available,
    );

/// In-memory [MusicSource] that records what the UI asks it to do.
class FakeMusicSource implements MusicSource {
  FakeMusicSource({List<RemoteSong>? songs, List<RemoteQueueItem>? queue})
      : library = songs ?? [],
        queue = queue ?? [];

  final List<RemoteSong> library;
  final List<RemoteQueueItem> queue;
  final calls = <String>[];
  Object? failWith;
  final favorites = <int>{};
  final recentIds = <int>{};
  final playlistList = <RemotePlaylist>[];
  final playlistSongs = <int, List<int>>{};

  List<RemoteSong> _filter(String q, String? artist, String? album,
          {String? view, int? playlistId}) =>
      [
        for (final s in library)
          if ((q.isEmpty || s.title.toLowerCase().contains(q.toLowerCase())) &&
              (artist == null || s.artist == artist) &&
              (album == null || s.album == album) &&
              (view != LibraryView.favorites || favorites.contains(s.id)) &&
              (view != LibraryView.recent || recentIds.contains(s.id)) &&
              (playlistId == null || (playlistSongs[playlistId] ?? []).contains(s.id)))
            s,
      ];

  LibraryPage<T> _page<T>(List<T> all, int offset, int limit) => LibraryPage(
        items: all.skip(offset).take(limit).toList(),
        total: all.length,
        offset: offset,
      );

  @override
  Future<LibraryPage<RemoteSong>> songs(
      {String query = '',
      String? artist,
      String? album,
      String? view,
      int? playlistId,
      int offset = 0,
      int limit = 50}) async {
    if (failWith != null) throw failWith!;
    return _page(_filter(query, artist, album, view: view, playlistId: playlistId),
        offset, limit);
  }

  @override
  Future<LibraryPage<RemotePlaylist>> playlists(
          {String query = '', int offset = 0, int limit = 50}) async =>
      _page(playlistList, offset, limit);

  @override
  Future<void> setFavorite(int songId, bool favorite) async {
    calls.add('favorite $songId $favorite');
    favorite ? favorites.add(songId) : favorites.remove(songId);
  }

  @override
  Future<int> createPlaylist(String name) async {
    calls.add('createPlaylist $name');
    final id = playlistList.length + 1;
    playlistList.add(RemotePlaylist(id: id, name: name, songCount: 0));
    return id;
  }

  @override
  Future<void> renamePlaylist(int playlistId, String name) async =>
      calls.add('renamePlaylist $playlistId $name');

  @override
  Future<void> deletePlaylist(int playlistId) async =>
      calls.add('deletePlaylist $playlistId');

  @override
  Future<int> addToPlaylist(int playlistId, List<int> songIds) async {
    calls.add('addToPlaylist $playlistId $songIds');
    playlistSongs.putIfAbsent(playlistId, () => []).addAll(songIds);
    return songIds.length;
  }

  @override
  Future<void> removeFromPlaylist(int playlistId, int songId) async =>
      calls.add('removeFromPlaylist $playlistId $songId');

  @override
  Future<LibraryPage<RemoteArtist>> artists(
      {String query = '', int offset = 0, int limit = 50}) async {
    final names = {for (final s in _filter('', null, null)) s.artist};
    return _page([
      for (final n in names.toList()..sort())
        RemoteArtist(
          name: n,
          songCount: library.where((s) => s.artist == n).length,
          albumCount: library.where((s) => s.artist == n).map((s) => s.album).toSet().length,
        ),
    ], offset, limit);
  }

  @override
  Future<LibraryPage<RemoteAlbum>> albums(
      {String query = '', String? artist, int offset = 0, int limit = 50}) async {
    final keys = {for (final s in library) '${s.album}|${s.artist}'};
    return _page([
      for (final k in keys.toList()..sort())
        RemoteAlbum(
          name: k.split('|')[0],
          artist: k.split('|')[1],
          songCount: library.where((s) => '${s.album}|${s.artist}' == k).length,
        ),
    ], offset, limit);
  }

  @override
  Future<void> playSongs(List<int> songIds,
          {int? startSongId, bool keepQueue = false}) async =>
      calls.add('play $songIds start=$startSongId${keepQueue ? ' keep' : ''}');

  @override
  Future<void> queueSongs(List<int> songIds, {bool playNext = false}) async =>
      calls.add('queue $songIds next=$playNext');

  @override
  Future<QueueSnapshot> loadQueue() async {
    if (failWith != null) throw failWith!;
    return QueueSnapshot(items: List.of(queue));
  }

  @override
  Future<void> removeQueueItem(int id) async {
    calls.add('remove $id');
    queue.removeWhere((i) => i.queueItemId == id);
  }

  @override
  Future<void> moveQueueItem(int id, int newIndex) async {
    calls.add('move $id->$newIndex');
    final i = queue.indexWhere((e) => e.queueItemId == id);
    final item = queue.removeAt(i);
    queue.insert(newIndex, item);
  }

  @override
  Future<void> clearQueue() async {
    calls.add('clear');
    queue.clear();
  }

  @override
  Future<void> playQueueItem(int id) async => calls.add('jump $id');

  @override
  Future<void> setShuffle(bool enabled) async => calls.add('shuffle $enabled');

  @override
  Future<void> setRepeat(RepeatMode mode) async => calls.add('repeat ${mode.name}');
}

Widget host(Widget child) => MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: Scaffold(body: child),
    );

Future<void> settleUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

void main() {
  group('MusicBrowser', () {
    late FakeMusicSource source;

    setUp(() {
      source = FakeMusicSource(songs: [
        song(1, 'Apple Song', artist: 'Ann', album: 'Alpha'),
        song(2, 'Banana Song', artist: 'Ann', album: 'Alpha'),
        song(3, 'Cherry Song', artist: 'Bob', album: 'Beta'),
      ]);
    });

    testWidgets('lists songs with artist, album and duration', (tester) async {
      await tester.pumpWidget(host(MusicBrowser(source: source)));
      await settleUi(tester);
      expect(find.text('Apple Song'), findsOneWidget);
      expect(find.text('Ann · Alpha'), findsWidgets);
      expect(find.text('2:05'), findsWidgets);
      expect(find.text('Songs'), findsOneWidget);
      expect(find.text('Artists'), findsOneWidget);
      expect(find.text('Albums'), findsOneWidget);
    });

    testWidgets('search narrows the list after a short pause', (tester) async {
      await tester.pumpWidget(host(MusicBrowser(source: source)));
      await settleUi(tester);
      await tester.enterText(find.byType(TextField), 'cherry');
      await tester.pump(const Duration(milliseconds: 350));
      await settleUi(tester);
      expect(find.text('Cherry Song'), findsOneWidget);
      expect(find.text('Apple Song'), findsNothing);

      await tester.enterText(find.byType(TextField), 'zzz');
      await tester.pump(const Duration(milliseconds: 350));
      await settleUi(tester);
      expect(find.text('No matches.'), findsOneWidget);
    });

    testWidgets('tapping a song plays just that song', (tester) async {
      await tester.pumpWidget(host(MusicBrowser(source: source)));
      await settleUi(tester);
      await tester.tap(find.text('Banana Song'));
      await settleUi(tester);
      expect(source.calls, ['play [2] start=null keep']);
    });

    testWidgets('song menu: play next and add to queue', (tester) async {
      await tester.pumpWidget(host(MusicBrowser(source: source)));
      await settleUi(tester);

      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Play next'));
      await settleUi(tester);
      expect(find.text('Will play next'), findsOneWidget);

      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add to queue'));
      await settleUi(tester);

      expect(source.calls, ['queue [1] next=true', 'queue [1] next=false']);
      expect(find.text('Remove from library'), findsNothing,
          reason: 'only the Player can remove songs');
    });

    testWidgets('an unavailable song cannot be played', (tester) async {
      source = FakeMusicSource(songs: [song(9, 'Ghost', available: false)]);
      await tester.pumpWidget(host(MusicBrowser(source: source)));
      await settleUi(tester);
      expect(find.text('File missing from the Player'), findsOneWidget);
      await tester.tap(find.text('Ghost'));
      await settleUi(tester);
      expect(source.calls, isEmpty);
      expect(find.textContaining('missing from the Player'), findsWidgets);
    });

    testWidgets('artists chip, drill into an artist, Play all / tap a song',
        (tester) async {
      await tester.pumpWidget(host(MusicBrowser(source: source)));
      await settleUi(tester);

      await tester.tap(find.text('Artists'));
      await settleUi(tester);
      expect(find.text('Ann'), findsOneWidget);
      expect(find.text('2 songs · 1 album'), findsOneWidget);

      await tester.tap(find.text('Ann'));
      await settleUi(tester);
      expect(find.text('Play all'), findsOneWidget);
      expect(find.text('Apple Song'), findsOneWidget);
      expect(find.text('Cherry Song'), findsNothing);

      await tester.tap(find.text('Play all'));
      await settleUi(tester);
      await tester.tap(find.text('Banana Song'));
      await settleUi(tester);
      expect(source.calls, ['play [1, 2] start=null', 'play [1, 2] start=2']);

      await tester.tap(find.byTooltip('Add all to queue'));
      await settleUi(tester);
      expect(source.calls.last, 'queue [1, 2] next=false');

      await tester.tap(find.byTooltip('Back'));
      await settleUi(tester);
      expect(find.text('Artists'), findsOneWidget);
      expect(find.text('Play all'), findsNothing);
    });

    testWidgets('albums chip lists albums with their artist', (tester) async {
      await tester.pumpWidget(host(MusicBrowser(source: source)));
      await settleUi(tester);
      await tester.tap(find.text('Albums'));
      await settleUi(tester);
      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Ann · 2 songs'), findsOneWidget);
      expect(find.text('Bob · 1 song'), findsOneWidget);
    });

    testWidgets('empty library shows the hint', (tester) async {
      await tester.pumpWidget(host(MusicBrowser(
        source: FakeMusicSource(),
        emptyMessage: 'Nothing here yet.',
      )));
      await settleUi(tester);
      expect(find.text('Nothing here yet.'), findsOneWidget);
    });

    testWidgets('a failed load shows a plain message and Try again works',
        (tester) async {
      source.failWith = StateError('boom');
      await tester.pumpWidget(host(MusicBrowser(source: source)));
      await settleUi(tester);
      expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
      expect(find.textContaining('boom'), findsNothing);

      source.failWith = null;
      await tester.tap(find.text('Try again'));
      await settleUi(tester);
      expect(find.text('Apple Song'), findsOneWidget);
    });

    testWidgets('loads more pages when scrolling', (tester) async {
      source = FakeMusicSource(
          songs: [for (var i = 1; i <= 120; i++) song(i, 'Track ${i.toString().padLeft(3, '0')}')]);
      await tester.pumpWidget(host(MusicBrowser(source: source)));
      await settleUi(tester);
      expect(find.text('Track 001'), findsOneWidget);
      expect(find.text('Track 060'), findsNothing);
      await tester.dragUntilVisible(
        find.text('Track 100'),
        find.byType(ListView),
        const Offset(0, -400),
      );
      await settleUi(tester);
      expect(find.text('Track 100'), findsOneWidget);
    });

    testWidgets('Player can remove a song from the library', (tester) async {
      final removed = <int>[];
      await tester.pumpWidget(host(MusicBrowser(
        source: source,
        onRemoveSong: (s) async => removed.add(s.id),
      )));
      await settleUi(tester);
      await tester.tap(find.byTooltip('More').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from library'));
      await settleUi(tester);
      expect(removed, [1]);
    });

    testWidgets('disabled while reconnecting: taps do nothing', (tester) async {
      await tester.pumpWidget(host(MusicBrowser(source: source, enabled: false)));
      await settleUi(tester);
      await tester.tap(find.text('Apple Song'), warnIfMissed: false);
      await settleUi(tester);
      expect(source.calls, isEmpty);
    });
  });

  group('QueueView', () {
    RemoteQueueItem item(int id, String title, {bool current = false, bool available = true}) =>
        RemoteQueueItem(
          queueItemId: id,
          isCurrent: current,
          song: song(id, title, available: available),
        );

    Widget queue(FakeMusicSource s,
            {int revision = 1,
            int currentIndex = 0,
            bool shuffle = false,
            RepeatMode repeat = RepeatMode.off}) =>
        host(QueueView(
          source: s,
          revision: revision,
          currentIndex: currentIndex,
          shuffle: shuffle,
          repeat: repeat,
        ));

    testWidgets('shows the queue with a count and drag handles', (tester) async {
      final s = FakeMusicSource(queue: [item(10, 'One'), item(11, 'Two'), item(12, 'Three')]);
      await tester.pumpWidget(queue(s));
      await settleUi(tester);
      expect(find.text('One'), findsOneWidget);
      expect(find.text('3 in queue'), findsOneWidget);
      expect(find.byIcon(Icons.drag_handle_rounded), findsNWidgets(3));
      expect(find.byIcon(Icons.graphic_eq_rounded), findsOneWidget,
          reason: 'the playing entry is marked');
    });

    testWidgets('empty queue explains what to do', (tester) async {
      await tester.pumpWidget(queue(FakeMusicSource()));
      await settleUi(tester);
      expect(find.textContaining('The queue is empty'), findsOneWidget);
    });

    testWidgets('tap jumps to the entry; X removes it', (tester) async {
      final s = FakeMusicSource(queue: [item(10, 'One'), item(11, 'Two')]);
      await tester.pumpWidget(queue(s));
      await settleUi(tester);
      await tester.tap(find.text('Two'));
      await settleUi(tester);
      await tester.tap(find.byTooltip('Remove from queue').first);
      await settleUi(tester);
      expect(s.calls, ['jump 11', 'remove 10']);
      expect(find.text('One'), findsNothing);
    });

    testWidgets('clear, shuffle and repeat controls', (tester) async {
      final s = FakeMusicSource(queue: [item(10, 'One')]);
      await tester.pumpWidget(queue(s, repeat: RepeatMode.off));
      await settleUi(tester);
      await tester.tap(find.byIcon(Icons.shuffle_rounded));
      await settleUi(tester);
      await tester.tap(find.byIcon(Icons.repeat_rounded));
      await settleUi(tester);
      await tester.tap(find.text('Clear'));
      await settleUi(tester);
      expect(s.calls, ['shuffle true', 'repeat queue', 'clear']);
      expect(find.textContaining('The queue is empty'), findsOneWidget);
    });

    testWidgets('repeat cycles off -> queue -> one -> off', (tester) async {
      for (final (from, to) in [
        (RepeatMode.off, 'queue'),
        (RepeatMode.queue, 'one'),
        (RepeatMode.one, 'off'),
      ]) {
        final s = FakeMusicSource(queue: [item(10, 'One')]);
        await tester.pumpWidget(queue(s, repeat: from));
        await settleUi(tester);
        await tester.tap(find.byIcon(
            from == RepeatMode.off ? Icons.repeat_rounded : (from == RepeatMode.one ? Icons.repeat_one_on_rounded : Icons.repeat_on_rounded)));
        await settleUi(tester);
        expect(s.calls.single, 'repeat $to');
      }
    });

    testWidgets('dragging a handle reorders and tells the Player', (tester) async {
      final s = FakeMusicSource(queue: [item(10, 'One'), item(11, 'Two'), item(12, 'Three')]);
      await tester.pumpWidget(queue(s));
      await settleUi(tester);
      await tester.drag(find.byIcon(Icons.drag_handle_rounded).first, const Offset(0, 150));
      await tester.pumpAndSettle();
      expect(s.calls.single, startsWith('move 10->'));
      expect(s.queue.first.queueItemId, isNot(10));
    });

    testWidgets('reloads when the revision changes', (tester) async {
      final s = FakeMusicSource(queue: [item(10, 'One')]);
      await tester.pumpWidget(queue(s, revision: 1));
      await settleUi(tester);
      expect(find.text('1 in queue'), findsOneWidget);

      s.queue.add(item(11, 'Two'));
      await tester.pumpWidget(queue(s, revision: 2));
      await settleUi(tester);
      expect(find.text('2 in queue'), findsOneWidget);
      expect(find.text('Two'), findsOneWidget);
    });

    testWidgets('a missing file is flagged', (tester) async {
      final s = FakeMusicSource(queue: [item(10, 'Ghost', available: false)]);
      await tester.pumpWidget(queue(s));
      await settleUi(tester);
      expect(find.text('File missing from the Player'), findsOneWidget);
    });

    testWidgets('load errors show a retry', (tester) async {
      final s = FakeMusicSource()..failWith = StateError('boom');
      await tester.pumpWidget(queue(s));
      await settleUi(tester);
      expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
      s.failWith = null;
      await tester.tap(find.text('Try again'));
      await settleUi(tester);
      expect(find.textContaining('The queue is empty'), findsOneWidget);
    });
  });
}
