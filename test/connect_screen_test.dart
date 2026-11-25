import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/router/app_router.dart';
import 'package:remote_tunes/app.dart';
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/settings_repository.dart';
import 'package:remote_tunes/features/controller/discovery.dart';
import 'package:remote_tunes/providers/connection_providers.dart';
import 'package:remote_tunes/providers/providers.dart';

/// In-memory stand-in so the widget test does not touch Drift (Drift's real
/// async work does not run inside testWidgets' fake-async zone). Drift itself
/// is covered by settings_repository_test.dart.
class _FakeSettingsRepository implements SettingsRepository {
  AppSettings _current = const AppSettings();
  final _controller = StreamController<AppSettings>.broadcast();

  @override
  Stream<AppSettings> watch() async* {
    yield _current;
    yield* _controller.stream;
  }

  @override
  Future<void> setConnectionMode(ConnectionMode v) async {
    _current = AppSettings(deviceName: _current.deviceName, connectionMode: v);
    _controller.add(_current);
  }

  @override
  Stream<List<PairedController>> watchConnectionHistory({int limit = 10}) =>
      Stream.value(const <PairedController>[]);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('Controller screen lists discovered Players and offers manual '
      'IP/port connect', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsRepositoryProvider.overrideWithValue(_FakeSettingsRepository()),
          playerDiscoveryProvider.overrideWithValue(_FakeDiscovery()),
        ],
        child: const RemoteTunesApp(initialLocation: AppRoutes.connect),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Scan QR code'), findsOneWidget);
    await tester.tap(find.text('Other ways to connect'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Nearby Players'), 300, scrollable: find.byType(Scrollable).last);
    expect(find.text('Nearby Players'), findsOneWidget);
    expect(find.text('Kitchen Phone'), findsOneWidget);
    expect(find.text('192.168.1.20:8765'), findsOneWidget);
    expect(find.text('Connect manually'), findsOneWidget);
    expect(find.text('Player IP address'), findsOneWidget);

    // Manual connect validates input before trying the network.
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Connect'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Enter the Player'), findsOneWidget);
  });
}

class _FakeDiscovery implements PlayerDiscovery {
  @override
  Stream<List<DiscoveredPlayer>> discover() => Stream.value(const [
        DiscoveredPlayer(name: 'Kitchen Phone', host: '192.168.1.20', port: 8765),
      ]);
}
