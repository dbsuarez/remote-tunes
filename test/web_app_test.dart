import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/core/pairing_qr.dart';
import 'package:remote_tunes/core/protocol/protocol.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
import 'package:remote_tunes/providers/recent_links.dart';
import 'package:remote_tunes/web/web_app.dart';
import 'package:remote_tunes/web/web_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A Controller connection that records what the web page asks of it.
class FakeWebClient extends ControllerClient {
  FakeWebClient() : super();

  ControllerClientState _state = const ControllerClientState();
  ControllerSession? fakeSaved;
  final _stream = StreamController<ControllerClientState>.broadcast();
  final calls = <String>[];
  String? lastRoom;
  String? lastName;
  ConnectionMode? lastMode;
  String? lastTicket;
  ControllerSession? resumedWith;
  Completer<void>? resumeGate;

  @override
  ControllerClientState get current => _state;

  @override
  Stream<ControllerClientState> get stateStream => _stream.stream;

  @override
  ControllerSession? get savedSession => fakeSaved;

  void update(ControllerClientState s) {
    _state = s;
    _stream.add(s);
  }

  @override
  Future<void> connect({
    String? host,
    int? port,
    String? roomCode,
    required String deviceName,
    ConnectionMode mode = ConnectionMode.auto,
    String? pairingTicket,
  }) async {
    calls.add('connect');
    lastRoom = roomCode;
    lastName = deviceName;
    lastMode = mode;
    lastTicket = pairingTicket;
    update(ControllerClientState(status: ControllerStatus.awaitingCode, roomCode: roomCode));
  }

  @override
  Future<void> resumeSession({
    required ControllerSession session,
    required String deviceName,
  }) async {
    calls.add('resume');
    resumedWith = session;
    update(ControllerClientState(status: ControllerStatus.connecting, roomCode: session.roomCode));
    await resumeGate?.future;
  }

  @override
  Future<void> disconnect() async {
    calls.add('disconnect');
    fakeSaved = null;
    update(const ControllerClientState());
  }

  @override
  Future<void> sendCommand(String action, [Map<String, dynamic> params = const {}]) async {
    calls.add(action);
  }

  @override
  Future<void> dispose() async {}
}

const _session = ControllerSession(
  roomCode: 'ABCD2345',
  sessionId: 'sid-1',
  token: 'secret-token',
  peerId: 'c-12345678',
  playerName: 'Living Room',
);

final withSession = <String, Object>{'rt.web.session': jsonEncode(_session.toJson())};

Future<void> settleUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  late FakeWebClient client;
  late WebStorage storage;

  Future<void> openWeb(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
    PairingQr? link,
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues(prefs);
    storage = WebStorage(await SharedPreferences.getInstance());
    client = FakeWebClient();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        webStorageProvider.overrideWithValue(storage),
        webControllerProvider.overrideWithValue(client),
        webLaunchLinkProvider.overrideWithValue(link),
        recentLinksStoreProvider.overrideWithValue(MemoryRecentLinksStore()),
      ],
      child: const WebControllerApp(),
    ));
    await settleUi(tester);
  }

  group('opened from the Player QR code', () {
    testWidgets('connects at once with the ticket, no typing', (tester) async {
      await openWeb(tester,
          link: const PairingQr(ticket: 'ABCDEFGH23', roomCode: 'ABCD2345', playerName: 'GT30 Pro'));
      expect(client.calls, ['connect']);
      expect(client.lastRoom, 'ABCD2345');
      expect(client.lastTicket, 'ABCDEFGH23');
      expect(client.lastMode, ConnectionMode.onlineOnly);
    });

    testWidgets('a fresh scan beats an old saved session', (tester) async {
      await openWeb(tester,
          prefs: withSession,
          link: const PairingQr(ticket: 'ABCDEFGH23', roomCode: 'WXYZ2345'));
      expect(client.calls, ['connect'], reason: 'it does not resume the old one');
      expect(client.lastRoom, 'WXYZ2345');
    });

    testWidgets('a Player that is not online is explained, not a blank page',
        (tester) async {
      await openWeb(tester,
          link: const PairingQr(ticket: 'ABCDEFGH23', host: '192.168.1.20', port: 8765));
      expect(client.calls, isEmpty);
      expect(find.textContaining('not online'), findsOneWidget);
    });
  });

  group('connect page', () {
    testWidgets('explains what to do and shows no recent rooms at first', (tester) async {
      await openWeb(tester);
      expect(find.text('RemoteTunes Web'), findsOneWidget);
      expect(find.text('Control your Player from this browser'), findsOneWidget);
      expect(find.textContaining('never leaves the Player'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Room code'), findsOneWidget);
      expect(find.text('Connect to Player'), findsOneWidget);
      expect(find.text('Recent rooms'), findsNothing);
      expect(client.calls, isEmpty, reason: 'nothing connects until asked');
    });

    testWidgets('checks the room code before connecting, in plain words', (tester) async {
      await openWeb(tester);
      await tester.tap(find.text('Connect to Player'));
      await settleUi(tester);
      expect(find.text('Enter the room code shown on the Player.'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Room code'), 'ABC');
      await tester.tap(find.text('Connect to Player'));
      await settleUi(tester);
      expect(find.textContaining('8 letters and numbers'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Room code'), 'ABCD-2340');
      await tester.tap(find.text('Connect to Player'));
      await settleUi(tester);
      expect(find.textContaining('never used'), findsOneWidget);
      expect(client.calls, isEmpty);
    });

    testWidgets('connects online-only with a cleaned-up code and remembers the '
        'name', (tester) async {
      await openWeb(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Room code'), ' abcd 2345 ');
      await tester.enterText(
          find.widgetWithText(TextField, 'Your name (shown on the Player)'), 'Sam Laptop');
      await tester.tap(find.text('Connect to Player'));
      await settleUi(tester);

      expect(client.lastRoom, 'ABCD2345');
      expect(client.lastName, 'Sam Laptop');
      expect(client.lastMode, ConnectionMode.onlineOnly,
          reason: 'browsers cannot reach a phone on the local network');
      expect(storage.deviceName, 'Sam Laptop');
      // Next stop: the pairing code (the Player shows it).
      expect(find.textContaining('Pair with'), findsOneWidget);
    });

    testWidgets('an empty name falls back to the default', (tester) async {
      await openWeb(tester);
      await tester.enterText(find.widgetWithText(TextField, 'Room code'), 'ABCD2345');
      await tester.enterText(
          find.widgetWithText(TextField, 'Your name (shown on the Player)'), '   ');
      await tester.tap(find.text('Connect to Player'));
      await settleUi(tester);
      expect(client.lastName, 'Web Controller');
    });

    testWidgets("a failed attempt shows the reason on the page", (tester) async {
      await openWeb(tester);
      client.update(const ControllerClientState(
        message: "Couldn't connect to the online relay. Check the internet connection.",
      ));
      await settleUi(tester);
      expect(find.textContaining("Couldn't connect to the online relay"), findsOneWidget);
      expect(find.text('Connect to Player'), findsOneWidget);
    });
  });

  group('recent rooms', () {
    final prefs = <String, Object>{
      'rt.web.recent_rooms': jsonEncode([
        {'code': 'ABCD2345', 'playerName': 'Living Room'},
        {'code': 'WXYZ6789'},
      ]),
    };

    testWidgets('are listed with the Player name, tap to connect', (tester) async {
      await openWeb(tester, prefs: prefs);
      expect(find.text('Recent rooms'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'ABCD-2345'), findsOneWidget);
      expect(find.text('Living Room'), findsOneWidget);
      expect(find.widgetWithText(ListTile, 'WXYZ-6789'), findsOneWidget);
      expect(find.text('Player'), findsOneWidget, reason: 'name unknown');

      await tester.tap(find.widgetWithText(ListTile, 'ABCD-2345'));
      await settleUi(tester);
      expect(client.lastRoom, 'ABCD2345');
    });

    testWidgets('can be forgotten', (tester) async {
      await openWeb(tester, prefs: prefs);
      await tester.tap(find.byTooltip('Forget this room').first);
      await settleUi(tester);
      expect(find.widgetWithText(ListTile, 'ABCD-2345'), findsNothing);
      expect(find.widgetWithText(ListTile, 'WXYZ-6789'), findsOneWidget);
      expect(storage.loadRooms().map((r) => r.code), ['WXYZ6789']);
    });
  });

  group('reloading the page', () {

    testWidgets('resumes the saved session instead of asking for a code', (tester) async {
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      SharedPreferences.setMockInitialValues(withSession);
      storage = WebStorage(await SharedPreferences.getInstance());
      client = FakeWebClient()..resumeGate = Completer<void>();
      await tester.pumpWidget(ProviderScope(
        overrides: [
          webStorageProvider.overrideWithValue(storage),
          webControllerProvider.overrideWithValue(client),
          recentLinksStoreProvider.overrideWithValue(MemoryRecentLinksStore()),
        ],
        child: const WebControllerApp(),
      ));
      await settleUi(tester);

      expect(client.calls, ['resume']);
      expect(client.resumedWith!.token, 'secret-token');
      expect(client.resumedWith!.roomCode, 'ABCD2345');
      expect(find.text('Reconnecting to your Player…'), findsOneWidget);
      expect(find.text('Connect to Player'), findsNothing);

      client.fakeSaved = _session;
      client.resumeGate!.complete();
      client.update(const ControllerClientState(
        status: ControllerStatus.connected,
        playerName: 'Living Room',
        route: ConnectionType.online,
        playback: PlaybackState(title: 'Blue Song', artist: 'The Band', isPlaying: true),
      ));
      await settleUi(tester);
      expect(find.text('RemoteTunes Web · Living Room'), findsOneWidget);
      expect(find.text('Blue Song'), findsOneWidget);
      expect(find.text('Disconnect'), findsOneWidget);
    });

    testWidgets("if the Player no longer knows the session, it is forgotten and "
        'the page asks for the room code', (tester) async {
      await openWeb(tester, prefs: withSession);
      await settleUi(tester);
      expect(storage.loadSession(), isNotNull);

      client.update(const ControllerClientState(
        message: 'That saved connection is no longer valid. Enter the room code '
            'shown on the Player and pair again.',
        sessionInvalid: true,
      ));
      await settleUi(tester);
      expect(storage.loadSession(), isNull, reason: 'stale token removed');
      expect(find.textContaining('no longer valid'), findsOneWidget);
      expect(find.text('Connect to Player'), findsOneWidget);
    });

    testWidgets('a network problem keeps the saved session for the next reload',
        (tester) async {
      await openWeb(tester, prefs: withSession);
      client.update(const ControllerClientState(
        message: "Couldn't connect to the online relay. Check the internet connection.",
      ));
      await settleUi(tester);
      expect(storage.loadSession(), isNotNull);
    });

    testWidgets('damaged saved data is ignored, not a crash', (tester) async {
      await openWeb(tester, prefs: {'rt.web.session': '{not json'});
      expect(client.calls, isEmpty);
      expect(find.text('Connect to Player'), findsOneWidget);
    });
  });

  group('while connected', () {
    testWidgets('the session is saved to the browser and the room remembered',
        (tester) async {
      await openWeb(tester);
      client.fakeSaved = _session;
      client.update(const ControllerClientState(
        status: ControllerStatus.connected,
        playerName: 'Living Room',
        route: ConnectionType.online,
      ));
      await settleUi(tester);

      expect(storage.loadSession()!.token, 'secret-token');
      expect(storage.loadSession()!.peerId, 'c-12345678');
      expect(storage.loadRooms().single.code, 'ABCD2345');
      expect(storage.loadRooms().single.playerName, 'Living Room');
    });

    testWidgets('state updates do not rewrite storage over and over', (tester) async {
      await openWeb(tester);
      client.fakeSaved = _session;
      client.update(const ControllerClientState(
          status: ControllerStatus.connected, playerName: 'Living Room', route: ConnectionType.online));
      await settleUi(tester);
      // Tamper with storage; later states must not overwrite it.
      await storage.clearSession();
      for (var i = 0; i < 5; i++) {
        client.update(ControllerClientState(
          status: ControllerStatus.connected,
          playerName: 'Living Room',
          route: ConnectionType.online,
          playback: PlaybackState(positionSeconds: i),
        ));
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(storage.loadSession(), isNull);
    });

    testWidgets('shows the dashboard with all four tabs', (tester) async {
      await openWeb(tester);
      client.update(const ControllerClientState(
        status: ControllerStatus.connected,
        playerName: 'Living Room',
        route: ConnectionType.online,
      ));
      await settleUi(tester);
      for (final t in ['Now Playing', 'Queue', 'Library', 'URL']) {
        expect(find.text(t), findsWidgets, reason: t);
      }
      expect(find.textContaining('Online'), findsWidgets);
    });

    testWidgets('Disconnect forgets the saved session', (tester) async {
      await openWeb(tester);
      client.fakeSaved = _session;
      client.update(const ControllerClientState(
          status: ControllerStatus.connected, playerName: 'Living Room', route: ConnectionType.online));
      await settleUi(tester);
      expect(storage.loadSession(), isNotNull);

      await tester.tap(find.text('Disconnect'));
      await settleUi(tester);
      expect(client.calls, contains('disconnect'));
      expect(storage.loadSession(), isNull);
      expect(find.text('Connect to Player'), findsOneWidget);
    });

    testWidgets('a reconnecting banner is shown, and controls pause', (tester) async {
      await openWeb(tester);
      client.update(const ControllerClientState(
        status: ControllerStatus.reconnecting,
        playerName: 'Living Room',
        route: ConnectionType.online,
        playback: PlaybackState(title: 'Blue Song', isPlaying: true),
      ));
      await settleUi(tester);
      expect(find.textContaining('Reconnecting to Living Room'), findsOneWidget);
      expect(find.textContaining('Controls are paused'), findsOneWidget);
    });
  });

  group('WebStorage', () {
    Future<WebStorage> fresh([Map<String, Object> init = const {}]) async {
      SharedPreferences.setMockInitialValues(init);
      return WebStorage(await SharedPreferences.getInstance());
    }

    test('device name has a default and trims', () async {
      final s = await fresh();
      expect(s.deviceName, 'Web Controller');
      await s.setDeviceName('  Laptop  ');
      expect(s.deviceName, 'Laptop');
      await s.setDeviceName('   ');
      expect(s.deviceName, 'Web Controller');
    });

    test('rooms: newest first, no duplicates, capped, names kept', () async {
      final s = await fresh();
      await s.rememberRoom('AAAA2222', playerName: 'One');
      await s.rememberRoom('BBBB3333');
      await s.rememberRoom('AAAA2222'); // again, without a name
      expect(s.loadRooms().map((r) => r.code), ['AAAA2222', 'BBBB3333']);
      expect(s.loadRooms().first.playerName, 'One', reason: 'earlier name kept');

      for (var i = 0; i < 12; i++) {
        await s.rememberRoom('CCCC${(2222 + i)}');
      }
      expect(s.loadRooms().length, WebStorage.maxRooms);
      expect(s.loadRooms().first.code, 'CCCC2233');
    });

    test('damaged storage reads as empty, never throws', () async {
      final s = await fresh({
        'rt.web.recent_rooms': 'oops',
        'rt.web.recent_links': '[1,2',
        'rt.web.session': '{"roomCode":1}',
      });
      expect(s.loadRooms(), isEmpty);
      expect(s.loadLinks(), isEmpty);
      expect(s.loadSession(), isNull);
    });

    test('recent links: saved in the browser, newest first, titles kept', () async {
      final s = await fresh();
      final store = WebRecentLinksStore(s);
      await store.remember('https://a.example/1.mp3', title: 'One');
      await store.remember('https://a.example/2.mp3');
      await store.remember('https://a.example/1.mp3'); // again: moves up
      var links = await store.watch().first;
      expect(links.map((l) => l.url), ['https://a.example/1.mp3', 'https://a.example/2.mp3']);
      expect(links.first.title, 'One');

      await store.remove(links.first.id);
      links = await store.watch().first;
      expect(links.single.url, 'https://a.example/2.mp3');
      await store.clear();
      expect(await store.watch().first, isEmpty);
    });

    test('recent links are capped at 20', () async {
      final s = await fresh();
      final store = WebRecentLinksStore(s);
      for (var i = 0; i < 25; i++) {
        await store.remember('https://a.example/$i.mp3');
      }
      final links = await store.watch().first;
      expect(links.length, RecentLinksStore.maxEntries);
      expect(links.first.url, 'https://a.example/24.mp3');
    });
  });
}
