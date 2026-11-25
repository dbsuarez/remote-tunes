import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/settings_repository.dart';
import 'package:remote_tunes/features/shell/app_drawer.dart';
import 'package:remote_tunes/features/update/update_controller.dart';
import 'package:remote_tunes/features/update/update_service.dart';
import 'package:remote_tunes/features/update/update_widgets.dart';
import 'package:remote_tunes/providers/providers.dart';

class _Native implements UpdateNative {
  _Native(this.me);
  final ({String version, int build, String abi})? me;
  @override
  Future<({String version, int build, String abi})?> info() async => me;
  @override
  Future<bool> canInstall() async => true;
  @override
  Future<void> openInstallSettings() async {}
  @override
  Future<void> install(String path) async {}
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  test('the version reads the way it is shown', () {
    const app = InstalledApp('1.0.0', 57, 'arm64-v8a');
    expect(app.label, '1.0.0');
    expect(app.long, 'Version 1.0.0 (build 57)');
    expect(app.short, '1.0.0 (build 57)');
  });

  group('where the version is shown', () {
    late AppDatabase db;
    setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
    tearDown(() => db.close());

    Widget scope(Widget child, {({String version, int build, String abi})? me}) => ProviderScope(
          overrides: [
            databaseProvider.overrideWithValue(db),
            updateNativeProvider.overrideWithValue(_Native(me)),
          ],
          child: MaterialApp(home: Scaffold(body: child)),
        );

    testWidgets('Settings > App updates always says which version is installed', (tester) async {
      await tester.pumpWidget(scope(
        UpdateSettingsTiles(settings: const AppSettings()),
        me: (version: '1.0.0', build: 57, abi: 'arm64-v8a'),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('RemoteTunes 1.0.0'), findsOneWidget);
      expect(find.textContaining('Version 1.0.0 (build 57)'), findsOneWidget);
    });

    testWidgets('where it cannot be read it says so, not a made-up number', (tester) async {
      await tester.pumpWidget(scope(UpdateSettingsTiles(settings: const AppSettings())));
      await tester.pump();
      await tester.pump();
      expect(find.text('RemoteTunes'), findsOneWidget);
      expect(find.textContaining('0.1.0'), findsNothing);
    });
  });

  group('the menu', () {
    Widget drawer({String? version, bool update = false}) {
      void nop() {}
      return MaterialApp(
        home: Scaffold(
          drawer: AppDrawer(
            version: version,
            updateAvailable: update,
            onNowPlaying: nop,
            onLyrics: nop,
            onLibrary: nop,
            onPlaylists: nop,
            onSearch: nop,
            onQueue: nop,
            onEqualizer: nop,
            onRemotePlayback: nop,
            onSettings: nop,
            onChangelog: nop,
            onHelp: nop,
          ),
          body: const SizedBox(),
        ),
      );
    }

    Future<void> openMenu(WidgetTester tester) async {
      tester.state<ScaffoldState>(find.byType(Scaffold)).openDrawer();
      await tester.pumpAndSettle();
    }

    testWidgets('shows the installed version under the name', (tester) async {
      await tester.pumpWidget(drawer(version: '1.0.0'));
      await openMenu(tester);
      expect(find.text('Version 1.0.0'), findsOneWidget);
      expect(find.byKey(const Key('drawer-update')), findsNothing);
    });

    testWidgets('says when a newer version is available', (tester) async {
      await tester.pumpWidget(drawer(version: '1.0.0', update: true));
      await openMenu(tester);
      expect(find.text('A new version is available'), findsOneWidget);
    });

    testWidgets('shows no version when it is not known', (tester) async {
      await tester.pumpWidget(drawer());
      await openMenu(tester);
      expect(find.byKey(const Key('drawer-version')), findsNothing);
    });
  });
}
