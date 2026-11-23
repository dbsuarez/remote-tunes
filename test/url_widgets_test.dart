import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/constants.dart';
import 'package:remote_tunes/core/protocol/protocol.dart';
import 'package:remote_tunes/core/widgets/playback_widgets.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
import 'package:remote_tunes/features/music/url_player_view.dart';
import 'package:remote_tunes/features/player/playback_engine.dart';
import 'package:remote_tunes/providers/recent_links.dart';

/// In-memory recent links (Drift does not run inside testWidgets).
class FakeRecentUrls implements RecentLinksStore {
  FakeRecentUrls([List<RecentLink>? initial]) : _rows = initial ?? [];

  final List<RecentLink> _rows;
  final _controller = StreamController<List<RecentLink>>.broadcast();
  final remembered = <String>[];
  int _nextId = 100;

  @override
  Stream<List<RecentLink>> watch() async* {
    yield List.of(_rows);
    yield* _controller.stream;
  }

  void _push() => _controller.add(List.of(_rows));

  @override
  Future<void> remember(String url, {String? title}) async {
    remembered.add(url);
    _rows.removeWhere((r) => r.url == url);
    _rows.insert(0, RecentLink(id: _nextId++, url: url, title: title));
    _push();
  }

  @override
  Future<void> remove(int id) async {
    _rows.removeWhere((r) => r.id == id);
    _push();
  }

  @override
  Future<void> clear() async {
    _rows.clear();
    _push();
  }
}

RecentLink recent(int id, String url, {String? title}) =>
    RecentLink(id: id, url: url, title: title);

Widget host(Widget child, FakeRecentUrls recents) => ProviderScope(
      overrides: [recentLinksStoreProvider.overrideWithValue(recents)],
      child: MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: Scaffold(body: child),
      ),
    );

Future<void> settleUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
}

Finder get urlField => find.widgetWithText(TextField, 'Link to an audio file');

void main() {
  group('UrlPlayerView', () {
    testWidgets('explains the internet requirement and what links work', (tester) async {
      await tester.pumpWidget(host(
          UrlPlayerView(onPlay: (_, __) async {}, target: 'the Player'),
          FakeRecentUrls()));
      await settleUi(tester);
      expect(find.textContaining('needs an internet connection'), findsOneWidget);
      expect(find.textContaining('plays on the Player'), findsOneWidget);
      expect(find.textContaining('keeps working offline'), findsOneWidget);
      expect(find.textContaining('direct link'), findsOneWidget);
    });

    testWidgets('invalid input shows why and does not call the Player', (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(host(
          UrlPlayerView(onPlay: (u, t) async => calls.add(u)), FakeRecentUrls()));
      await settleUi(tester);

      await tester.tap(find.text('Play'));
      await settleUi(tester);
      expect(find.text('Paste a link to an audio file.'), findsOneWidget);

      await tester.enterText(urlField, 'ftp://example.com/a.mp3');
      await tester.tap(find.text('Play'));
      await settleUi(tester);
      expect(find.textContaining('http://'), findsWidgets);
      expect(calls, isEmpty);

      // The message clears as soon as the user edits the field.
      await tester.enterText(urlField, 'https://example.com/a.mp3');
      await settleUi(tester);
      expect(find.textContaining('Only http'), findsNothing);
    });

    testWidgets('a valid link is sent, remembered and confirmed', (tester) async {
      final calls = <(String, String?)>[];
      final recents = FakeRecentUrls();
      await tester.pumpWidget(host(
          UrlPlayerView(
              target: 'the Player', onPlay: (u, t) async => calls.add((u, t))),
          recents));
      await settleUi(tester);

      await tester.enterText(urlField, '  https://example.com/Song.mp3  ');
      await tester.enterText(find.widgetWithText(TextField, 'Name (optional)'), 'My tune');
      await tester.tap(find.text('Play'));
      await settleUi(tester);

      expect(calls.single, ('https://example.com/Song.mp3', 'My tune'));
      expect(recents.remembered, ['https://example.com/Song.mp3']);
      expect(find.text('Playing on the Player'), findsOneWidget);
      // It now shows up under "Recent links".
      expect(find.text('Recent links'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'My tune'), findsOneWidget);
    });

    testWidgets('can be pre-filled with the test MP3, and Play sends it as is',
        (tester) async {
      final calls = <String>[];
      await tester.pumpWidget(host(
          UrlPlayerView(
            initialUrl: AppConstants.sampleAudioUrl,
            onPlay: (u, t) async => calls.add(u),
          ),
          FakeRecentUrls()));
      await settleUi(tester);

      expect(find.text(AppConstants.sampleAudioUrl), findsOneWidget);
      expect(find.textContaining('Pre-filled with a test MP3'), findsOneWidget);

      await tester.tap(find.text('Play'));
      await settleUi(tester);
      expect(calls, [AppConstants.sampleAudioUrl]);

      // Editing the box removes the "pre-filled" note.
      await tester.enterText(urlField, 'https://example.com/mine.mp3');
      await settleUi(tester);
      expect(find.textContaining('Pre-filled with a test MP3'), findsNothing);
    });

    testWidgets('is empty by default (no surprise link)', (tester) async {
      await tester.pumpWidget(host(
          UrlPlayerView(onPlay: (_, __) async {}), FakeRecentUrls()));
      await settleUi(tester);
      expect(tester.widget<TextField>(urlField).controller!.text, isEmpty);
      expect(find.textContaining('Pre-filled with a test MP3'), findsNothing);
    });

    testWidgets('no name given: the title is left for the Player to guess', (tester) async {
      String? sentTitle = 'unset';
      await tester.pumpWidget(host(
          UrlPlayerView(onPlay: (u, t) async => sentTitle = t), FakeRecentUrls()));
      await settleUi(tester);
      await tester.enterText(urlField, 'https://example.com/a.mp3');
      await tester.tap(find.text('Play'));
      await settleUi(tester);
      expect(sentTitle, isNull);
    });

    testWidgets('a failure from the Player is shown in plain words and not remembered',
        (tester) async {
      final recents = FakeRecentUrls();
      await tester.pumpWidget(host(
          UrlPlayerView(onPlay: (u, t) async {
            throw PlaybackException(ErrorCodes.urlUnreachable,
                "The Player couldn't reach that website. Check its internet connection.");
          }),
          recents));
      await settleUi(tester);
      await tester.enterText(urlField, 'https://example.com/a.mp3');
      await tester.tap(find.text('Play'));
      await settleUi(tester);

      expect(find.textContaining("couldn't reach that website"), findsOneWidget);
      expect(recents.remembered, isEmpty);
      // Usable again: the button is back to "Play".
      expect(find.text('Play'), findsOneWidget);
    });

    testWidgets('a Controller error is shown as its message', (tester) async {
      await tester.pumpWidget(host(
          UrlPlayerView(onPlay: (u, t) async {
            throw ControllerException('Not connected to a Player.');
          }),
          FakeRecentUrls()));
      await settleUi(tester);
      await tester.enterText(urlField, 'https://example.com/a.mp3');
      await tester.tap(find.text('Play'));
      await settleUi(tester);
      expect(find.text('Not connected to a Player.'), findsOneWidget);
    });

    testWidgets('an unexpected error never leaks technical details', (tester) async {
      await tester.pumpWidget(host(
          UrlPlayerView(onPlay: (u, t) async => throw StateError('secret internals')),
          FakeRecentUrls()));
      await settleUi(tester);
      await tester.enterText(urlField, 'https://example.com/a.mp3');
      await tester.tap(find.text('Play'));
      await settleUi(tester);
      expect(find.text('Something went wrong. Please try again.'), findsOneWidget);
      expect(find.textContaining('secret'), findsNothing);
    });

    testWidgets('while checking, the form is locked and says so', (tester) async {
      final gate = Completer<void>();
      var calls = 0;
      await tester.pumpWidget(host(
          UrlPlayerView(onPlay: (u, t) async {
            calls++;
            await gate.future;
          }),
          FakeRecentUrls()));
      await settleUi(tester);
      await tester.enterText(urlField, 'https://example.com/a.mp3');
      await tester.tap(find.text('Play'));
      await tester.pump();

      expect(find.text('Checking the link…'), findsOneWidget);
      // A second tap does nothing.
      await tester.tap(find.text('Checking the link…'), warnIfMissed: false);
      await tester.pump();
      expect(calls, 1);

      gate.complete();
      await settleUi(tester);
      expect(find.text('Play'), findsOneWidget);
    });

    testWidgets('tapping a recent link plays it; X removes it; Clear empties the list',
        (tester) async {
      final calls = <(String, String?)>[];
      final recents = FakeRecentUrls([
        recent(1, 'https://a.example/one.mp3', title: 'First'),
        recent(2, 'https://a.example/two.mp3'),
      ]);
      await tester.pumpWidget(host(
          UrlPlayerView(onPlay: (u, t) async => calls.add((u, t))), recents));
      await settleUi(tester);

      expect(find.text('First'), findsOneWidget);
      expect(find.text('two'), findsOneWidget, reason: 'title guessed from the link');

      await tester.tap(find.text('First'));
      await settleUi(tester);
      expect(calls.single, ('https://a.example/one.mp3', 'First'));

      await tester.tap(find.byTooltip('Remove').last);
      await settleUi(tester);
      expect(find.text('two'), findsNothing);

      await tester.tap(find.text('Clear'));
      await settleUi(tester);
      expect(find.text('Recent links'), findsNothing);
    });

    testWidgets('Paste fills the field from the clipboard', (tester) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? <String, dynamic>{'text': ' https://example.com/pasted.mp3 '}
            : null,
      );
      addTearDown(() => tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));

      await tester.pumpWidget(host(
          UrlPlayerView(onPlay: (_, __) async {}), FakeRecentUrls()));
      await settleUi(tester);
      await tester.tap(find.byTooltip('Paste'));
      await settleUi(tester);
      expect(find.text('https://example.com/pasted.mp3'), findsOneWidget);
    });

    testWidgets('disabled while reconnecting', (tester) async {
      var calls = 0;
      await tester.pumpWidget(host(
          UrlPlayerView(enabled: false, onPlay: (_, __) async => calls++),
          FakeRecentUrls()));
      await settleUi(tester);
      await tester.tap(find.text('Play'), warnIfMissed: false);
      await settleUi(tester);
      expect(calls, 0);
    });
  });

  group('NowPlayingCard with internet audio', () {
    Widget card(PlaybackState s, {void Function(int)? onSeek}) => MaterialApp(
          theme: ThemeData.dark(useMaterial3: true),
          home: Scaffold(body: NowPlayingCard(state: s, onSeek: onSeek ?? (_) {})),
        );

    testWidgets('labels internet audio instead of "track x of y"', (tester) async {
      await tester.pumpWidget(card(const PlaybackState(
          title: 'Radio', source: 'url', queueLength: 1, durationSeconds: 200)));
      expect(find.text('Internet audio'), findsOneWidget);
      expect(find.textContaining('Track 1 of 1'), findsNothing);
    });

    testWidgets('local songs still show their queue position', (tester) async {
      await tester.pumpWidget(card(const PlaybackState(
          title: 'Song', source: 'local_file', queueLength: 3, queueIndex: 1)));
      expect(find.text('Track 2 of 3'), findsOneWidget);
      expect(find.text('Internet audio'), findsNothing);
    });

    testWidgets('shows that the stream is opening', (tester) async {
      await tester.pumpWidget(card(const PlaybackState(
          title: 'Radio', source: 'url', isLoading: true)));
      expect(find.text('Opening the stream…'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
    });

    testWidgets('shows a playback error', (tester) async {
      await tester.pumpWidget(card(const PlaybackState(
          title: 'Radio', source: 'url', error: 'Playback stopped. Connection dropped.')));
      expect(find.text('Playback stopped. Connection dropped.'), findsOneWidget);
    });

    testWidgets('cannot seek in a stream with no known length', (tester) async {
      await tester.pumpWidget(card(const PlaybackState(
          title: 'Live', source: 'url', durationSeconds: 0)));
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNull);

      await tester.pumpWidget(card(const PlaybackState(
          title: 'Song', source: 'local_file', durationSeconds: 200)));
      expect(tester.widget<Slider>(find.byType(Slider)).onChanged, isNotNull);
    });
  });
}
