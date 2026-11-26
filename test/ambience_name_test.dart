import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/settings_repository.dart';
import 'package:remote_tunes/features/shell/app_drawer.dart';

void main() {
  test('the name is Ambience until changed; blank or the usual name goes back; long ones are cut', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    final repo = SettingsRepository(db);
    expect((await repo.load()).ambienceName, 'Ambience');
    await repo.setAmbienceName('  Pampatulog  ');
    expect((await repo.load()).ambienceName, 'Pampatulog');
    await repo.setAmbienceName('   ');
    expect((await repo.load()).ambienceName, 'Ambience');
    await repo.setAmbienceName('Sleepy');
    await repo.setAmbienceName('Ambience');
    expect(await repo.readValue(SettingKeys.ambienceName), isNull);
    await repo.setAmbienceName('x' * 50);
    expect((await repo.load()).ambienceName, hasLength(30));
  });

  testWidgets('the menu shows the name chosen', (tester) async {
    tester.view.physicalSize = const Size(400, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var opened = 0;
    void nothing() {}
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AppDrawer(
          onNowPlaying: nothing,
          onLyrics: nothing,
          onLibrary: nothing,
          onPlaylists: nothing,
          onSearch: nothing,
          onQueue: nothing,
          onEqualizer: nothing,
          onRemotePlayback: nothing,
          onSettings: nothing,
          onChangelog: nothing,
          onHelp: nothing,
          ambienceName: 'Pampatulog',
          onAmbience: () => opened++,
        ),
      ),
    ));
    expect(find.text('Ambience'), findsNothing);
    expect(find.text('Pampatulog'), findsOneWidget);
  });
}
