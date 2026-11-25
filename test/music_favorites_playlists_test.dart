import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/features/music/music_browser.dart';

import 'music_widgets_test.dart' show FakeMusicSource, host, settleUi, song;
import 'package:remote_tunes/features/music/song_art.dart';

void main() {
  late FakeMusicSource source;

  setUp(() {
    source = FakeMusicSource(songs: [
      song(1, 'Apple Song'),
      song(2, 'Banana Song'),
      song(3, 'Cherry Song', artist: 'Bob', album: 'Beta'),
    ]);
  });

  Future<void> open(WidgetTester tester) async {
    await tester.pumpWidget(host(MusicBrowser(source: source)));
    await settleUi(tester);
  }

  testWidgets('song rows show album art when the song has it, the default picture otherwise',
      (tester) async {
    source.withArt.add(2); // only Banana
    await open(tester);
    await tester.pump(const Duration(milliseconds: 100));

    CircleAvatar avatarOf(String title) => tester.widget<CircleAvatar>(find.descendant(
        of: find.ancestor(of: find.text(title), matching: find.byType(ListTile)),
        matching: find.descendant(
            of: find.byType(SongArt), matching: find.byType(CircleAvatar))));

    expect(avatarOf('Banana Song').backgroundImage, isA<MemoryImage>());
    // The one without art shows the default picture (not a plain note).
    expect(avatarOf('Apple Song').backgroundImage, isA<ResizeImage>());
    expect(
        find.descendant(
            of: find.ancestor(of: find.text('Apple Song'), matching: find.byType(ListTile)),
            matching: find.byIcon(Icons.music_note_rounded)),
        findsNothing);
  });

  testWidgets('a selected row with art keeps the picture and adds a check',
      (tester) async {
    source.withArt.add(2);
    await open(tester);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.longPress(find.text('Banana Song'));
    await settleUi(tester);
    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  testWidgets('all six filter chips are offered', (tester) async {
    await open(tester);
    for (final t in ['Songs', 'Artists', 'Albums', 'Favorites', 'Recent', 'Playlists']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
  });

  testWidgets('the heart marks a favorite and Favorites lists it', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Add to favorites').at(1)); // Banana
    await settleUi(tester);
    expect(source.calls, ['favorite 2 true']);
    expect(find.byTooltip('Remove from favorites'), findsOneWidget);

    await tester.tap(find.text('Favorites'));
    await settleUi(tester);
    expect(find.text('Banana Song'), findsOneWidget);
    expect(find.text('Apple Song'), findsNothing);
  });

  testWidgets('an empty Favorites list explains itself', (tester) async {
    await open(tester);
    await tester.tap(find.text('Favorites'));
    await settleUi(tester);
    expect(find.textContaining('No favorites yet'), findsOneWidget);
  });

  testWidgets('the heart goes back if the Player says no', (tester) async {
    source.failWith = null;
    final failing = _FailingFavorites(songs: [song(1, 'Apple Song')]);
    await tester.pumpWidget(host(MusicBrowser(source: failing)));
    await settleUi(tester);
    await tester.tap(find.byTooltip('Add to favorites'));
    await settleUi(tester);
    expect(find.byTooltip('Add to favorites'), findsOneWidget);
    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
  });

  testWidgets('Recent explains itself when nothing has played', (tester) async {
    await open(tester);
    await tester.tap(find.text('Recent'));
    await settleUi(tester);
    expect(find.text('Nothing played yet.'), findsOneWidget);
  });

  testWidgets('make a playlist, add a song to it, open it', (tester) async {
    await open(tester);
    await tester.tap(find.text('Playlists'));
    await settleUi(tester);
    expect(find.textContaining('No playlists yet'), findsOneWidget);

    await tester.tap(find.text('New playlist'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Road trip');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(source.calls, ['createPlaylist Road trip']);
    expect(find.text('Road trip'), findsOneWidget);

    // Back to Songs, add Cherry to the playlist from its menu.
    await tester.tap(find.text('Songs'));
    await settleUi(tester);
    await tester.tap(find.byTooltip('More').at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add to playlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Road trip'));
    await tester.pumpAndSettle();
    expect(source.calls.last, 'addToPlaylist 1 [3]');
    expect(find.text('Added to "Road trip"'), findsOneWidget);

    // Open the playlist: only that song, and it plays with the playlist.
    await tester.tap(find.text('Playlists'));
    await settleUi(tester);
    await tester.tap(find.text('Road trip'));
    await settleUi(tester);
    expect(find.text('Cherry Song'), findsOneWidget);
    expect(find.text('Apple Song'), findsNothing);
    await tester.tap(find.text('Cherry Song'));
    await settleUi(tester);
    expect(source.calls.last, 'play [3] start=3');
  });


  testWidgets('long-press selects songs; add them all to a playlist', (tester) async {
    source.playlistList.add(const RemotePlaylist(id: 4, name: 'Gym', songCount: 0));
    await open(tester);

    await tester.longPress(find.text('Apple Song'));
    await settleUi(tester);
    expect(find.text('1 selected'), findsOneWidget);
    // Now taps pick songs instead of playing them.
    await tester.tap(find.text('Cherry Song'));
    await settleUi(tester);
    expect(find.text('2 selected'), findsOneWidget);
    expect(source.calls, isEmpty);
    // Tap again to drop one.
    await tester.tap(find.text('Cherry Song'));
    await settleUi(tester);
    await tester.tap(find.text('Banana Song'));
    await settleUi(tester);
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('Add selected to playlist'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Gym'));
    await tester.pumpAndSettle();
    expect(source.calls.last, 'addToPlaylist 4 [1, 2]');
    expect(find.text('Added 2 songs to "Gym"'), findsOneWidget);
    expect(find.textContaining('selected'), findsNothing,
        reason: 'the selection ends after the action');
  });

  group('taking songs out of a playlist', () {
    Future<void> openPlaylist(WidgetTester tester) async {
      source.playlistList.add(const RemotePlaylist(id: 4, name: 'Gym', songCount: 3));
      source.playlistSongs[4] = [1, 2, 3];
      await open(tester);
      await tester.tap(find.text('Playlists'));
      await settleUi(tester);
      await tester.tap(find.text('Gym'));
      await settleUi(tester);
      expect(find.text('Apple Song'), findsOneWidget);
    }

    testWidgets('one song, from its menu', (tester) async {
      await openPlaylist(tester);
      await tester.tap(find.byTooltip('More').at(1)); // Banana
      await tester.pumpAndSettle();
      await tester.tap(find.text('Remove from playlist'));
      await settleUi(tester);
      expect(source.calls.last, 'removeFromPlaylist 4 2');
      expect(find.text('Banana Song'), findsNothing);
      expect(find.text('Apple Song'), findsOneWidget);
    });

    testWidgets('several at once: pick them, then use the bar', (tester) async {
      await openPlaylist(tester);
      await tester.longPress(find.text('Apple Song'));
      await settleUi(tester);
      await tester.tap(find.text('Cherry Song'));
      await settleUi(tester);
      expect(find.text('2 selected'), findsOneWidget);
      await tester.tap(find.byTooltip('Remove selected from the playlist'));
      await settleUi(tester);
      expect(source.calls.where((c) => c.startsWith('removeFromPlaylist')).toList(),
          ['removeFromPlaylist 4 1', 'removeFromPlaylist 4 3']);
      expect(find.text('Apple Song'), findsNothing);
      expect(find.text('Cherry Song'), findsNothing);
      expect(find.text('Banana Song'), findsOneWidget, reason: 'the one not picked stays');
      expect(find.textContaining('selected'), findsNothing, reason: 'the selection ends');
      expect(find.text('Removed from the playlist'), findsOneWidget);
    });

    testWidgets('the button is only there inside a playlist', (tester) async {
      await open(tester);
      await tester.longPress(find.text('Apple Song'));
      await settleUi(tester);
      expect(find.byTooltip('Remove selected from the playlist'), findsNothing);
      expect(find.byTooltip('Add selected to playlist'), findsOneWidget);
    });
  });

  testWidgets('select all, add to queue, and cancel', (tester) async {
    await open(tester);
    await tester.longPress(find.text('Apple Song'));
    await settleUi(tester);
    await tester.tap(find.byTooltip('Select all'));
    await settleUi(tester);
    expect(find.text('3 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('Add selected to queue'));
    await settleUi(tester);
    expect(source.calls.last, startsWith('queue [')); 
    expect(find.textContaining('selected'), findsNothing);

    await tester.longPress(find.text('Banana Song'));
    await settleUi(tester);
    await tester.tap(find.byTooltip('Cancel selection'));
    await settleUi(tester);
    expect(find.textContaining('selected'), findsNothing);
  });

  testWidgets('a playlist can be renamed and deleted', (tester) async {
    source.playlistList.add(const RemotePlaylist(id: 7, name: 'Mix', songCount: 0));
    await open(tester);
    await tester.tap(find.text('Playlists'));
    await settleUi(tester);
    await tester.tap(find.text('Mix'));
    await settleUi(tester);
    expect(find.textContaining('This playlist is empty'), findsOneWidget);

    await tester.tap(find.byTooltip('Playlist options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Better mix');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(source.calls, ['renamePlaylist 7 Better mix']);
    expect(find.text('Better mix'), findsOneWidget);

    await tester.tap(find.byTooltip('Playlist options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete playlist'));
    await tester.pumpAndSettle();
    expect(find.text('The songs stay in your library.'), findsOneWidget);
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(source.calls.last, 'deletePlaylist 7');
  });
}

class _FailingFavorites extends FakeMusicSource {
  _FailingFavorites({super.songs});

  @override
  Future<void> setFavorite(int songId, bool favorite) async =>
      throw StateError('no');
}
