import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/core/online_defaults.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/settings_repository.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = SettingsRepository(db);
  });

  tearDown(() => db.close());

  test('returns defaults when nothing is stored', () async {
    final s = await repo.load();
    expect(s.connectionMode, ConnectionMode.auto);
    // The relay stays OFF until the user turns it on, even though this build
    // knows which Supabase project to use.
    expect(s.onlineRelayEnabled, isFalse);
    expect(s.supabaseUrl, OnlineDefaults.supabaseUrl);
    expect(s.supabaseAnonKey, OnlineDefaults.supabaseAnonKey);
    expect(s.lastPlayerPort, 8765);
    expect(s.defaultVolume, closeTo(0.8, 1e-9));
  });

  test('settings persist and round-trip', () async {
    await repo.setDeviceName('  GT 30 Pro ');
    await repo.setConnectionMode(ConnectionMode.localOnly);
    await repo.setOnlineRelayEnabled(true);
    await repo.setDefaultVolume(0.35);
    await repo.setRepeatMode(RepeatMode.queue);
    await repo.setShuffleEnabled(true);
    await repo.setExternalAppControlEnabled(true);
    await repo.setLastPlayerPort(9000);

    final s = await repo.load();
    expect(s.deviceName, 'GT 30 Pro');
    expect(s.connectionMode, ConnectionMode.localOnly);
    expect(s.onlineRelayEnabled, isTrue);
    expect(s.defaultVolume, closeTo(0.35, 1e-9));
    expect(s.repeatMode, RepeatMode.queue);
    expect(s.shuffleEnabled, isTrue);
    expect(s.externalAppControlEnabled, isTrue);
    expect(s.lastPlayerPort, 9000);
  });

  test('empty device name is ignored', () async {
    await repo.setDeviceName('Phone A');
    await repo.setDeviceName('   ');
    expect((await repo.load()).deviceName, 'Phone A');
  });

  test('what the user enters wins over the build defaults; blank goes back to '
      'the defaults', () async {
    await repo.setSupabaseUrl('https://abc.supabase.co');
    await repo.setSupabaseAnonKey('anon-key');
    var s = await repo.load();
    expect(s.supabaseUrl, 'https://abc.supabase.co');
    expect(s.supabaseAnonKey, 'anon-key');

    // Clearing the fields removes the stored values: the build's own project
    // is used again.
    await repo.setSupabaseUrl('  ');
    await repo.setSupabaseAnonKey('');
    s = await repo.load();
    expect(s.supabaseUrl, OnlineDefaults.supabaseUrl);
    expect(s.supabaseAnonKey, OnlineDefaults.supabaseAnonKey);
    final rows = await db.customSelect(
        "SELECT COUNT(*) AS c FROM settings WHERE key LIKE 'supabase_%'").getSingle();
    expect(rows.read<int>('c'), 0, reason: 'blank values are not stored');
  });

  test('the default URL is an https Supabase address and passes the app checks',
      () {
    expect(OnlineDefaults.supabaseUrl, startsWith('https://'));
    expect(OnlineDefaults.supabaseUrl, endsWith('.supabase.co'));
    expect(OnlineDefaults.supabaseAnonKey, isNotEmpty);
    // Never ship a secret key by mistake.
    expect(OnlineDefaults.supabaseAnonKey, isNot(contains('service_role')));
    expect(OnlineDefaults.supabaseAnonKey, isNot(startsWith('sb_secret_')));
  });

  test('volume is clamped to 0.0–1.0', () async {
    await repo.setDefaultVolume(5);
    expect((await repo.load()).defaultVolume, 1.0);
    await repo.setDefaultVolume(-1);
    expect((await repo.load()).defaultVolume, 0.0);
  });

  test('connection history is empty in Phase 0', () async {
    expect(await repo.watchConnectionHistory().first, isEmpty);
  });

  test('all five schema-v1 tables exist', () async {
    final rows = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    final names = rows.map((r) => r.read<String>('name')).toSet();
    expect(
      names,
      containsAll([
        'songs',
        'queue_items',
        'settings',
        'paired_controllers',
        'recent_urls',
      ]),
    );
  });
}
