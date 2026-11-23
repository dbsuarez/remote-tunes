import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/core/online/relay.dart';
import 'package:remote_tunes/data/repositories/settings_repository.dart';
import 'package:remote_tunes/features/online/online_setup.dart';

import 'helpers/in_memory_relay.dart';

AppSettings settings({
  bool enabled = true,
  String? url = 'https://abc.supabase.co',
  String? key = 'anon-key',
}) =>
    AppSettings(onlineRelayEnabled: enabled, supabaseUrl: url, supabaseAnonKey: key);

void main() {
  group('OnlineAvailability', () {
    test('ready when enabled with a URL and key', () {
      expect(OnlineAvailability.evaluate(settings()).usable, isTrue);
    });

    test('explains each missing piece in plain language', () {
      expect(OnlineAvailability.evaluate(settings(enabled: false)).problem,
          contains('turned off'));
      expect(OnlineAvailability.evaluate(settings(url: null)).problem,
          contains('Supabase URL'));
      expect(OnlineAvailability.evaluate(settings(url: '  ')).problem,
          contains('Supabase URL'));
      expect(OnlineAvailability.evaluate(settings(key: null)).problem,
          contains('anon key'));
    });

    test('rejects URLs that are not https', () {
      for (final bad in ['http://abc.supabase.co', 'abc.supabase.co', 'ftp://x', 'https://']) {
        final a = OnlineAvailability.evaluate(settings(url: bad));
        expect(a.usable, isFalse, reason: bad);
        expect(a.problem, contains('https://'));
      }
    });
  });

  group('PlayerOnlinePlan', () {
    test('Local only: local server, never online', () {
      final p = PlayerOnlinePlan.forMode(ConnectionMode.localOnly, settings());
      expect(p.runLocal, isTrue);
      expect(p.runOnline, isFalse);
      expect(p.problem, isNull);
    });

    test('Online only: no local server, online when set up', () {
      final p = PlayerOnlinePlan.forMode(ConnectionMode.onlineOnly, settings());
      expect(p.runLocal, isFalse);
      expect(p.runOnline, isTrue);
      expect(p.problem, isNull);
    });

    test('Online only without setup explains what to do', () {
      final p = PlayerOnlinePlan.forMode(
          ConnectionMode.onlineOnly, settings(enabled: false));
      expect(p.runLocal, isFalse);
      expect(p.runOnline, isFalse);
      expect(p.problem, contains('Settings'));
    });

    test('Auto: both when set up', () {
      final p = PlayerOnlinePlan.forMode(ConnectionMode.auto, settings());
      expect(p.runLocal, isTrue);
      expect(p.runOnline, isTrue);
    });

    test('Auto without setup quietly stays local (local never depends on '
        'Supabase)', () {
      for (final s in [
        const AppSettings(),
        settings(enabled: false),
        settings(url: null),
        settings(key: ''),
      ]) {
        final p = PlayerOnlinePlan.forMode(ConnectionMode.auto, s);
        expect(p.runLocal, isTrue);
        expect(p.runOnline, isFalse);
        expect(p.problem, isNull);
      }
    });

    test('default settings: nothing online is ever started', () {
      for (final m in ConnectionMode.values) {
        expect(PlayerOnlinePlan.forMode(m, const AppSettings()).runOnline, isFalse);
      }
    });
  });

  group('UnavailableRelayChannel', () {
    test('fails to join with the real reason', () async {
      final ch = UnavailableRelayChannel('Turn it on.');
      await expectLater(
        ch.join(),
        throwsA(isA<RelayException>().having((e) => e.message, 'm', 'Turn it on.')),
      );
      await ch.leave();
    });
  });

  group('testRelayConnection', () {
    test('succeeds when the relay is reachable, and leaves the room', () async {
      final hub = InMemoryRelayHub();
      final r = await testRelayConnection(hub.channel);
      expect(r.success, isTrue);
      expect(r.message, contains('Connected'));
      expect(hub.membersIn('SELFTEST'), 0);
      expect(hub.log, isEmpty, reason: 'sends nothing');
    });

    test('reports why it failed', () async {
      final hub = InMemoryRelayHub()..offline = true;
      final r = await testRelayConnection(hub.channel);
      expect(r.success, isFalse);
      expect(r.message, contains('internet'));
    });

    test('times out instead of hanging', () async {
      final r = await testRelayConnection(
        (_) => _NeverJoins(),
        timeout: const Duration(milliseconds: 200),
      );
      expect(r.success, isFalse);
      expect(r.message, contains('too long'));
    });
  });
}

class _NeverJoins implements RelayChannel {
  @override
  Future<void> join() => Future<void>.delayed(const Duration(minutes: 5));
  @override
  Stream<RelayFrame> get frames => const Stream.empty();
  @override
  Stream<RelayStatus> get status => const Stream.empty();
  @override
  Future<void> send(RelayFrame frame) async {}
  @override
  Future<void> leave() async {}
}
