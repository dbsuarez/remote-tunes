import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/core/widgets/playback_widgets.dart' show formatCount;
import 'package:remote_tunes/features/music/music_browser.dart';

import 'music_widgets_test.dart' show FakeMusicSource, settleUi;

/// A pretend library with 3 songs that also says how big the other categories are.
class _Source extends FakeMusicSource {
  _Source({super.songs});

  @override
  Future<LibraryPage<RemoteSong>> songs({
    String query = '',
    String? artist,
    String? album,
    String? view,
    int? playlistId,
    int? folderId,
    String? groupKind,
    String? groupValue,
    int offset = 0,
    int limit = 50,
  }) async {
    if (failWith != null) throw failWith!;
    final all = switch (view) {
      LibraryView.top => [for (final s in library) if (s.plays > 0) s],
      LibraryView.skipped => [for (final s in library) if (s.skips > 0) s],
      LibraryView.never => [for (final s in library) if (s.plays == 0) s],
      _ => library,
    };
    return LibraryPage(
        items: all.skip(offset).take(limit).toList(), total: all.length, offset: offset);
  }

  @override
  Future<LibraryPage<RemoteArtist>> artists(
      {String query = '', int offset = 0, int limit = 50}) async {
    const all = [
      RemoteArtist(name: 'Ann', songCount: 2, albumCount: 1),
      RemoteArtist(name: 'Bob', songCount: 1, albumCount: 1),
    ];
    return LibraryPage(items: all.take(limit).toList(), total: all.length, offset: 0);
  }

  @override
  Future<LibraryPage<RemoteGroup>> groups(
      {required String kind, String query = '', int offset = 0, int limit = 50}) async {
    final all = kind == GroupKind.genre
        ? [
            for (var i = 0; i < 1234; i++) RemoteGroup(name: 'g$i', songCount: 1),
          ]
        : <RemoteGroup>[];
    return LibraryPage(items: all.take(limit).toList(), total: all.length, offset: 0);
  }
}

RemoteSong _song(int id, String title, {int plays = 0, int skips = 0}) => RemoteSong(
      id: id,
      title: title,
      artist: 'Ann',
      album: 'Alpha',
      durationSeconds: 125,
      plays: plays,
      skips: skips,
    );

void main() {
  test('numbers get thousands separators', () {
    expect(formatCount(0), '0');
    expect(formatCount(7), '7');
    expect(formatCount(999), '999');
    expect(formatCount(1000), '1,000');
    expect(formatCount(2043), '2,043');
    expect(formatCount(1234567), '1,234,567');
  });

  group('the Library list says how many are in each category', () {
    late _Source source;

    setUp(() {
      source = _Source(songs: [
        _song(1, 'A', plays: 5, skips: 2),
        _song(2, 'B', plays: 1),
        _song(3, 'C'),
      ]);
    });

    Future<void> openHome(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400, 1400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: MusicBrowser(source: source, homeList: true)),
      ));
      await settleUi(tester);
    }

    String countOf(WidgetTester tester, String scope) =>
        tester.widget<Text>(find.byKey(ValueKey('count-$scope'))).data!;

    testWidgets('All Songs, artists, genres and the lists made from play counts', (tester) async {
      await openHome(tester);
      expect(countOf(tester, 'songs'), '3');
      expect(countOf(tester, 'artists'), '2');
      expect(countOf(tester, 'genres'), '1,234', reason: 'with a thousands separator');
      expect(countOf(tester, 'top'), '2', reason: 'two songs have been played');
      expect(countOf(tester, 'skipped'), '1');
      expect(countOf(tester, 'never'), '1');
      expect(countOf(tester, 'years'), '0');
    });

    testWidgets('coming back to the list shows the numbers again', (tester) async {
      await openHome(tester);
      await tester.tap(find.text('All Songs'));
      await settleUi(tester);
      await tester.tap(find.byTooltip('Back to the Library'));
      await settleUi(tester);
      expect(countOf(tester, 'songs'), '3');
    });

    testWidgets('a category the source cannot count just shows no number', (tester) async {
      source.failWith = StateError('offline');
      await openHome(tester);
      expect(find.byKey(const ValueKey('count-songs')), findsNothing);
      expect(find.text('All Songs'), findsOneWidget, reason: 'the list still works');
    });
  });

  group('Most played and Most skipped say how many', () {
    late _Source source;

    setUp(() {
      source = _Source(songs: [
        _song(1, 'Heavy', plays: 12, skips: 3),
        _song(2, 'Once', plays: 1),
      ]);
    });

    Future<void> openList(WidgetTester tester, String category) async {
      tester.view.physicalSize = const Size(400, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: MusicBrowser(source: source, homeList: true)),
      ));
      await settleUi(tester);
      await tester.tap(find.text(category));
      await settleUi(tester);
    }

    testWidgets('Most played shows the plays in bold, and the skips small', (tester) async {
      await openList(tester, 'Most played');
      final counts = [for (final t in tester.widgetList<Text>(find.byKey(const Key('song-count')))) t.data];
      expect(counts, ['12 plays', '1 play']);
      expect(find.textContaining('3 skips'), findsOneWidget);
    });

    testWidgets('Most skipped shows the skips in bold, and the plays small', (tester) async {
      await openList(tester, 'Most skipped');
      final counts = [for (final t in tester.widgetList<Text>(find.byKey(const Key('song-count')))) t.data];
      expect(counts, ['3 skips']);
      expect(find.textContaining('12 plays'), findsOneWidget);
    });
  });
}
