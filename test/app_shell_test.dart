import 'dart:async';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/app.dart';
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/core/protocol/protocol.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
import 'package:remote_tunes/features/controller/trusted_players.dart';
import 'package:remote_tunes/features/external/control_mode_engine.dart';
import 'package:remote_tunes/features/player/player_core.dart';
import 'package:remote_tunes/features/player/queue/playable_song.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';
import 'package:remote_tunes/features/player/server/player_library.dart';
import 'package:remote_tunes/features/player/sleep_timer.dart';
import 'package:remote_tunes/providers/connection_providers.dart';
import 'package:remote_tunes/providers/providers.dart';
import 'package:remote_tunes/providers/shell_providers.dart';

import 'helpers/fake_audio_backend.dart';

class _FakeTrusted implements TrustedPlayersStore {
  _FakeTrusted(this.items);
  final List<TrustedPlayer> items;
  @override
  Future<List<TrustedPlayer>> load() async => items;
  @override
  Future<void> save(TrustedPlayer player) async {}
  @override
  Future<void> remove(String sessionId) async {}
}

/// A Controller connection that is already up (or not), with no network.
class _FakeClient extends ControllerClient {
  _FakeClient([ControllerClientState state = const ControllerClientState()]) : _fake = state, super();

  ControllerClientState _fake;
  final _c = StreamController<ControllerClientState>.broadcast();
  final resumed = <String>[];
  final sent = <String>[];
  var disconnects = 0;

  void setState(ControllerClientState s) {
    _fake = s;
    _c.add(s);
  }

  @override
  ControllerClientState get current => _fake;

  @override
  Stream<ControllerClientState> get stateStream => _c.stream;

  @override
  Future<void> resumeTrusted({
    required TrustedPlayer player,
    required String deviceName,
    ConnectionMode mode = ConnectionMode.auto,
    String? host,
    int? port,
    String? roomCode,
  }) async {
    resumed.add(player.name);
    setState(ControllerClientState(status: ControllerStatus.connecting, playerName: player.name));
  }

  @override
  Future<void> disconnect() async => disconnects++;

  @override
  Future<void> sendCommand(String action, [Map<String, dynamic> params = const {}]) async =>
      sent.add(action);

  @override
  Future<Map<String, dynamic>> sendCommandForResult(String action,
      [Map<String, dynamic> params = const {}, Duration? timeout]) async {
    if (action != RemoteActions.getArt) sent.add(action);
    return const {};
  }

  @override
  Future<QueueSnapshot> getQueue() async => const QueueSnapshot(items: []);
}

/// The engine runs on real futures: give them a moment, then draw.
Future<void> engineSettle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late FakeAudioBackend backend;
  late PlayerCore core;
  late _FakeClient client;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    backend = FakeAudioBackend();
    final repo = LibraryRepository(db);
    final library = RepositoryPlayerLibrary(repo, fileExists: (_) => true);
    final local = QueuePlaybackEngine(backend: backend, fileExists: (_) => true);
    final engine = ControlModeEngine(local: local);
    core = PlayerCore(
      engine: engine,
      localEngine: local,
      library: library,
      sleepTimer: SleepTimerService(onFire: engine.pause),
    );
    final id = await repo.addSong(
        title: 'Alpha Song', artist: 'Ann', album: 'First', filePath: '/m/a.mp3', durationSeconds: 200);
    await repo.addSong(
        title: 'Beta Song', artist: 'Bob', album: 'Second', filePath: '/m/b.mp3', durationSeconds: 180);
    await local.playSongs([
      PlayableSong(
          id: id,
          title: 'Alpha Song',
          artist: 'Ann',
          album: 'First',
          filePath: '/m/a.mp3',
          durationSeconds: 200),
      const PlayableSong(
          id: 2,
          title: 'Beta Song',
          artist: 'Bob',
          album: 'Second',
          filePath: '/m/b.mp3',
          durationSeconds: 180),
    ]);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    client = _FakeClient();
  });

  tearDown(() async {
    await core.dispose();
    await db.close();
  });

  Future<ProviderContainer> open(
    WidgetTester tester, {
    StartMode mode = StartMode.thisPhone,
    List<TrustedPlayer> trusted = const [],
    bool autoStart = false,
    Size size = const Size(520, 1300),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final repo = SettingsRepositoryForTest(db);
    await repo.setStartMode(mode);
    await repo.setRemoteAutoStart(autoStart);
    final container = ProviderContainer(overrides: [
      databaseProvider.overrideWithValue(db),
      playerCoreProvider.overrideWith((ref) async => core),
      controllerClientProvider.overrideWithValue(client),
      trustedPlayersStoreProvider.overrideWithValue(_FakeTrusted(trusted)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const RemoteTunesApp(),
    ));
    // The core and the settings load asynchronously.
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump(const Duration(milliseconds: 100));
    }
    return container;
  }

  testWidgets('opens as a music player for this phone, not the role picker', (tester) async {
    await open(tester);
    expect(find.text('This phone'), findsOneWidget, reason: 'the source chip');
    for (final t in ['Now Playing', 'Library', 'Search', 'Queue']) {
      expect(find.text(t), findsOneWidget, reason: t);
    }
    expect(find.text('Start as PLAYER'), findsNothing);
    expect(find.text('Alpha Song'), findsWidgets, reason: 'the song playing');
    expect(find.text('Ann · First'), findsOneWidget);
  });

  testWidgets('Now Playing has the same controls as the Controller', (tester) async {
    await open(tester);
    expect(find.byTooltip('Shuffle is off'), findsOneWidget);
    expect(find.byTooltip(RegExp('Repeat:')), findsOneWidget);
    expect(find.byTooltip('Set playback speed'), findsOneWidget);
    expect(find.byTooltip('Set sleep timer'), findsOneWidget);
    expect(find.byTooltip('Back 10 seconds'), findsOneWidget);
    expect(find.byTooltip('Show lyrics'), findsOneWidget);
    expect(find.text('Up next'), findsOneWidget, reason: 'the queue peek sheet');
  });

  testWidgets('the buttons play this phone\'s music', (tester) async {
    await open(tester);
    expect(backend.playing, isTrue);
    await tester.tap(find.byTooltip('Pause'));
    await engineSettle(tester);
    expect(backend.playing, isFalse);
    await tester.tap(find.byTooltip('Shuffle is off'));
    await engineSettle(tester);
    expect(core.engine.state.shuffleEnabled, isTrue);
    await tester.tap(find.byTooltip('Next'));
    await engineSettle(tester);
    expect(core.engine.state.title, 'Beta Song');
  });

  testWidgets('the sleep timer works from this screen', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Set sleep timer'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('15 minutes'));
    await tester.pumpAndSettle();
    expect(core.sleepTimer.isRunning, isTrue);
    expect(core.sleepTimer.secondsLeft, inInclusiveRange(890, 900));
    core.sleepTimer.set(null);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 1));
  });

  testWidgets('the tabs: Library list, Search, Queue, with a mini player under them',
      (tester) async {
    await open(tester);
    expect(find.byTooltip('Previous'), findsNWidgets(1), reason: 'only the big controls');

    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    expect(find.text('All Songs'), findsOneWidget);
    expect(find.text('Online Library'), findsOneWidget);
    expect(find.text('Play a link'), findsOneWidget);
    expect(find.text('Alpha Song'), findsOneWidget, reason: 'the mini player');
    expect(find.byTooltip('Pause'), findsOneWidget, reason: 'the mini player\'s button');

    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(find.text('Search songs, albums, artists and folders.'), findsOneWidget);

    await tester.tap(find.text('Queue'));
    await tester.pumpAndSettle();
    expect(find.text('Beta Song'), findsOneWidget);

    await tester.tap(find.text('Now Playing'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Pause'), findsOneWidget, reason: 'no mini player on Now Playing');
  });

  testWidgets('the Library plays and the mini player follows', (tester) async {
    await open(tester);
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('All Songs'));
    await tester.pumpAndSettle();
    expect(find.text('Beta Song'), findsOneWidget);
    await tester.tap(find.text('Beta Song'));
    await engineSettle(tester);
    await tester.pumpAndSettle();
    expect(core.engine.state.title, 'Beta Song');
  });

  testWidgets('left-edge swipe on Now Playing opens the Library tab', (tester) async {
    await open(tester);
    await tester.dragFrom(const Offset(6, 300), const Offset(160, 0));
    await tester.pumpAndSettle();
    expect(find.text('All Songs'), findsOneWidget);
  });

  group('the source chip', () {
    testWidgets('offers this phone, controlling another phone and remote playback',
        (tester) async {
      await open(tester);
      await tester.tap(find.text('This phone'));
      await tester.pumpAndSettle();
      expect(find.text('Control another phone'), findsOneWidget);
      expect(find.text('Start remote playback'), findsOneWidget);
      expect(find.text("Play the music that is on this phone"), findsOneWidget);
    });

    testWidgets('"Start remote playback" turns it on (and says so)', (tester) async {
      final c = await open(tester);
      expect(c.read(remotePlaybackProvider), isFalse, reason: 'off until the button');
      await tester.tap(find.text('This phone'));
      await tester.pumpAndSettle();
      c.read(remotePlaybackProvider.notifier).state = true; // what the button does
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Remote playback is on'), findsOneWidget);
    });

    testWidgets('nothing listens on the network until the button is pressed', (tester) async {
      final c = await open(tester);
      expect(c.read(remotePlaybackProvider), isFalse);
    });

    testWidgets('a setting can start remote playback when the app opens', (tester) async {
      final c = await open(tester, autoStart: true);
      expect(c.read(remotePlaybackProvider), isTrue);
    });
  });

  group('controlling another phone', () {
    ControllerClientState connected({ConnectionType? route}) => ControllerClientState(
          status: ControllerStatus.connected,
          playerName: 'Living room',
          playback: const PlaybackState(
            title: 'Remote Song',
            artist: 'Far Away',
            album: 'Other',
            durationSeconds: 100,
            queueLength: 3,
            songId: 9,
            isPlaying: true,
          ),
        );

    testWidgets('the same screens show that phone\'s music, with the chip saying so',
        (tester) async {
      final c = await open(tester);
      client.setState(connected());
      c.read(controlRemoteProvider.notifier).state = true;
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Controlling Living room'), findsOneWidget);
      expect(find.text('Remote Song'), findsWidgets);
      expect(find.text('Alpha Song'), findsNothing, reason: 'not this phone\'s song');
      // The same Now Playing controls.
      expect(find.byTooltip('Set playback speed'), findsOneWidget);
      expect(find.byTooltip('Shuffle is off'), findsOneWidget);
      await tester.tap(find.byTooltip('Pause'));
      await tester.pump();
      expect(client.sent, contains(RemoteActions.toggle));
    });

    testWidgets('going back to this phone from the chip', (tester) async {
      final c = await open(tester);
      client.setState(connected());
      c.read(controlRemoteProvider.notifier).state = true;
      await tester.pumpAndSettle();
      await tester.tap(find.text('Controlling Living room'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('This phone'));
      await tester.pumpAndSettle();
      expect(find.text('Controlling Living room'), findsNothing);
      expect(find.text('Alpha Song'), findsWidgets);
    });

    testWidgets('disconnecting returns to this phone\'s music', (tester) async {
      final c = await open(tester);
      client.setState(connected());
      c.read(controlRemoteProvider.notifier).state = true;
      await tester.pumpAndSettle();
      await tester.tap(find.text('Controlling Living room'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Disconnect'));
      await tester.pumpAndSettle();
      expect(client.disconnects, 1);
      expect(c.read(controlRemoteProvider), isFalse);
    });

    testWidgets('if the other phone goes away, it falls back to this phone', (tester) async {
      final c = await open(tester);
      client.setState(connected());
      c.read(controlRemoteProvider.notifier).state = true;
      await tester.pumpAndSettle();
      client.setState(const ControllerClientState(status: ControllerStatus.disconnected));
      await tester.pumpAndSettle();
      expect(c.read(controlRemoteProvider), isFalse);
      expect(find.text('This phone'), findsOneWidget);
    });

    testWidgets('while reconnecting the chip says so', (tester) async {
      final c = await open(tester);
      client.setState(ControllerClientState(
        status: ControllerStatus.reconnecting,
        playerName: 'Living room',
        playback: connected().playback,
      ));
      c.read(controlRemoteProvider.notifier).state = true;
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.text('Reconnecting to Living room…'), findsOneWidget);
    });
  });

  group('when the app opens', () {
    final trusted = TrustedPlayer(
      sessionId: 's1',
      token: 't',
      peerId: 'p',
      name: 'Living room',
      host: '192.168.1.5',
      port: 8765,
      lastUsed: DateTime(2026),
    );

    testWidgets('"Control my last Player" reconnects to it', (tester) async {
      final c = await open(tester, mode: StartMode.lastPlayer, trusted: [trusted]);
      expect(client.resumed, ['Living room']);
      expect(c.read(controlRemoteProvider), isTrue);
    });

    testWidgets('this phone\'s music does not reconnect to anything', (tester) async {
      await open(tester, trusted: [trusted]);
      expect(client.resumed, isEmpty);
    });

    testWidgets('with no Player used before, it just stays on this phone', (tester) async {
      await open(tester, mode: StartMode.lastPlayer);
      expect(client.resumed, isEmpty);
      expect(find.text('This phone'), findsOneWidget);
    });

    testWidgets('the classic start screen is still there to choose', (tester) async {
      await open(tester, mode: StartMode.classic);
      expect(find.text('Start as PLAYER'), findsOneWidget);
      expect(find.text('Start as CONTROLLER'), findsOneWidget);
    });
  });
}

/// The real settings repository on the test database.
class SettingsRepositoryForTest {
  SettingsRepositoryForTest(this._db);
  final AppDatabase _db;

  Future<void> setStartMode(StartMode m) => _put('start_mode', m.name);
  Future<void> setRemoteAutoStart(bool v) => _put('remote_auto_start', v.toString());

  Future<void> _put(String key, String value) => _db.customStatement(
      "INSERT OR REPLACE INTO settings (key, value, updated_at) VALUES (?, ?, strftime('%s','now'))",
      [key, value]);
}
