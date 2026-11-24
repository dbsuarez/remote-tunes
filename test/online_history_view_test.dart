import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/features/online_library/jamendo_api.dart';
import 'package:remote_tunes/features/online_library/jamendo_key_store.dart';
import 'package:remote_tunes/features/online_library/online_history_source.dart';
import 'package:remote_tunes/features/online_library/online_history_view.dart';
import 'package:remote_tunes/features/online_library/online_library_view.dart';

class _Keys implements JamendoKeyStore {
  _Keys([this.id]);
  String? id;
  @override
  Future<String?> load() async => id;
  @override
  Future<void> save(String clientId) async => id = clientId;
  @override
  Future<void> clear() async => id = null;
}

class FakeHistory implements OnlineHistorySource {
  FakeHistory(this.items);

  List<RemoteHistoryItem> items;
  bool enabled = true;
  final calls = <String>[];
  Object? failWith;

  @override
  Future<({LibraryPage<RemoteHistoryItem> page, bool enabled})> load(
      {int offset = 0, int limit = 50}) async {
    calls.add('load');
    if (failWith != null) throw failWith!;
    return (
      page: LibraryPage(
          items: items.skip(offset).take(limit).toList(), total: items.length, offset: offset),
      enabled: enabled,
    );
  }

  @override
  Future<void> play(RemoteHistoryItem item, {required bool queue}) async =>
      calls.add('${queue ? 'queue' : 'play'} ${item.title}');

  @override
  Future<void> remove(RemoteHistoryItem item) async {
    calls.add('remove ${item.title}');
    items = [for (final e in items) if (e.id != item.id) e];
  }

  @override
  Future<void> clear() async {
    calls.add('clear');
    items = [];
  }

  @override
  Future<void> setEnabled(bool e) async {
    calls.add('enabled $e');
    enabled = e;
  }
}

RemoteHistoryItem item(int id, String title, {int at = 0, String? license}) =>
    RemoteHistoryItem(
      id: id,
      title: title,
      artist: 'Band $id',
      album: 'Album $id',
      licenseUrl: license,
      playedAtSeconds: at,
    );

void main() {
  final now = DateTime(2026, 11, 24, 15, 30);
  int secs(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

  Future<void> open(WidgetTester tester, FakeHistory source,
      {VoidCallback? onBack}) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OnlineHistoryView(source: source, onBack: onBack ?? () {}, now: now),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  test('time labels are friendly', () {
    expect(playedLabel(now, secs(DateTime(2026, 11, 24, 9, 5))), 'Today 09:05');
    expect(playedLabel(now, secs(DateTime(2026, 11, 23, 22, 40))), 'Yesterday 22:40');
    expect(playedLabel(now, secs(DateTime(2026, 11, 2, 8, 0))), '2 Nov 2026');
    expect(playedLabel(now, 0), '');
  });

  testWidgets('lists what was played, with artist, album, when and licence',
      (tester) async {
    await open(
        tester,
        FakeHistory([
          item(1, 'Song One',
              at: secs(DateTime(2026, 11, 24, 9, 5)),
              license: 'http://creativecommons.org/licenses/by-nc-nd/3.0/'),
          item(2, 'Song Two', at: secs(DateTime(2026, 11, 23, 22, 40))),
        ]));
    expect(find.text('Song One'), findsOneWidget);
    expect(find.text('Band 1 · Album 1'), findsOneWidget);
    expect(find.text('Today 09:05 · CC BY-NC-ND 3.0'), findsOneWidget);
    expect(find.text('Yesterday 22:40'), findsOneWidget);
    expect(find.text('Stored on the Player phone only. Never sent anywhere.'), findsOneWidget);
  });

  testWidgets('an empty history explains itself', (tester) async {
    await open(tester, FakeHistory([]));
    expect(find.textContaining('Nothing here yet'), findsOneWidget);
    // Nothing to clear.
    expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Clear')).onPressed, isNull);
  });

  testWidgets('play, add to queue', (tester) async {
    final src = FakeHistory([item(1, 'Song One'), item(2, 'Song Two')]);
    await open(tester, src);
    await tester.tap(find.byTooltip('Play on Player').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Playing on the Player'), findsOneWidget);
    await tester.tap(find.byTooltip('Add to queue').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(src.calls, containsAllInOrder(['load', 'play Song One', 'load', 'queue Song Two']));
    expect(find.text("Added to the Player's queue"), findsOneWidget);
  });

  testWidgets('tapping a row plays it again', (tester) async {
    final src = FakeHistory([item(1, 'Song One')]);
    await open(tester, src);
    await tester.tap(find.text('Song One'));
    await tester.pump();
    expect(src.calls, contains('play Song One'));
  });

  testWidgets('remove one entry', (tester) async {
    final src = FakeHistory([item(1, 'Song One'), item(2, 'Song Two')]);
    await open(tester, src);
    await tester.tap(find.byTooltip('More').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from history'));
    await tester.pumpAndSettle();
    expect(src.calls, contains('remove Song One'));
    expect(find.text('Song One'), findsNothing);
    expect(find.text('Song Two'), findsOneWidget);
  });

  testWidgets('clear asks first, and only clears when confirmed', (tester) async {
    final src = FakeHistory([item(1, 'Song One')]);
    await open(tester, src);
    await tester.tap(find.widgetWithText(TextButton, 'Clear'));
    await tester.pumpAndSettle();
    expect(find.text('Clear history?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(src.calls, isNot(contains('clear')));

    await tester.tap(find.widgetWithText(TextButton, 'Clear'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Clear'));
    await tester.pumpAndSettle();
    expect(src.calls, contains('clear'));
    expect(find.textContaining('Nothing here yet'), findsOneWidget);
  });

  testWidgets('the Keep history switch turns recording off and on', (tester) async {
    final src = FakeHistory([item(1, 'Song One')]);
    await open(tester, src);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isTrue);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(src.enabled, isFalse);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value, isFalse);
    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();
    expect(src.enabled, isTrue);
  });

  testWidgets('when history is off the empty list says so', (tester) async {
    final src = FakeHistory([])..enabled = false;
    await open(tester, src);
    expect(find.text('History is off, so nothing is being remembered.'), findsOneWidget);
  });

  testWidgets('a Player that cannot be reached shows why, with Try again',
      (tester) async {
    final src = FakeHistory([item(1, 'Song One')])..failWith = StateError('x');
    await open(tester, src);
    expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
    src.failWith = null;
    await tester.tap(find.text('Try again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Song One'), findsOneWidget);
  });

  testWidgets('Back returns to the search', (tester) async {
    var backs = 0;
    await open(tester, FakeHistory([]), onBack: () => backs++);
    await tester.tap(find.byTooltip('Back to search'));
    expect(backs, 1);
  });

  group('inside the Online tab', () {
    Future<void> openTab(WidgetTester tester, FakeHistory src, {String? key = '56d30c95'}) async {
      tester.view.physicalSize = const Size(800, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          jamendoKeyStoreProvider.overrideWithValue(_Keys(key)),
          jamendoApiProvider.overrideWithValue(JamendoApi(
              client: MockClient((r) async => http.Response('{}', 200)),
              minGap: Duration.zero,
              retryDelay: Duration.zero)),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: OnlineLibraryView(
              history: src,
              onTrack: (t, {required queue}) async {},
            ),
          ),
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('the History button opens it and Back returns to the search',
        (tester) async {
      final src = FakeHistory([item(1, 'Song One')]);
      await openTab(tester, src);
      await tester.tap(find.byTooltip('History'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Song One'), findsOneWidget);
      await tester.tap(find.byTooltip('Back to search'));
      await tester.pump();
      expect(find.text('Keyword'), findsOneWidget);
    });

    testWidgets('history is reachable even before a client ID is saved', (tester) async {
      final src = FakeHistory([item(1, 'Song One')]);
      await openTab(tester, src, key: null);
      await tester.tap(find.text('History'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Song One'), findsOneWidget);
    });
  });
}
