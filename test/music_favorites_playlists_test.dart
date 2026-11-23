import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/features/music/music_browser.dart';

import 'music_widgets_test.dart' show FakeMusicSource, host, settleUi, song;

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
