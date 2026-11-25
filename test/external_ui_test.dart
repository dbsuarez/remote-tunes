import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/features/controller/controller_views.dart';
import 'package:remote_tunes/core/theme/app_theme.dart';
import 'package:remote_tunes/providers/shell_providers.dart';
import 'package:remote_tunes/core/router/app_router.dart';
import 'package:remote_tunes/app.dart';
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/core/protocol/protocol.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/settings_repository.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
import 'package:remote_tunes/features/controller/discovery.dart';
import 'package:remote_tunes/features/external/control_mode_engine.dart';
import 'package:remote_tunes/features/external/external_app_engine.dart';
import 'package:remote_tunes/features/external/external_media.dart';
import 'package:remote_tunes/features/player/player_host.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';
import 'package:remote_tunes/features/player/server/player_server.dart';
import 'package:remote_tunes/providers/connection_providers.dart';
import 'package:remote_tunes/providers/providers.dart';

import 'helpers/fake_audio_backend.dart';
import 'helpers/fake_external_bridge.dart';

/// Settings that tests can read back (Drift does not run in testWidgets).
class FakeSettings implements SettingsRepository {
  FakeSettings(this.current);

  AppSettings current;
  final _controller = StreamController<AppSettings>.broadcast();
  final changes = <String>[];

  @override
  Stream<AppSettings> watch() async* {
    yield current;
    yield* _controller.stream;
  }

  @override
  Future<AppSettings> load() async => current;

  @override
  Future<void> setExternalAppControlEnabled(bool v) async {
    changes.add('external:$v');
    current = AppSettings(
      externalAppControlEnabled: v,
      deviceName: current.deviceName,
      connectionMode: current.connectionMode,
    );
    _controller.add(current);
  }

  @override
  Stream<List<PairedController>> watchConnectionHistory({int limit = 10}) =>
      Stream.value(const <PairedController>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeDiscovery implements PlayerDiscovery {
  @override
  Stream<List<DiscoveredPlayer>> discover() => Stream.value(const []);
}

/// A Controller connection that records what the screen asks of it.
class FakeClient extends ControllerClient {
  FakeClient(this._state) : super();

  ControllerClientState _state;
  final _stream = StreamController<ControllerClientState>.broadcast();
  final calls = <String>[];
  ControllerException? failModeWith;

  @override
  ControllerClientState get current => _state;

  @override
  Stream<ControllerClientState> get stateStream => _stream.stream;

  void update(ControllerClientState s) {
    _state = s;
    _stream.add(s);
  }

  @override
  Future<void> sendCommand(String action, [Map<String, dynamic> params = const {}]) async {
    calls.add(action);
  }

  @override
  Future<void> setControlMode(ControlMode mode) async {
    calls.add('mode:${mode.name}');
    final f = failModeWith;
    if (f != null) throw f;
  }

  @override
  Future<void> disconnect() async {}

  @override
  Future<void> dispose() async {}
}

/// A label inside the RemoteTunes / Other music app switch (the app title also
/// says "RemoteTunes", so look only inside the switch).
Finder segment(String label) => find.descendant(
    of: find.byType(SegmentedButton<ControlMode>), matching: find.text(label));

Future<void> settleUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  group('Settings: External app control needs informed consent', () {
    Future<FakeSettings> openSettings(WidgetTester tester, {bool on = false}) async {
      tester.view.physicalSize = const Size(800, 4500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final settings = FakeSettings(AppSettings(externalAppControlEnabled: on));
      await tester.pumpWidget(ProviderScope(
        overrides: [settingsRepositoryProvider.overrideWithValue(settings)],
        child: const RemoteTunesApp(),
      ));
      await settleUi(tester);
      await tester.tap(find.byTooltip('Settings'));
      await settleUi(tester);
      // The setting is in the group "Other phones and connection".
      await tester.tap(find.byKey(const ValueKey('group-other')));
      await settleUi(tester);
      return settings;
    }

    testWidgets('is off by default and explained', (tester) async {
      await openSettings(tester);
      final tile = tester.widget<SwitchListTile>(
          find.widgetWithText(SwitchListTile, 'External app control'));
      expect(tile.value, isFalse);
      expect(find.textContaining('Off by default'), findsOneWidget);
    });

    testWidgets('turning it on first explains Notification access', (tester) async {
      final settings = await openSettings(tester);
      await tester.tap(find.widgetWithText(SwitchListTile, 'External app control'));
      await settleUi(tester);

      expect(find.text('Control other music apps?'), findsOneWidget);
      expect(find.textContaining('"Notification access"'), findsOneWidget);
      expect(find.textContaining('does not read your notifications or messages'),
          findsOneWidget);
      expect(settings.changes, isEmpty, reason: 'nothing saved until confirmed');

      await tester.tap(find.text('Turn on'));
      await settleUi(tester);
      expect(settings.changes, ['external:true']);
      expect(
        tester
            .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'External app control'))
            .value,
        isTrue,
      );
    });

    testWidgets('"Not now" leaves it off', (tester) async {
      final settings = await openSettings(tester);
      await tester.tap(find.widgetWithText(SwitchListTile, 'External app control'));
      await settleUi(tester);
      await tester.tap(find.text('Not now'));
      await settleUi(tester);
      expect(settings.changes, isEmpty);
      expect(
        tester
            .widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'External app control'))
            .value,
        isFalse,
      );
    });

    testWidgets('turning it off needs no confirmation', (tester) async {
      final settings = await openSettings(tester, on: true);
      await tester.tap(find.widgetWithText(SwitchListTile, 'External app control'));
      await settleUi(tester);
      expect(find.text('Control other music apps?'), findsNothing);
      expect(settings.changes, ['external:false']);
    });
  });

  group('Player: External App Control card', () {
    late FakeExternalBridge bridge;
    late ControlModeEngine engine;

    Future<void> openPlayer(WidgetTester tester, {required bool optedIn}) async {
      tester.view.physicalSize = const Size(800, 4000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final local = QueuePlaybackEngine(backend: FakeAudioBackend(), fileExists: (_) => true);
      engine = ControlModeEngine(
        local: local,
        external: optedIn ? ExternalAppEngine(bridge: bridge) : null,
      );
      final server = PlayerServer(engine: engine, deviceName: 'Test');
      addTearDown(() async {
        await engine.dispose();
      });

      await tester.pumpWidget(ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(FakeSettings(const AppSettings())),
          externalMediaBridgeProvider.overrideWithValue(bridge),
          playerHostProvider
              .overrideWith((ref) async => PlayerHost(engine: engine, server: server)),
          playerServerStateProvider.overrideWith((ref) => Stream.value(const PlayerServerState(
              running: true, port: 8765, addresses: ['192.168.1.20']))),
          playerPlaybackProvider.overrideWith((ref) async* {
            yield engine.state;
            yield* engine.states;
          }),
          remotePlaybackProvider.overrideWith((ref) => true),
        ],
        child: const RemoteTunesApp(initialLocation: AppRoutes.remotePlayback),
      ));
      await settleUi(tester);
    }

    setUp(() {
      // Not playing: keeps the engine's 1-second ticker off in widget tests.
      bridge = FakeExternalBridge()
        ..snapshot = FakeExternalBridge.playing(t: FakeExternalBridge.track(isPlaying: false));
    });

    testWidgets('is not shown unless the user opted in', (tester) async {
      await openPlayer(tester, optedIn: false);
      expect(find.text('External App Control'), findsNothing);
      expect(bridge.calls, isEmpty, reason: 'no other app is ever looked at');
    });

    testWidgets('when opted in: switch, honest limits, no permission nagging '
        'if already allowed', (tester) async {
      await openPlayer(tester, optedIn: true);
      expect(find.text('External App Control'), findsOneWidget);
      expect(segment('RemoteTunes'), findsOneWidget);
      expect(segment('Other music app'), findsOneWidget);
      expect(find.textContaining('Basic controls only'), findsOneWidget);
      expect(find.textContaining('You cannot pick songs'), findsOneWidget);
      expect(find.text('Allow Notification access'), findsNothing);
    });

    testWidgets('without access: explains the permission step by step',
        (tester) async {
      bridge.accessGranted = false;
      bridge.sdk = 34;
      await openPlayer(tester, optedIn: true);
      expect(find.text('Allow Notification access'), findsOneWidget);
      expect(find.textContaining('never reads your notifications'), findsOneWidget);
      // Android 13+: the restricted-settings step for sideloaded apps.
      expect(find.textContaining('Allow restricted settings'), findsOneWidget);
      expect(find.text('Open App info'), findsOneWidget);

      await tester.tap(find.text('Allow notification access'));
      await tester.tap(find.text('Open App info'));
      await tester.pump();
      expect(bridge.calls, containsAll(['openAccessSettings', 'openAppInfo']));
    });

    testWidgets('older Android: no restricted-settings step', (tester) async {
      bridge.accessGranted = false;
      bridge.sdk = 30;
      await openPlayer(tester, optedIn: true);
      expect(find.text('Allow Notification access'), findsOneWidget);
      expect(find.textContaining('restricted settings'), findsNothing);
      expect(find.text('Open App info'), findsNothing);
    });

    testWidgets('switching without access shows the reason and stays on '
        'RemoteTunes', (tester) async {
      bridge.accessGranted = false;
      await openPlayer(tester, optedIn: true);
      await tester.tap(find.text('Other music app'));
      await settleUi(tester);
      expect(find.textContaining('Notification access is not allowed'), findsOneWidget);
      expect(engine.controlMode, ControlMode.local);
    });

    testWidgets('switching with access controls the other app and says which',
        (tester) async {
      await openPlayer(tester, optedIn: true);
      await tester.tap(find.text('Other music app'));
      await settleUi(tester);
      expect(engine.controlMode, ControlMode.external);
      expect(find.text('Controlling Spotify.'), findsOneWidget);
      // (What is playing shows on Now Playing, not on this page.)

      await tester.tap(segment('RemoteTunes'));
      // Leaving external mode awaits a stream cancel, which completes on the
      // real event loop; widget tests' fake clock needs to be told to yield.
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)));
      await settleUi(tester);
      expect(engine.controlMode, ControlMode.local);
      expect(bridge.calls, containsAllInOrder(['start', 'stop']));
      expect(find.text('Controlling Spotify.'), findsNothing);
    });

    testWidgets('with no music app playing it says what to do', (tester) async {
      bridge.snapshot = const ExternalMediaSnapshot(accessGranted: true);
      await openPlayer(tester, optedIn: true);
      await tester.tap(find.text('Other music app'));
      await settleUi(tester);
      expect(
        find.text('Waiting for a music app. Start playing something in Spotify '
            'or YouTube Music on this phone.'),
        findsOneWidget,
      );
    });
  });

  group('Controller: switching and limits', () {
    PlaybackState state({
      bool enabled = true,
      bool external = false,
      bool canSeek = true,
      bool canSkip = true,
    }) =>
        PlaybackState(
          title: 'Blue Song',
          artist: 'The Band',
          durationSeconds: 200,
          positionSeconds: 10,
          isPlaying: true,
          source: external ? 'external' : 'local_file',
          externalApp: external ? 'Spotify' : '',
          externalEnabled: enabled,
          canSeek: canSeek,
          canSkip: canSkip,
        );

    Future<FakeClient> openController(
      WidgetTester tester,
      PlaybackState playback, {
      ControllerStatus status = ControllerStatus.connected,
    }) async {
      tester.view.physicalSize = const Size(800, 4500);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final client = FakeClient(ControllerClientState(
        status: status,
        playerName: 'Living Room',
        route: ConnectionType.local,
        playback: playback,
      ));
      await tester.pumpWidget(ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(FakeSettings(const AppSettings())),
          playerDiscoveryProvider.overrideWithValue(FakeDiscovery()),
          controllerClientProvider.overrideWithValue(client),
          controllerStateProvider.overrideWith((ref) async* {
            yield client.current;
            yield* client.stateStream;
          }),
        ],
        // The connected Controller screen (the web page uses the same one).
        child: MaterialApp(
          theme: AppTheme.dark(),
          home: Scaffold(
            body: Consumer(
              builder: (context, ref, _) => ControllerDashboard(
                client: client,
                state: ref.watch(controllerStateProvider).valueOrNull ?? client.current,
              ),
            ),
          ),
        ),
      ));
      await settleUi(tester);
      return client;
    }

    testWidgets('no switch when the Player has not turned External App Control on',
        (tester) async {
      await openController(tester, state(enabled: false));
      expect(find.text('Other music app'), findsNothing);
      expect(find.text('Blue Song'), findsOneWidget);
    });

    testWidgets('the switch appears when it is on, and asks the Player to switch',
        (tester) async {
      final client = await openController(tester, state());
      expect(find.text('Other music app'), findsOneWidget);
      await tester.tap(segment('Other music app'));
      await settleUi(tester);
      expect(client.calls, ['mode:external']);
    });

    testWidgets("the Player's reason is shown if it cannot switch", (tester) async {
      final client = await openController(tester, state());
      client.failModeWith = ControllerException(
        'Notification access is not allowed on the Player. Open the Player and allow it.',
        code: ErrorCodes.permissionDenied,
      );
      await tester.tap(segment('Other music app'));
      await settleUi(tester);
      // (Home is still in the tree underneath, so the message can be drawn twice.)
      expect(find.textContaining('Notification access is not allowed'), findsWidgets);
    });

    testWidgets('while controlling another app: which app, honest limits, and the '
        'RemoteTunes-only tabs explain themselves', (tester) async {
      await openController(tester, state(external: true));
      expect(find.text('Playing in Spotify'), findsOneWidget);
      expect(find.textContaining('Basic controls only'), findsOneWidget);

      for (final tab in ['Queue', 'Library', 'URL']) {
        await tester.tap(find.text(tab));
        await settleUi(tester);
        // The neighbouring tab is preloaded, so the notice can appear twice.
        expect(find.text('Not available while controlling Spotify'), findsWidgets,
            reason: tab);
        expect(find.textContaining('switch back to RemoteTunes'), findsWidgets);
      }
    });

    testWidgets('seek and skip are disabled when the other app does not allow them',
        (tester) async {
      await openController(tester, state(external: true, canSeek: false, canSkip: false));
      expect(tester.widget<Slider>(find.byType(Slider).first).onChanged, isNull);
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.skip_next_rounded)).onPressed, isNull);
      expect(tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.skip_previous_rounded)).onPressed, isNull);
      // Play/pause still works.
      expect(
          tester
              .widget<IconButton>(find.widgetWithIcon(IconButton, Icons.pause_rounded))
              .onPressed,
          isNotNull);
    });

    testWidgets('seek and skip work when the app allows them', (tester) async {
      final client = await openController(tester, state(external: true));
      expect(tester.widget<Slider>(find.byType(Slider).first).onChanged, isNotNull);
      await tester.tap(find.byIcon(Icons.skip_next_rounded));
      await tester.pump();
      expect(client.calls, ['next']);
    });

    testWidgets('RemoteTunes mode keeps every tab', (tester) async {
      await openController(tester, state());
      await tester.tap(find.text('URL'));
      await settleUi(tester);
      expect(find.text('Not available while controlling Spotify'), findsNothing);
      expect(find.textContaining('Link to an audio file'), findsWidgets);
    });

    testWidgets('the switch is disabled while reconnecting', (tester) async {
      final client = await openController(
          tester, state(), status: ControllerStatus.reconnecting);
      await tester.tap(find.text('Other music app'), warnIfMissed: false);
      await settleUi(tester);
      expect(client.calls, isEmpty);
    });
  });
}
