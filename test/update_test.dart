import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/features/update/update_controller.dart';
import 'package:remote_tunes/providers/providers.dart';
import 'package:remote_tunes/features/update/update_service.dart';

const _base = 'https://github.com/$kUpdateRepo/releases/download/v0.3.0/';

String release({
  String tag = 'v0.3.0',
  bool draft = false,
  bool prerelease = false,
  List<Map<String, Object?>>? assets,
}) =>
    jsonEncode({
      'tag_name': tag,
      'draft': draft,
      'prerelease': prerelease,
      'body': 'Gapless playback.',
      'assets': assets ??
          [
            {
              'name': 'app-arm64-v8a-release.apk',
              'browser_download_url': '${_base}app-arm64-v8a-release.apk',
              'size': 5,
            },
            {
              'name': 'app-armeabi-v7a-release.apk',
              'browser_download_url': '${_base}app-armeabi-v7a-release.apk',
              'size': 5,
            },
          ],
    });

UpdateChecker checker(http.Response Function(http.Request) answer) =>
    UpdateChecker(client: MockClient((r) async => answer(r)));

class FakeNative implements UpdateNative {
  FakeNative({this.installed = '0.1.0', this.allowed = true, this.available = true});
  String installed;
  bool allowed;
  bool available;
  final calls = <String>[];

  @override
  Future<({String version, int build, String abi})?> info() async =>
      available ? (version: installed, build: 1, abi: 'arm64-v8a') : null;
  @override
  Future<bool> canInstall() async => allowed;
  @override
  Future<void> openInstallSettings() async => calls.add('settings');
  @override
  Future<void> install(String path) async => calls.add('install ${path.split(RegExp(r'[\\/]')).last}');
}

void main() {
  group('comparing versions', () {
    test('higher is newer, lower and equal are not', () {
      expect(isNewerVersion('0.2.0', '0.1.0'), isTrue);
      expect(isNewerVersion('v1.0.0', '0.9.9'), isTrue);
      expect(isNewerVersion('0.10.0', '0.9.0'), isTrue, reason: 'numbers, not text');
      expect(isNewerVersion('0.1.0', '0.1.0'), isFalse);
      expect(isNewerVersion('0.1.0', '0.2.0'), isFalse);
    });

    test('a short version counts as having zeros; build parts are ignored', () {
      expect(isNewerVersion('1.1', '1.0.5'), isTrue);
      expect(isNewerVersion('v0.2.0+7', '0.2.0'), isFalse);
      expect(isNewerVersion('0.2.1-beta', '0.2.0'), isTrue);
    });

    test('junk is never newer', () {
      expect(isNewerVersion('latest', '0.1.0'), isFalse);
      expect(isNewerVersion('', '0.1.0'), isFalse);
      expect(isNewerVersion('0.2.0', 'oops'), isFalse);
    });
  });

  group('looking on GitHub', () {
    test('a newer release is found, with the APK for this phone', () async {
      final info = await checker((r) {
        expect(r.url.toString(), 'https://api.github.com/repos/$kUpdateRepo/releases/latest');
        return http.Response(release(), 200);
      }).latest(currentVersion: '0.1.0', abi: 'arm64-v8a');
      expect(info, isNotNull);
      expect(info!.version, '0.3.0');
      expect(info.apkName, 'app-arm64-v8a-release.apk');
      expect(info.notes, 'Gapless playback.');
    });

    test('the other CPU type gets its own APK', () async {
      final info = await checker((_) => http.Response(release(), 200))
          .latest(currentVersion: '0.1.0', abi: 'armeabi-v7a');
      expect(info!.apkName, 'app-armeabi-v7a-release.apk');
    });

    test('already up to date: nothing', () async {
      expect(
        await checker((_) => http.Response(release(), 200))
            .latest(currentVersion: '0.3.0', abi: 'arm64-v8a'),
        isNull,
      );
    });

    test('drafts and pre-releases are ignored', () async {
      for (final body in [release(draft: true), release(prerelease: true)]) {
        expect(
          await checker((_) => http.Response(body, 200))
              .latest(currentVersion: '0.1.0', abi: 'arm64-v8a'),
          isNull,
        );
      }
    });

    test('no release published yet is not an error', () async {
      expect(
        await checker((_) => http.Response('{}', 404))
            .latest(currentVersion: '0.1.0', abi: 'arm64-v8a'),
        isNull,
      );
    });

    test('a release without an APK for this phone says so', () async {
      expect(
        checker((_) => http.Response(release(assets: const []), 200))
            .latest(currentVersion: '0.1.0', abi: 'arm64-v8a'),
        throwsA(isA<UpdateException>()),
      );
    });

    test('a download link that is not from this repo is refused', () async {
      final body = release(assets: [
        {
          'name': 'app-arm64-v8a-release.apk',
          'browser_download_url': 'https://evil.example/app-arm64-v8a-release.apk',
          'size': 5,
        }
      ]);
      expect(
        checker((_) => http.Response(body, 200))
            .latest(currentVersion: '0.1.0', abi: 'arm64-v8a'),
        throwsA(isA<UpdateException>()),
      );
    });

    test('network trouble and server errors give plain messages', () async {
      final down = UpdateChecker(client: MockClient((_) async => throw const SocketException('x')));
      expect(down.latest(currentVersion: '0.1.0', abi: 'arm64-v8a'),
          throwsA(isA<UpdateException>()));
      expect(
        checker((_) => http.Response('rate limited', 403))
            .latest(currentVersion: '0.1.0', abi: 'arm64-v8a'),
        throwsA(isA<UpdateException>()),
      );
      expect(
        checker((_) => http.Response('<html>', 200))
            .latest(currentVersion: '0.1.0', abi: 'arm64-v8a'),
        throwsA(isA<UpdateException>()),
      );
    });
  });

  group('the release notes', () {
    test('recent releases come back newest first with their notes', () async {
      final list = await checker((r) {
        expect(r.url.path, '/repos/$kUpdateRepo/releases');
        return http.Response(
            jsonEncode([
              {'tag_name': 'v0.3.0', 'name': 'RemoteTunes 0.3.0', 'body': 'Lyrics', 'published_at': '2026-11-24T10:00:00Z'},
              {'tag_name': 'v0.2.0', 'name': '', 'body': '', 'draft': false},
              {'tag_name': 'v0.1.9', 'body': 'x', 'draft': true},
            ]),
            200);
      }).recentReleases();
      expect([for (final r in list) r.version], ['0.3.0', '0.2.0']);
      expect(list.first.notes, 'Lyrics');
      expect(list.first.published, DateTime.utc(2026, 11, 24, 10));
      expect(list.last.notes, isEmpty);
    });

    test('network trouble and junk give plain messages', () async {
      expect(
          UpdateChecker(client: MockClient((_) async => throw const SocketException('x')))
              .recentReleases(),
          throwsA(isA<UpdateException>()));
      expect(checker((_) => http.Response('nope', 500)).recentReleases(),
          throwsA(isA<UpdateException>()));
      expect(checker((_) => http.Response('{"a":1}', 200)).recentReleases(),
          throwsA(isA<UpdateException>()));
    });
  });

  group('downloading', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('rt_upd_'));
    tearDown(() => dir.deleteSync(recursive: true));

    final bytes = utf8.encode('hello');
    UpdateInfo info({int size = 5, String? sha}) => UpdateInfo(
          version: '0.3.0',
          notes: '',
          apkUrl: '${_base}app-arm64-v8a-release.apk',
          apkName: 'app-arm64-v8a-release.apk',
          size: size,
          sha256: sha,
        );

    test('the file is saved, and progress reaches 100%', () async {
      final progress = <double>[];
      final f = await checker((_) => http.Response.bytes(bytes, 200))
          .download(info(), dir, onProgress: progress.add);
      expect(f.readAsBytesSync(), bytes);
      expect(progress.last, 1.0);
    });

    test('a matching checksum is accepted', () async {
      final f = await checker((_) => http.Response.bytes(bytes, 200))
          .download(info(sha: sha256.convert(bytes).toString()), dir);
      expect(f.existsSync(), isTrue);
    });

    test('a wrong checksum is refused and nothing is kept', () async {
      await expectLater(
        checker((_) => http.Response.bytes(bytes, 200)).download(info(sha: 'ab' * 32), dir),
        throwsA(isA<UpdateException>()),
      );
      expect(dir.listSync(), isEmpty);
    });

    test('a file of the wrong size is refused', () async {
      await expectLater(
        checker((_) => http.Response.bytes(bytes, 200)).download(info(size: 99), dir),
        throwsA(isA<UpdateException>()),
      );
      expect(dir.listSync(), isEmpty);
    });

    test('a failed download leaves nothing behind', () async {
      await expectLater(
        checker((_) => http.Response('nope', 500)).download(info(), dir),
        throwsA(isA<UpdateException>()),
      );
      expect(dir.listSync(), isEmpty);
    });

    test('an older download is cleared first', () async {
      File('${dir.path}/old.apk').writeAsBytesSync([1]);
      await checker((_) => http.Response.bytes(bytes, 200)).download(info(), dir);
      expect(dir.listSync().map((e) => e.path.split(RegExp(r'[\\/]')).last),
          ['app-arm64-v8a-release.apk']);
    });

    test('a file that is already complete is used without downloading again', () async {
      File('${dir.path}/app-arm64-v8a-release.apk').writeAsBytesSync(bytes);
      var asked = 0;
      final f = await checker((_) {
        asked++;
        return http.Response.bytes(bytes, 200);
      }).download(info(sha: sha256.convert(bytes).toString()), dir);
      expect(asked, 0);
      expect(f.readAsBytesSync(), bytes);
    });

    test('a half-finished or changed file is downloaded again', () async {
      File('${dir.path}/app-arm64-v8a-release.apk').writeAsBytesSync([1, 2]);
      var asked = 0;
      final f = await checker((_) {
        asked++;
        return http.Response.bytes(bytes, 200);
      }).download(info(sha: sha256.convert(bytes).toString()), dir);
      expect(asked, 1);
      expect(f.readAsBytesSync(), bytes);
      // Same size but different content (checksum differs): also downloaded again.
      File('${dir.path}/app-arm64-v8a-release.apk').writeAsBytesSync(utf8.encode('HELLO'));
      await checker((_) {
        asked++;
        return http.Response.bytes(bytes, 200);
      }).download(info(sha: sha256.convert(bytes).toString()), dir);
      expect(asked, 2);
    });

    test('a link from somewhere else is not fetched', () async {
      var asked = false;
      final c = checker((_) {
        asked = true;
        return http.Response.bytes(bytes, 200);
      });
      await expectLater(
        c.download(
            UpdateInfo(
                version: '1',
                notes: '',
                apkUrl: 'https://evil.example/a.apk',
                apkName: 'a.apk',
                size: 5),
            dir),
        throwsA(isA<UpdateException>()),
      );
      expect(asked, isFalse);
    });
  });

  group('the update flow', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('rt_upd_'));
    tearDown(() => dir.deleteSync(recursive: true));

    ProviderContainer make(FakeNative native, String body) => ProviderContainer(overrides: [
          databaseProvider.overrideWith((ref) {
            final db = AppDatabase.forTesting(NativeDatabase.memory());
            ref.onDispose(db.close);
            return db;
          }),
          updateNativeProvider.overrideWithValue(native),
          updateCheckerProvider.overrideWithValue(UpdateChecker(
              client: MockClient((r) async => r.url.host == 'api.github.com'
                  ? http.Response(body, 200)
                  : http.Response.bytes(utf8.encode('hello'), 200)))),
          updateDirProvider.overrideWithValue(() async => dir),
        ]);

    test('check finds an update; update downloads it and starts the installer', () async {
      final native = FakeNative();
      final c = make(native, release());
      addTearDown(c.dispose);
      await c.read(updateProvider.notifier).check();
      expect(c.read(updateProvider).status, UpdateStatus.available);
      expect(c.read(updateProvider).info!.version, '0.3.0');
      await c.read(updateProvider.notifier).install();
      expect(native.calls, ['install app-arm64-v8a-release.apk']);
      expect(c.read(updateProvider).status, UpdateStatus.installing,
          reason: 'the install screen is open: the button is off');
      // Back from the install screen without installing: it can be tried again.
      await c.read(updateProvider.notifier).onResumed();
      expect(c.read(updateProvider).status, UpdateStatus.available);
    });

    test('up to date says so', () async {
      final c = make(FakeNative(installed: '0.3.0'), release());
      addTearDown(c.dispose);
      await c.read(updateProvider.notifier).check();
      expect(c.read(updateProvider).status, UpdateStatus.upToDate);
    });

    test('without permission to install, Android settings open instead', () async {
      final native = FakeNative(allowed: false);
      final c = make(native, release());
      addTearDown(c.dispose);
      await c.read(updateProvider.notifier).check();
      await c.read(updateProvider.notifier).install();
      expect(native.calls, ['settings']);
      expect(c.read(updateProvider).status, UpdateStatus.needsPermission);
    });

    test('off Android it says updating is for the Android app', () async {
      final c = make(FakeNative(available: false), release());
      addTearDown(c.dispose);
      await c.read(updateProvider.notifier).check();
      expect(c.read(updateProvider).status, UpdateStatus.failed);
    });

    test('tapping Update again after a finished download does not download again', () async {
      var downloads = 0;
      final native = FakeNative();
      final c = ProviderContainer(overrides: [
        databaseProvider.overrideWith((ref) {
          final db = AppDatabase.forTesting(NativeDatabase.memory());
          ref.onDispose(db.close);
          return db;
        }),
        updateNativeProvider.overrideWithValue(native),
        updateCheckerProvider.overrideWithValue(UpdateChecker(
            client: MockClient((r) async {
          if (r.url.host == 'api.github.com') return http.Response(release(), 200);
          downloads++;
          return http.Response.bytes(utf8.encode('hello'), 200);
        }))),
        updateDirProvider.overrideWithValue(() async => dir),
      ]);
      addTearDown(c.dispose);
      await c.read(updateProvider.notifier).check();
      await c.read(updateProvider.notifier).install();
      await c.read(updateProvider.notifier).onResumed(); // closed Android's screen
      await c.read(updateProvider.notifier).install();
      expect(downloads, 1, reason: 'the second tap used the file already downloaded');
      expect(native.calls, ['install app-arm64-v8a-release.apk', 'install app-arm64-v8a-release.apk']);
    });

    test('after allowing installs, coming back carries on by itself', () async {
      final native = FakeNative(allowed: false);
      final c = make(native, release());
      addTearDown(c.dispose);
      await c.read(updateProvider.notifier).check();
      await c.read(updateProvider.notifier).install();
      expect(c.read(updateProvider).status, UpdateStatus.needsPermission);
      // Still not allowed: nothing happens on return.
      await c.read(updateProvider.notifier).onResumed();
      expect(native.calls, ['settings']);
      // Allowed now.
      native.allowed = true;
      await c.read(updateProvider.notifier).onResumed();
      expect(native.calls.last, 'install app-arm64-v8a-release.apk');
    });

    test('if Android restarted the app meanwhile, the next start carries on', () async {
      final native = FakeNative(allowed: false);
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);
      ProviderContainer build() => ProviderContainer(overrides: [
            databaseProvider.overrideWithValue(db),
            updateNativeProvider.overrideWithValue(native),
            updateCheckerProvider.overrideWithValue(UpdateChecker(
                client: MockClient((r) async => r.url.host == 'api.github.com'
                    ? http.Response(release(), 200)
                    : http.Response.bytes(utf8.encode('hello'), 200)))),
            updateDirProvider.overrideWithValue(() async => dir),
          ]);
      final first = build();
      await first.read(updateProvider.notifier).check();
      await first.read(updateProvider.notifier).install(); // sends the user to the switch
      first.dispose(); // the app is restarted

      native.allowed = true; // the user allowed it
      final second = build();
      addTearDown(second.dispose);
      await second.read(updateProvider.notifier).autoCheck();
      expect(native.calls.last, 'install app-arm64-v8a-release.apk');
    });

    test('the quiet check stays silent on a network failure', () async {
      final c = ProviderContainer(overrides: [
        updateNativeProvider.overrideWithValue(FakeNative()),
        updateCheckerProvider.overrideWithValue(
            UpdateChecker(client: MockClient((_) async => throw const SocketException('x')))),
      ]);
      addTearDown(c.dispose);
      await c.read(updateProvider.notifier).check(quiet: true);
      expect(c.read(updateProvider).status, UpdateStatus.idle);
      expect(c.read(updateProvider).message, isNull);
    });
  });
}
