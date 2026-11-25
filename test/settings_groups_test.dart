import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/features/settings/settings_screen.dart';
import 'package:remote_tunes/providers/providers.dart';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(500, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [databaseProvider.overrideWithValue(db)],
      child: const MaterialApp(home: SettingsScreen()),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// A test that lets go of the screen at the end (no timers left behind).
  void screenTest(String name, Future<void> Function(WidgetTester tester) body) {
    testWidgets(name, (tester) async {
      await body(tester);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(seconds: 1));
    });
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump(const Duration(milliseconds: 300));
  }

  screenTest('the front page is a short list of groups, not forty settings', (tester) async {
    await open(tester);
    for (final g in [
      'Playback and sound',
      'Library',
      'Look',
      'Lyrics and online',
      'Other phones and connection',
      'Updates and about',
      'Backup and restore',
    ]) {
      expect(find.text(g), findsOneWidget, reason: g);
    }
    // None of the settings themselves are on it.
    expect(find.text('Haptic feedback'), findsNothing);
    expect(find.text('Crossfade: off'), findsNothing);
    expect(find.byType(Switch), findsNothing);
  });

  screenTest('each group says what is in it', (tester) async {
    await open(tester);
    expect(find.textContaining('Crossfade off'), findsOneWidget);
    expect(find.textContaining('Skin:'), findsOneWidget);
    expect(find.textContaining('Device name:'), findsOneWidget);
  });

  screenTest('a group opens its own page with its settings', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('group-look')));
    await settle(tester);
    expect(find.text('Look'), findsWidgets);
    expect(find.text('Skins'), findsOneWidget);
    expect(find.text('Haptic feedback'), findsOneWidget);
    expect(find.text('Song list text size'), findsNothing, reason: 'the title is the label above its buttons');
    expect(find.text('Text size'), findsOneWidget);
    expect(find.text('Crossfade: off'), findsNothing, reason: 'that is in Playback');
  });

  screenTest('Playback holds crossfade, loudness, the equalizer and the visualizer',
      (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('group-playback')));
    await settle(tester);
    expect(find.text('Crossfade: off'), findsOneWidget);
    expect(find.text('Even out loudness'), findsOneWidget);
    expect(find.text('Equalizer'), findsOneWidget);
    expect(find.text('Visualizer'), findsOneWidget);
    expect(find.text('Queue opens at the song playing'), findsOneWidget);
  });

  screenTest('a setting changed on its page still works', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const ValueKey('group-look')));
    await settle(tester);
    final before = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Haptic feedback')).value;
    await tester.tap(find.widgetWithText(SwitchListTile, 'Haptic feedback'));
    await settle(tester);
    final after = tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Haptic feedback')).value;
    expect(after, !before);
  });

  screenTest('the search finds a setting by its name and shows it right there', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'crossfade');
    await tester.pump();
    expect(find.text('Crossfade: off'), findsOneWidget);
    expect(find.text('Playback and sound'), findsOneWidget, reason: 'its group is named above it');
    expect(find.text('Haptic feedback'), findsNothing);
  });

  screenTest('the search also knows other words people use', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'vibration');
    await tester.pump();
    expect(find.text('Haptic feedback'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'replay gain');
    await tester.pump();
    expect(find.text('Even out loudness'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'spotify');
    await tester.pump();
    expect(find.text('External app control'), findsOneWidget);
  });

  screenTest('every word has to match, and nothing found says so', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'crossfade haptic');
    await tester.pump();
    expect(find.text('No setting matches that.'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();
    expect(find.text('Library'), findsOneWidget);
  });

  screenTest('a found setting can be changed without leaving the search', (tester) async {
    await open(tester);
    await tester.enterText(find.byType(TextField), 'haptic');
    await tester.pump();
    await tester.tap(find.widgetWithText(SwitchListTile, 'Haptic feedback'));
    await settle(tester);
    expect(find.text('Haptic feedback'), findsOneWidget);
  });

  screenTest('Backup and restore, and every old setting, can still be reached', (tester) async {
    await open(tester);
    expect(find.byKey(const ValueKey('group-backup')), findsOneWidget);
    // Every setting of the old long page is in some group: search each by its title.
    for (final title in [
      'Default volume',
      'Repeat and shuffle',
      'Crossfade',
      'Even out loudness',
      'Equalizer',
      'Visualizer',
      'Queue opens at the song playing',
      'Find missing album art',
      'Update tags from files',
      'Excluded from library',
      'Reset play and skip counts',
      'All files access',
      'Skins',
      'Song list text size',
      'Haptic feedback',
      'Colors from album art',
      'Lyrics from the internet',
      'Suggestions in the Online Library',
      'Device name',
      'When the app opens',
      'Connection mode',
      'Online relay',
      'External app control',
      'Player port',
      'App updates',
      'Diagnostics',
    ]) {
      await tester.enterText(find.byType(TextField).first, title);
      await tester.pump();
      expect(find.text('No setting matches that.'), findsNothing, reason: title);
    }
  });
}
