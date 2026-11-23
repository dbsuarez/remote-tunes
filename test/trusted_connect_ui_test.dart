import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/data/repositories/settings_repository.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
import 'package:remote_tunes/features/controller/controller_screen.dart';
import 'package:remote_tunes/features/controller/discovery.dart';
import 'package:remote_tunes/features/controller/trusted_players.dart';
import 'package:remote_tunes/providers/connection_providers.dart';
import 'package:remote_tunes/providers/providers.dart';

import 'external_ui_test.dart' show FakeSettings;

class _Discovery implements PlayerDiscovery {
  _Discovery(this.players);
  final List<DiscoveredPlayer> players;

  @override
  Stream<List<DiscoveredPlayer>> discover() => Stream.value(players);
}

class _Store implements TrustedPlayersStore {
  _Store(this.saved);
  final List<TrustedPlayer> saved;

  @override
  Future<List<TrustedPlayer>> load() async => List.of(saved);
  @override
  Future<void> save(TrustedPlayer p) async {}
  @override
  Future<void> remove(String sessionId) async {}
}

class _Client extends ControllerClient {
  _Client() : super();

  final calls = <String>[];
  final _stream = StreamController<ControllerClientState>.broadcast();

  @override
  ControllerClientState get current => const ControllerClientState();
  @override
  Stream<ControllerClientState> get stateStream => _stream.stream;

  @override
  Future<void> resumeTrusted({
    required TrustedPlayer player,
    required String deviceName,
    ConnectionMode mode = ConnectionMode.auto,
    String? host,
    int? port,
    String? roomCode,
  }) async =>
      calls.add('resume ${player.sessionId} ${player.host}:${player.port} '
          'room=${player.roomCode}');

  @override
  Future<void> connect({
    String? host,
    int? port,
    String? roomCode,
    required String deviceName,
    ConnectionMode mode = ConnectionMode.auto,
    String? pairingTicket,
  }) async =>
      calls.add('pair $host:$port');

  @override
  Future<void> disconnect() async {}
  @override
  Future<void> dispose() async {}
}

TrustedPlayer trusted(String id, String name, {String host = '10.0.0.5', String? room}) =>
    TrustedPlayer(
      sessionId: id,
      token: 't',
      peerId: 'c-1',
      name: name,
      host: host,
      port: 8765,
      roomCode: room,
      lastUsed: DateTime(2026, 11, 24),
    );

void main() {
  Future<_Client> open(
    WidgetTester tester, {
    required List<TrustedPlayer> saved,
    required List<DiscoveredPlayer> nearby,
  }) async {
    tester.view.physicalSize = const Size(800, 3000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final client = _Client();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        controllerClientProvider.overrideWithValue(client),
        trustedPlayersStoreProvider.overrideWithValue(_Store(saved)),
        playerDiscoveryProvider.overrideWithValue(_Discovery(nearby)),
        settingsRepositoryProvider.overrideWithValue(FakeSettings(const AppSettings())),
      ],
      child: const MaterialApp(home: ControllerScreen()),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));
    // The first saved Player is tried on its own when the screen opens.
    client.calls.clear();
    await tester.tap(find.text('Other ways to connect'));
    await tester.pumpAndSettle();
    return client;
  }

  testWidgets('picking a nearby Player we trust reconnects with no code, even renamed',
      (tester) async {
    final client = await open(
      tester,
      // Saved under its old name, same stable online room.
      saved: [trusted('s1', 'My Phone', room: '4DUQNSQS')],
      nearby: const [
        DiscoveredPlayer(
            name: 'GT30 Pro', host: '192.168.18.219', port: 8765, roomCode: '4DUQNSQS'),
      ],
    );
    await tester.tap(find.text('GT30 Pro'));
    await tester.pump();
    expect(client.calls, ['resume s1 192.168.18.219:8765 room=4DUQNSQS']);
  });

  testWidgets('a Player we do not know still goes through pairing', (tester) async {
    final client = await open(
      tester,
      saved: [trusted('s1', 'My Phone', room: '4DUQNSQS')],
      nearby: const [
        DiscoveredPlayer(name: 'Stranger', host: '10.9.9.9', port: 8765, roomCode: 'ZZZZ2222'),
      ],
    );
    await tester.tap(find.text('Stranger'));
    await tester.pump();
    expect(client.calls, ['pair 10.9.9.9:8765']);
  });

  testWidgets('matching by name needs the name to be unique', (tester) async {
    final client = await open(
      tester,
      saved: [trusted('s1', 'My Phone'), trusted('s2', 'My Phone', host: '10.0.0.6')],
      nearby: const [DiscoveredPlayer(name: 'My Phone', host: '10.9.9.9', port: 8765)],
    );
    await tester.tap(find.text('My Phone').last);
    await tester.pump();
    expect(client.calls, ['pair 10.9.9.9:8765'],
        reason: 'two saved Players share the name, so it cannot tell which');
  });
}
