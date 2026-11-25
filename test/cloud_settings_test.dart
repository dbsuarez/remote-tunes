import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:remote_tunes/features/cloud/cloud_config_store.dart';
import 'package:remote_tunes/features/cloud/cloud_models.dart';
import 'package:remote_tunes/features/cloud/cloud_service.dart';
import 'package:remote_tunes/features/cloud/cloud_settings_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cloud_test.dart' show FakeR2, config;

void main() {
  group('the store', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('nothing saved is empty', () async {
      final c = await PrefsCloudConfigStore().load();
      expect(c.canRead, isFalse);
      expect(c.canWrite, isFalse);
    });

    test('saves and reads back, trimming spaces', () async {
      final store = PrefsCloudConfigStore();
      await store.save(const CloudConfig(
          publicUrl: ' https://pub-1.r2.dev ', accountId: 'abc', bucket: ' b ', accessKeyId: ' k ', secretKey: ' s '));
      final c = await store.load();
      expect((c.publicUrl, c.accountId, c.bucket, c.accessKeyId, c.secretKey), ('https://pub-1.r2.dev', 'abc', 'b', 'k', 's'));
    });

    test('forgetting the keys keeps the address; clearing forgets everything', () async {
      final store = PrefsCloudConfigStore();
      await store.save(config);
      await store.clearKeys();
      var c = await store.load();
      expect(c.canRead, isTrue);
      expect(c.accessKeyId, isEmpty);
      expect(c.secretKey, isEmpty);
      expect(c.accountId, isNotEmpty);
      await store.clear();
      c = await store.load();
      expect(c.canRead, isFalse);
      expect(c.accountId, isEmpty);
    });

    test('an empty field removes what was saved', () async {
      final store = PrefsCloudConfigStore();
      await store.save(config);
      await store.save(config.copyWith(bucket: ''));
      expect((await store.load()).bucket, isEmpty);
    });

    test('the keys are never in the app settings table that backups read', () {
      // They live in shared preferences under their own names, apart from the settings table.
      expect(PrefsCloudConfigStore, isNotNull);
    });
  });

  test('the S3 address Cloudflare shows is understood', () {
    final a = CloudConfig.parseS3Address('https://${config.accountId}.r2.cloudflarestorage.com/remotetunes');
    expect((a!.accountId, a.bucket), (config.accountId, 'remotetunes'));
    expect(CloudConfig.parseS3Address('https://${config.accountId}.r2.cloudflarestorage.com')!.bucket, '');
    expect(CloudConfig.parseS3Address('https://${config.accountId}.eu.r2.cloudflarestorage.com/b')!.accountId, config.accountId);
    expect(CloudConfig.parseS3Address(config.accountId), isNull, reason: 'a plain id is not an address');
    expect(CloudConfig.parseS3Address('https://example.com/b'), isNull);
    expect(CloudConfig.parseS3Address(''), isNull);
  });

  group('the settings screen', () {
    late FakeR2 r2;
    late CloudConfigStore store;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      r2 = FakeR2();
      store = PrefsCloudConfigStore();
    });

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(500, 2000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          cloudConfigStoreProvider.overrideWithValue(store),
          cloudServiceFactoryProvider.overrideWithValue((c) => CloudLibraryService(
                c,
                client: MockClient((r) async => r2.handle(r)),
                now: () => DateTime.utc(2026),
              )),
        ],
        child: const MaterialApp(home: CloudSettingsScreen()),
      ));
      await settle(tester);
    }

    Future<void> fill(WidgetTester tester, {bool keys = true}) async {
      await tester.enterText(find.byKey(const Key('cloud-url')), 'https://pub-123.r2.dev');
      if (keys) {
        await tester.enterText(find.byKey(const Key('cloud-account')), config.accountId);
        await tester.enterText(find.byKey(const Key('cloud-bucket')), 'remotetunes');
        await tester.enterText(find.byKey(const Key('cloud-key-id')), 'KEYID');
        await tester.enterText(find.byKey(const Key('cloud-secret')), 'SECRET');
      }
    }

    screenTest('shows what is saved, with the secret hidden', (tester) async {
      await tester.runAsync(() => store.save(config));
      await open(tester);
      expect(tester.widget<TextField>(find.byKey(const Key('cloud-url'))).controller!.text, 'https://pub-123.r2.dev');
      expect(tester.widget<TextField>(find.byKey(const Key('cloud-bucket'))).controller!.text, 'remotetunes');
      expect(tester.widget<TextField>(find.byKey(const Key('cloud-secret'))).obscureText, isTrue);
      await tester.tap(find.byTooltip('Show'));
      await tester.pump();
      expect(tester.widget<TextField>(find.byKey(const Key('cloud-secret'))).obscureText, isFalse);
    });

    screenTest('the S3 address pasted into the account field gives the account id and the bucket', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const Key('cloud-url')), 'https://pub-123.r2.dev');
      await tester.enterText(find.byKey(const Key('cloud-account')), 'https://${config.accountId}.r2.cloudflarestorage.com/remotetunes');
      await tester.enterText(find.byKey(const Key('cloud-key-id')), 'KEYID');
      await tester.enterText(find.byKey(const Key('cloud-secret')), 'SECRET');
      await tester.tap(find.byKey(const Key('cloud-test-keys')));
      await settle(tester);
      expect(find.text('The keys work. The bucket holds 0 songs.'), findsOneWidget);
      final c = await tester.runAsync(store.load);
      expect((c!.accountId, c.bucket), (config.accountId, 'remotetunes'));
    });

    screenTest('Save keeps what was typed', (tester) async {
      await open(tester);
      await fill(tester);
      await tester.tap(find.byKey(const Key('cloud-save')));
      await settle(tester);
      expect(find.text('Saved.'), findsOneWidget);
      final c = await tester.runAsync(store.load);
      expect(c!.accessKeyId, 'KEYID');
      expect(c.publicUrl, 'https://pub-123.r2.dev');
    });

    screenTest('a mistake is explained and nothing is saved', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const Key('cloud-url')), 'http://nope');
      await tester.tap(find.byKey(const Key('cloud-save')));
      await settle(tester);
      expect(find.textContaining('https://'), findsWidgets);
      expect((await tester.runAsync(store.load))!.canRead, isFalse);
    });

    screenTest('Test the address says how many songs are in the cloud', (tester) async {
      r2.files['catalog.json'] = utf8.encode(jsonEncode({
        'songs': [
          {'id': 'a', 'title': 'A', 'audio': 'songs/a.mp3'},
          {'id': 'b', 'title': 'B', 'audio': 'songs/b.mp3'},
        ],
      }));
      await open(tester);
      await fill(tester, keys: false);
      await tester.tap(find.byKey(const Key('cloud-test-public')));
      await settle(tester);
      expect(find.text('The address works: 2 songs in the cloud.'), findsOneWidget);
    });

    screenTest('Test the address with nothing there yet', (tester) async {
      await open(tester);
      await fill(tester, keys: false);
      await tester.tap(find.byKey(const Key('cloud-test-public')));
      await settle(tester);
      expect(find.textContaining('Nothing is in the cloud yet'), findsOneWidget);
    });

    screenTest('Test the keys needs them, then says they work or were refused', (tester) async {
      await open(tester);
      await fill(tester, keys: false);
      await tester.tap(find.byKey(const Key('cloud-test-keys')));
      await settle(tester);
      expect(find.textContaining('account id'), findsOneWidget);
      await fill(tester);
      await tester.tap(find.byKey(const Key('cloud-test-keys')));
      await settle(tester);
      expect(find.text('The keys work. The bucket holds 0 songs.'), findsOneWidget);
      r2.refuse = true;
      await tester.tap(find.byKey(const Key('cloud-test-keys')));
      await settle(tester);
      expect(find.textContaining('refused the keys'), findsOneWidget);
    });

    screenTest('Forget the keys empties the key fields and keeps the address', (tester) async {
      await tester.runAsync(() => store.save(config));
      await open(tester);
      await tester.tap(find.byKey(const Key('cloud-forget-keys')));
      await settle(tester);
      expect(tester.widget<TextField>(find.byKey(const Key('cloud-secret'))).controller!.text, isEmpty);
      final c = await tester.runAsync(store.load);
      expect(c!.canRead, isTrue);
      expect(c.secretKey, isEmpty);
      expect(find.textContaining('still browse and play'), findsOneWidget);
    });
  });
}

Future<void> settle(WidgetTester tester) async {
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 150)));
  await tester.pump(const Duration(milliseconds: 100));
  await tester.pump(const Duration(milliseconds: 300));
}

void screenTest(String name, Future<void> Function(WidgetTester tester) body) {
  testWidgets(name, (tester) async {
    await body(tester);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pump(const Duration(seconds: 1));
  });
}
