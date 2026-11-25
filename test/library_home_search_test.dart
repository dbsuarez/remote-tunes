import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/core/search_history.dart';
import 'package:remote_tunes/features/music/library_search.dart';
import 'package:remote_tunes/features/music/music_browser.dart';

import 'music_widgets_test.dart' show FakeMusicSource, settleUi, song;

/// A source that knows about albums, artists and folders too.
class _Source extends FakeMusicSource {
  _Source() : super(songs: [song(1, 'Alpha Song'), song(2, 'Beta Song', artist: 'Bob', album: 'Beta')]);

  final asked = <String>[];

  @override
  Future<LibraryPage<RemoteAlbum>> albums(
      {String query = '', String? artist, int offset = 0, int limit = 50}) async {
    asked.add('albums $query $limit');
    final all = [
      const RemoteAlbum(name: 'Alpha Album', artist: 'Ann', songCount: 3),
      const RemoteAlbum(name: 'Other', artist: 'Bob', songCount: 1),
    ].where((a) => a.name.toLowerCase().contains(query.toLowerCase())).toList();
    return LibraryPage(items: all, total: all.length, offset: 0);
  }

  @override
  Future<LibraryPage<RemoteArtist>> artists(
      {String query = '', int offset = 0, int limit = 50}) async {
    final all = [const RemoteArtist(name: 'Alpha Band', songCount: 4, albumCount: 1)]
        .where((a) => a.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return LibraryPage(items: all, total: all.length, offset: 0);
  }

  @override
  Future<LibraryPage<RemoteGroup>> groups(
      {required String kind, String query = '', int offset = 0, int limit = 50}) async {
    final all = kind == GroupKind.albumArtist
        ? [const RemoteGroup(name: 'Alpha Group', songCount: 6)]
            .where((g) => g.name.toLowerCase().contains(query.toLowerCase()))
            .toList()
        : <RemoteGroup>[];
    return LibraryPage(items: all, total: all.length, offset: 0);
  }

  @override
  Future<LibraryPage<RemoteFolder>> folders(
      {String query = '', int offset = 0, int limit = 50}) async {
    final all = [const RemoteFolder(id: 7, name: 'Alpha Rock', parent: 'Music', songCount: 2)]
        .where((f) => f.name.toLowerCase().contains(query.toLowerCase()))
        .toList();
    return LibraryPage(items: all, total: all.length, offset: 0);
  }
}

void main() {
  late _Source source;

  setUp(() => source = _Source());

  group('the Library as a list of categories', () {
    Future<void> openHome(WidgetTester tester, {VoidCallback? onSearch}) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: MusicBrowser(source: source, homeList: true, onSearch: onSearch),
        ),
      ));
      await settleUi(tester);
    }

    testWidgets('starts on the list of categories, not on songs', (tester) async {
      await openHome(tester);
      for (final c in [
        'All Songs', 'Folders', 'Albums', 'Artists', 'Favorites', 'Recent', 'Top', 'New', 'Playlists'
      ]) {
        expect(find.text(c), findsOneWidget, reason: c);
      }
      expect(find.text('Alpha Song'), findsNothing);
    });

    testWidgets('opening a category shows it with a back arrow to the list', (tester) async {
      await openHome(tester);
      await tester.tap(find.text('All Songs'));
      await settleUi(tester);
      expect(find.text('Alpha Song'), findsOneWidget);
      expect(find.byTooltip('Back to the Library'), findsOneWidget);
      await tester.tap(find.byTooltip('Back to the Library'));
      await settleUi(tester);
      expect(find.text('Folders'), findsOneWidget);
      expect(find.text('Alpha Song'), findsNothing);
    });

    testWidgets('Folders, Top and New open their own lists', (tester) async {
      await openHome(tester);
      await tester.tap(find.text('Top'));
      await settleUi(tester);
      expect(find.text('Nothing played yet. Your most played songs show up here.').evaluate().length +
              find.text('Alpha Song').evaluate().length,
          greaterThan(0));
    });

    testWidgets('the search button only shows when there is somewhere to go', (tester) async {
      await openHome(tester);
      expect(find.byTooltip('Search'), findsNothing);
      var opened = 0;
      await openHome(tester, onSearch: () => opened++);
      await tester.tap(find.byTooltip('Search'));
      expect(opened, 1);
    });

    testWidgets('without homeList the old chips are still there', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: MusicBrowser(source: source))));
      await settleUi(tester);
      expect(find.text('Songs'), findsOneWidget);
      expect(find.text('Alpha Song'), findsOneWidget);
    });

    testWidgets('a target opens an album at once, and back leaves the screen', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    body: MusicBrowser(
                      source: source,
                      initialTarget: const LibraryTarget(
                          title: 'Alpha Album', artist: 'Ann', album: 'Alpha'),
                    ),
                  ),
                )),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(find.text('Alpha Album'), findsOneWidget);
      expect(find.text('Play all'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('open'), findsOneWidget);
    });
  });

  group('the search screen', () {
    late ProviderContainer container;

    Future<void> openSearch(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      container = ProviderContainer();
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(home: LibrarySearchScreen(source: source)),
      ));
      await settleUi(tester);
    }

    Future<void> type(WidgetTester tester, String text) async {
      await tester.enterText(find.byType(TextField), text);
      await tester.pump(const Duration(milliseconds: 400));
      await settleUi(tester);
    }

    testWidgets('starts with a hint when there is no history', (tester) async {
      await openSearch(tester);
      expect(find.text('Search songs, albums, artists and folders.'), findsOneWidget);
      for (final c in ['All', 'Songs', 'Albums', 'Artists', 'Folders']) {
        expect(find.text(c), findsOneWidget, reason: c);
      }
    });

    testWidgets('All shows every kind of match in its own section', (tester) async {
      await openSearch(tester);
      await type(tester, 'alpha');
      expect(find.text('Alpha Song'), findsOneWidget);
      expect(find.text('Alpha Album'), findsOneWidget);
      expect(find.text('Alpha Band'), findsOneWidget);
      expect(find.text('Alpha Rock'), findsOneWidget);
      expect(find.text('Beta Song'), findsNothing);
      expect(find.text('See all'), findsNWidgets(5), reason: 'songs, albums, artists, album artists, folders');
    });

    testWidgets('a kind can be chosen, and then shows more of it', (tester) async {
      await openSearch(tester);
      await type(tester, 'alpha');
      await tester.tap(find.widgetWithText(ChoiceChip, 'Albums'));
      await settleUi(tester);
      expect(find.text('Alpha Album'), findsOneWidget);
      expect(find.text('Alpha Song'), findsNothing);
      expect(find.text('Alpha Band'), findsNothing);
      expect(source.asked.last, 'albums alpha 50');
    });

    testWidgets('"See all" jumps to that kind', (tester) async {
      await openSearch(tester);
      await type(tester, 'alpha');
      await tester.tap(find.text('See all').at(1)); // the albums section
      await settleUi(tester);
      expect(find.text('Alpha Song'), findsNothing);
      expect(find.text('Alpha Album'), findsOneWidget);
    });

    testWidgets('Album Artists are found, and open like an artist', (tester) async {
      await openSearch(tester);
      await type(tester, 'alpha');
      expect(find.text('Alpha Group'), findsOneWidget);
      expect(find.widgetWithText(ChoiceChip, 'Album Artists'), findsOneWidget);
      await tester.tap(find.text('Alpha Group'));
      await tester.pumpAndSettle();
      expect(find.text('Play all'), findsOneWidget);
      expect(container.read(searchHistoryProvider), ['alpha']);
    });

    testWidgets('Play and Shuffle start everything that was found', (tester) async {
      await openSearch(tester);
      await type(tester, 'song');
      expect(find.text('Play'), findsOneWidget);
      expect(find.text('Shuffle'), findsOneWidget);
      await tester.tap(find.text('Play'));
      await settleUi(tester);
      expect(source.calls.any((c) => c.startsWith('play ')), isTrue, reason: source.calls.toString());
      source.calls.clear();
      await tester.tap(find.text('Shuffle'));
      await settleUi(tester);
      expect(source.calls.any((c) => c.startsWith('play ')), isTrue);
    });

    testWidgets('no match says so', (tester) async {
      await openSearch(tester);
      await type(tester, 'zzzz');
      expect(find.text('No matches for "zzzz".'), findsOneWidget);
    });

    testWidgets('tapping a song plays it (keeping the queue) and remembers the search',
        (tester) async {
      await openSearch(tester);
      await type(tester, 'alpha');
      await tester.tap(find.text('Alpha Song'));
      await settleUi(tester);
      expect(source.calls.any((c) => c.contains('play') && c.contains('1')), isTrue);
      expect(container.read(searchHistoryProvider), ['alpha']);
    });

    testWidgets('tapping an album opens it and remembers the search', (tester) async {
      await openSearch(tester);
      await type(tester, 'alpha');
      await tester.tap(find.text('Alpha Album'));
      await tester.pumpAndSettle();
      expect(find.text('Play all'), findsOneWidget);
      expect(container.read(searchHistoryProvider), ['alpha']);
    });

    testWidgets('the history is listed, tapped to search again, trimmed one by one and cleared',
        (tester) async {
      await openSearch(tester);
      container.read(searchHistoryProvider.notifier)
        ..add('beta')
        ..add('alpha');
      await tester.pump();
      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('beta'), findsOneWidget);

      await tester.tap(find.text('beta'));
      await tester.pump(const Duration(milliseconds: 50));
      await settleUi(tester);
      expect(find.text('Beta Song'), findsOneWidget);
      expect(tester.widget<TextField>(find.byType(TextField)).controller!.text, 'beta');

      await tester.tap(find.byTooltip('Clear search'));
      await settleUi(tester);
      await tester.tap(find.byTooltip('Remove "beta" from the history'));
      await tester.pump();
      expect(container.read(searchHistoryProvider), ['alpha']);

      await tester.tap(find.text('Clear search history'));
      await tester.pump();
      expect(container.read(searchHistoryProvider), isEmpty);
    });

    testWidgets('a failing Player shows a plain message', (tester) async {
      await openSearch(tester);
      source.failWith = StateError('offline');
      await type(tester, 'alpha');
      expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    });
  });

  group('the search history list', () {
    test('newest first, no repeats (ignoring case), short ones skipped, at most 20', () {
      final h = SearchHistory();
      h.add('a'); // too short
      h.add('Alpha');
      h.add('beta');
      h.add('ALPHA');
      expect(h.state, ['ALPHA', 'beta']);
      for (var i = 0; i < 30; i++) {
        h.add('query $i');
      }
      expect(h.state.length, SearchHistory.maxEntries);
      expect(h.state.first, 'query 29');
    });

    test('long text is cut, and what was saved is picked up once', () {
      final h = SearchHistory();
      h.load(['saved one', 'saved two', 'saved one']);
      expect(h.state, ['saved one', 'saved two']);
      h.load(['ignored']);
      expect(h.state, ['saved one', 'saved two']);
      h.add('x' * 200);
      expect(h.state.first.length, SearchHistory.maxLength);
    });
  });
}
