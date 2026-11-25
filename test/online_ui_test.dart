import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/router/app_router.dart';
import 'package:remote_tunes/providers/shell_providers.dart';
import 'package:remote_tunes/app.dart';
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/settings_repository.dart';
import 'package:remote_tunes/features/controller/controller_screen.dart';
import 'package:remote_tunes/features/controller/discovery.dart';
import 'package:remote_tunes/features/online/online_setup.dart';
import 'package:remote_tunes/features/online/online_status.dart';
import 'package:remote_tunes/features/player/player_host.dart';
import 'package:remote_tunes/features/player/playback_engine.dart';
import 'package:remote_tunes/features/player/server/player_server.dart';
import 'package:remote_tunes/providers/connection_providers.dart';
import 'package:remote_tunes/providers/providers.dart';

/// Settings that tests can choose (Drift does not run inside testWidgets).
class FakeSettings implements SettingsRepository {
  FakeSettings(this.current);

  AppSettings current;
  final _controller = StreamController<AppSettings>.broadcast();

  @override
  Stream<AppSettings> watch() async* {
    yield current;
    yield* _controller.stream;
  }

  @override
  Future<AppSettings> load() async => current;

  @override
  Stream<List<PairedController>> watchConnectionHistory({int limit = 10}) =>
      Stream.value(const <PairedController>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDiscovery implements PlayerDiscovery {
  FakeDiscovery([this.players = const []]);
  final List<DiscoveredPlayer> players;

  @override
  Stream<List<DiscoveredPlayer>> discover() => Stream.value(players);
}

Future<void> settleUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> openController(
  WidgetTester tester, {
  required ConnectionMode mode,
  List<DiscoveredPlayer> players = const [],
}) async {
  // A tall window so lazily built lists show every section.
  tester.view.physicalSize = const Size(800, 3000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsRepositoryProvider
          .overrideWithValue(FakeSettings(AppSettings(connectionMode: mode))),
      playerDiscoveryProvider.overrideWithValue(FakeDiscovery(players)),
    ],
    child: const RemoteTunesApp(initialLocation: AppRoutes.connect),
  ));
  await settleUi(tester);
  // The fallback ways to connect are folded away until asked for.
  await tester.tap(find.text('Other ways to connect'));
  await settleUi(tester);
}

Future<void> openPlayer(
  WidgetTester tester, {
  required PlayerServerState state,
  String? onlineProblem,
}) async {
  final engine = SimulatedPlaybackEngine(autoTick: false);
  final server = PlayerServer(engine: engine, deviceName: 'Test');
  await tester.pumpWidget(ProviderScope(
    overrides: [
      settingsRepositoryProvider.overrideWithValue(FakeSettings(const AppSettings())),
      playerHostProvider.overrideWith((ref) async => PlayerHost(
            engine: engine,
            server: server,
            onlineProblem: onlineProblem,
          )),
      playerServerStateProvider.overrideWith((ref) => Stream.value(state)),
      playerPlaybackProvider.overrideWith((ref) => Stream.value(engine.state)),
      // Remote playback is on: that page shows the connection details.
      remotePlaybackProvider.overrideWith((ref) => true),
    ],
    child: const RemoteTunesApp(initialLocation: AppRoutes.remotePlayback),
  ));
  await settleUi(tester);
}

void main() {
  group('Controller connect screen follows the connection mode', () {
    testWidgets('Auto: local section and an optional online section', (tester) async {
      await openController(tester, mode: ConnectionMode.auto);
      expect(find.text('Nearby Players'), findsOneWidget);
      expect(find.text('Connect manually'), findsOneWidget);
      expect(find.text('Online (optional)'), findsOneWidget);
      expect(find.widgetWithText(TextField, 'Room code'), findsOneWidget);
      expect(find.text('Connect online'), findsNothing,
          reason: 'online connects via the Player list or the manual button');
      expect(find.textContaining('Auto:'), findsOneWidget);
    });

    testWidgets('Local only: no online controls at all', (tester) async {
      await openController(tester, mode: ConnectionMode.localOnly);
      // (Home is still in the tree underneath, so look only inside the
      // Controller screen.)
      Finder inController(Finder f) =>
          find.descendant(of: find.byType(ControllerScreen), matching: f);
      expect(inController(find.text('Nearby Players')), findsOneWidget);
      expect(inController(find.text('Room code')), findsNothing);
      expect(inController(find.textContaining('Online')), findsNothing);
      expect(inController(find.textContaining('online')), findsNothing);
      expect(inController(find.byIcon(Icons.public_rounded)), findsNothing);
      expect(inController(find.textContaining('Local only:')), findsOneWidget);
    });

    testWidgets('Online only: just the room code, no local discovery', (tester) async {
      await openController(tester, mode: ConnectionMode.onlineOnly);
      expect(find.text('Nearby Players'), findsNothing);
      expect(find.text('Connect manually'), findsNothing);
      expect(find.text('Connect online'), findsWidgets);
      expect(find.widgetWithText(TextField, 'Room code'), findsOneWidget);
      expect(find.textContaining('Online only:'), findsOneWidget);
    });

    testWidgets('room code is checked before connecting, with plain messages',
        (tester) async {
      await openController(tester, mode: ConnectionMode.onlineOnly);
      // The heading and the button share this label; the button is last.
      final button = find.text('Connect online').last;

      await tester.tap(button);
      await settleUi(tester);
      expect(find.text('Enter the room code shown on the Player.'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Room code'), 'ABC');
      await settleUi(tester);
      expect(find.text('Enter the room code shown on the Player.'), findsNothing,
          reason: 'message clears when typing');
      await tester.tap(button);
      await settleUi(tester);
      expect(find.textContaining('8 letters and numbers'), findsOneWidget);

      await tester.enterText(find.widgetWithText(TextField, 'Room code'), 'ABCD-2340');
      await tester.tap(button);
      await settleUi(tester);
      expect(find.textContaining('never used'), findsOneWidget);
    });

    testWidgets('a valid room code attempts to connect (and says why if online '
        'is not set up)', (tester) async {
      await openController(tester, mode: ConnectionMode.onlineOnly);
      await tester.enterText(find.widgetWithText(TextField, 'Room code'), 'abcd 2345');
      await tester.tap(find.text('Connect online').last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      // Default settings have no Supabase keys: the reason is shown.
      expect(find.textContaining('online relay is turned off'), findsOneWidget);
    });

    testWidgets('a nearby Player that also advertises a room is marked', (tester) async {
      await openController(tester, mode: ConnectionMode.auto, players: const [
        DiscoveredPlayer(
            name: 'Kitchen', host: '192.168.1.20', port: 8765, roomCode: 'ABCD2345'),
        DiscoveredPlayer(name: 'Den', host: '192.168.1.21', port: 8765),
      ]);
      expect(find.text('192.168.1.20:8765 · also online'), findsOneWidget);
      expect(find.text('192.168.1.21:8765'), findsOneWidget);
    });
  });

  group('Player screen: online room', () {
    const room = 'ABCD2345';

    testWidgets('shows the room code, status and the privacy note', (tester) async {
      await openPlayer(
        tester,
        state: const PlayerServerState(
          running: true,
          port: 8765,
          addresses: ['192.168.1.20'],
          online: OnlineRelayInfo(roomCode: room, phase: OnlinePhase.connected),
        ),
      );
      expect(find.text('ABCD-2345'), findsOneWidget);
      expect(find.text('Online relay connected'), findsOneWidget);
      expect(find.byTooltip('Copy room code'), findsOneWidget);
      expect(find.textContaining('never leaves this phone'), findsOneWidget);
      // Both the local address and the room are offered (Auto).
      expect(find.text('Connect from the Controller'), findsOneWidget);
    });

    testWidgets('shows connecting, reconnecting and failed states', (tester) async {
      for (final (phase, text, error) in [
        (OnlinePhase.connecting, 'Connecting to the online relay…', null),
        (OnlinePhase.reconnecting, 'Reconnecting to the online relay…',
            'The online relay connection was lost.'),
        (OnlinePhase.failed, 'Not connected to the online relay',
            "Couldn't reach the online relay."),
      ]) {
        await openPlayer(
          tester,
          state: PlayerServerState(
            running: true,
            port: 8765,
            addresses: const ['192.168.1.20'],
            online: OnlineRelayInfo(roomCode: room, phase: phase, error: error),
          ),
        );
        expect(find.text(text), findsOneWidget, reason: '$phase');
        if (phase == OnlinePhase.failed) {
          expect(find.textContaining('Trying again automatically'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
      }
    });

    testWidgets('Online only: no local address card, online status in the pill',
        (tester) async {
      await openPlayer(
        tester,
        state: const PlayerServerState(
          running: true,
          online: OnlineRelayInfo(roomCode: room, phase: OnlinePhase.connected),
        ),
      );
      expect(find.text('Connect from the Controller'), findsNothing);
      expect(find.text('Online · waiting for a Controller'), findsOneWidget);
      expect(find.text('ABCD-2345'), findsOneWidget);
    });

    testWidgets('Online only and not set up: explains what to do', (tester) async {
      await openPlayer(
        tester,
        state: const PlayerServerState(running: true),
        onlineProblem:
            'The online relay is turned off. Turn it on in Settings → Online relay.',
      );
      expect(find.textContaining('turned off'), findsOneWidget);
      expect(find.text('Room code'), findsNothing);
    });

    testWidgets('local-only Player shows no online card', (tester) async {
      await openPlayer(
        tester,
        state: const PlayerServerState(
            running: true, port: 8765, addresses: ['192.168.1.20']),
      );
      expect(find.text('Room code'), findsNothing);
      expect(find.textContaining('online relay'), findsNothing);
    });

    testWidgets('a Controller connected online is shown in violet "Online"',
        (tester) async {
      await openPlayer(
        tester,
        state: const PlayerServerState(
          running: true,
          online: OnlineRelayInfo(roomCode: room, phase: OnlinePhase.connected),
          controller: ControllerInfo(
            name: 'Remote Phone',
            address: 'Online',
            connectionType: ConnectionType.online,
            connected: true,
          ),
        ),
      );
      expect(find.text('Controller connected: Remote Phone · Online'), findsOneWidget);
    });
  });

  group('Settings: Test online relay', () {
    Future<void> openSettings(
      WidgetTester tester,
      Future<RelayTestResult> Function(AppSettings) tester_,
    ) async {
      await tester.pumpWidget(ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(FakeSettings(
            const AppSettings(
              onlineRelayEnabled: true,
              supabaseUrl: 'https://abc.supabase.co',
              supabaseAnonKey: 'key',
            ),
          )),
          relayTesterProvider.overrideWithValue(tester_),
        ],
        child: const RemoteTunesApp(),
      ));
      await settleUi(tester);
      await tester.tap(find.byTooltip('Settings'));
      await settleUi(tester);
      // The online relay is in the group "Other phones and connection".
      await tester.tap(find.byKey(const ValueKey('group-other')));
      await settleUi(tester);
      // Home is still in the tree underneath: scroll the Settings list on top.
      await tester.dragUntilVisible(
        find.text('Test online relay'),
        find.byType(ListView).last,
        const Offset(0, -300),
      );
      await tester.pump();
    }

    testWidgets('success is shown', (tester) async {
      AppSettings? seen;
      await openSettings(tester, (s) async {
        seen = s;
        return const RelayTestResult.ok();
      });
      await tester.tap(find.text('Test online relay'));
      await settleUi(tester);
      expect(find.text('Connected to the online relay.'), findsOneWidget);
      expect(seen!.supabaseUrl, 'https://abc.supabase.co');
    });

    testWidgets('failure is explained, and the button shows progress meanwhile',
        (tester) async {
      final gate = Completer<RelayTestResult>();
      await openSettings(tester, (_) => gate.future);
      await tester.tap(find.text('Test online relay'));
      await tester.pump();
      expect(find.text('Testing…'), findsOneWidget);

      gate.complete(const RelayTestResult.failed(
          'The online relay refused the connection. Check the Supabase URL and anon key.'));
      await settleUi(tester);
      expect(find.textContaining('refused the connection'), findsOneWidget);
      expect(find.text('Test online relay'), findsOneWidget);
    });

    testWidgets('an unexpected error never leaks details', (tester) async {
      await openSettings(tester, (_) async => throw StateError('secret key leak'));
      await tester.tap(find.text('Test online relay'));
      await settleUi(tester);
      expect(find.text("Couldn't test the online relay."), findsOneWidget);
      expect(find.textContaining('secret'), findsNothing);
    });

    testWidgets('explains how to set up Supabase and what passes through it',
        (tester) async {
      await openSettings(tester, (_) async => const RelayTestResult.ok());
      expect(find.textContaining('free Supabase project'), findsOneWidget);
      expect(find.textContaining('Music, file names and paths never do'), findsOneWidget);
    });
  });
}
