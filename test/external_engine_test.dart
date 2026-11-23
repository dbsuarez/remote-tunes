import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/core/protocol/protocol.dart';
import 'package:remote_tunes/features/external/control_mode_engine.dart';
import 'package:remote_tunes/features/external/external_app_engine.dart';
import 'package:remote_tunes/features/external/external_media.dart';
import 'package:remote_tunes/features/player/playback_engine.dart';
import 'package:remote_tunes/features/player/queue/playable_song.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';

import 'helpers/fake_audio_backend.dart';
import 'helpers/fake_external_bridge.dart';

Matcher playbackError(String code) => throwsA(
    isA<PlaybackException>().having((e) => e.code, 'code', code));

void main() {
  group('parsing what Android reports', () {
    test('a full snapshot', () {
      final s = ExternalMediaSnapshot.fromMap({
        'accessGranted': true,
        'volume': 0.4,
        'sessions': [
          {'package': 'com.spotify.music', 'label': 'Spotify', 'isPlaying': true, 'title': 'T'},
        ],
        'current': {
          'package': 'com.spotify.music',
          'label': 'Spotify',
          'title': 'Song',
          'artist': 'Artist',
          'album': 'Album',
          'durationMs': 180000,
          'positionMs': 5000,
          'isPlaying': true,
          'canSeek': true,
          'canNext': true,
          'canPrevious': false,
        },
      });
      expect(s.accessGranted, isTrue);
      expect(s.volume, 0.4);
      expect(s.sessions.single.label, 'Spotify');
      expect(s.current!.title, 'Song');
      expect(s.current!.canPrevious, isFalse);
      expect(s.current!.durationMs, 180000);
    });

    test('junk becomes safe defaults, never an exception', () {
      for (final junk in [null, 'x', 5, <String, dynamic>{}, {'sessions': 'no'}, {'current': 7}]) {
        final s = ExternalMediaSnapshot.fromMap(junk);
        expect(s.accessGranted, isFalse);
        expect(s.current, isNull);
        expect(s.sessions, isEmpty);
      }
      final t = ExternalTrack.fromMap({'package': 'a.b', 'title': 5, 'durationMs': 'x'})!;
      expect(t.label, 'a.b', reason: 'falls back to the package name');
      expect(t.title, '');
      expect(t.durationMs, 0);
      expect(ExternalTrack.fromMap({'label': 'no package'}), isNull);
      expect(ExternalSession.fromMap({'package': ''}), isNull);
      expect(ExternalMediaSnapshot.fromMap({'volume': 9}).volume, 1.0);
    });
  });

  group('PlaybackState external fields are backward compatible', () {
    test('defaults are not sent, so older Controllers see nothing new', () {
      final json = const PlaybackState(title: 'x').toJson();
      expect(json.containsKey('externalApp'), isFalse);
      expect(json.containsKey('externalEnabled'), isFalse);
      expect(json.containsKey('canSeek'), isFalse);
      expect(json.containsKey('canSkip'), isFalse);
      final back = PlaybackState.fromJson(json);
      expect(back.canSeek, isTrue);
      expect(back.canSkip, isTrue);
      expect(back.externalEnabled, isFalse);
      expect(back.isExternal, isFalse);
    });

    test('external values round-trip', () {
      const s = PlaybackState(
          source: 'external',
          externalApp: 'Spotify',
          externalEnabled: true,
          canSeek: false,
          canSkip: false);
      final back = PlaybackState.fromJson(s.toJson());
      expect(back.isExternal, isTrue);
      expect(back.externalApp, 'Spotify');
      expect(back.externalEnabled, isTrue);
      expect(back.canSeek, isFalse);
      expect(back.canSkip, isFalse);
    });
  });

  group('ExternalAppEngine', () {
    late FakeExternalBridge bridge;
    late ExternalAppEngine engine;

    setUp(() {
      bridge = FakeExternalBridge()..snapshot = FakeExternalBridge.playing();
      engine = ExternalAppEngine(bridge: bridge);
    });

    tearDown(() => engine.dispose());

    test('reports what the other app is playing', () async {
      await engine.activate();
      final s = engine.state;
      expect(s.source, 'external');
      expect(s.isExternal, isTrue);
      expect(s.title, 'Blue Song');
      expect(s.artist, 'The Band');
      expect(s.album, 'Blue Album');
      expect(s.positionSeconds, 10);
      expect(s.durationSeconds, 200);
      expect(s.isPlaying, isTrue);
      expect(s.externalApp, 'Spotify');
      expect(s.canSeek, isTrue);
      expect(s.canSkip, isTrue);
      expect(s.volume, 0.5);
      expect(s.queueLength, 0, reason: 'no queue for other apps');
      expect(s.error, '');
      expect(engine.appName, 'Spotify');
    });

    test('a track without a title shows the app name instead', () async {
      bridge.snapshot = FakeExternalBridge.playing(t: FakeExternalBridge.track(title: ''));
      await engine.activate();
      expect(engine.state.title, 'Spotify');
    });

    test('without Notification access it refuses clearly and stays inactive', () async {
      bridge.accessGranted = false;
      await expectLater(engine.activate(), playbackError(ErrorCodes.permissionDenied));
      expect(engine.isActive, isFalse);
      expect(bridge.calls, ['start', 'stop']);
    });

    test('transport commands reach the other app', () async {
      await engine.activate();
      await engine.play();
      await engine.pause();
      await engine.next();
      await engine.previous();
      await engine.seek(42);
      await engine.setVolume(0.75);
      await engine.stop();
      expect(bridge.calls.skip(1), [
        'play',
        'pause',
        'next',
        'previous',
        'seekTo:42000',
        'volume:0.75',
        'pause',
      ]);
    });

    test('toggle pauses a playing app and plays a paused one', () async {
      await engine.activate();
      await engine.toggle();
      expect(bridge.calls.last, 'pause');
      bridge.push(FakeExternalBridge.playing(t: FakeExternalBridge.track(isPlaying: false)));
      await Future<void>.delayed(Duration.zero);
      await engine.toggle();
      expect(bridge.calls.last, 'play');
    });

    test('never promises what the app does not allow', () async {
      bridge.snapshot = FakeExternalBridge.playing(
        t: FakeExternalBridge.track(canSeek: false, canNext: false, canPrevious: false),
      );
      await engine.activate();
      expect(engine.state.canSeek, isFalse);
      expect(engine.state.canSkip, isFalse);
      await expectLater(
        engine.next(),
        throwsA(isA<PlaybackException>()
            .having((e) => e.code, 'code', ErrorCodes.invalidAction)
            .having((e) => e.message, 'message', contains("Spotify doesn't allow skipping"))),
      );
      await expectLater(engine.previous(), playbackError(ErrorCodes.invalidAction));
      await expectLater(
        engine.seek(5),
        throwsA(isA<PlaybackException>()
            .having((e) => e.message, 'message', contains("doesn't allow seeking"))),
      );
      expect(bridge.calls, ['start'], reason: 'nothing was sent to the app');
    });

    test('one-way skipping: only the allowed direction works', () async {
      bridge.snapshot = FakeExternalBridge.playing(
          t: FakeExternalBridge.track(canNext: true, canPrevious: false));
      await engine.activate();
      expect(engine.state.canSkip, isTrue);
      await engine.next();
      await expectLater(engine.previous(), playbackError(ErrorCodes.invalidAction));
    });

    test('seek and volume are validated', () async {
      await engine.activate();
      await expectLater(engine.seek(-1), playbackError(ErrorCodes.invalidPosition));
      await expectLater(engine.seek(9999), playbackError(ErrorCodes.invalidPosition));
      await expectLater(engine.setVolume(2), playbackError(ErrorCodes.invalidAction));
      await expectLater(engine.setVolume(double.nan), playbackError(ErrorCodes.invalidAction));
    });

    test('with no music app playing: clear message, commands refused', () async {
      bridge.snapshot = const ExternalMediaSnapshot(accessGranted: true);
      await engine.activate();
      expect(engine.state.title, '');
      expect(engine.state.externalApp, '');
      expect(engine.state.error, contains('No music app is playing'));
      for (final action in [engine.play, engine.pause, engine.next, engine.previous]) {
        await expectLater(
          action(),
          throwsA(isA<PlaybackException>()
              .having((e) => e.code, 'code', ErrorCodes.playbackFailed)
              .having((e) => e.message, 'message', contains('Spotify or YouTube Music'))),
        );
      }
      // Then the user starts a song.
      bridge.push(FakeExternalBridge.playing());
      await Future<void>.delayed(Duration.zero);
      expect(engine.state.error, '');
      expect(engine.state.title, 'Blue Song');
    });

    test('follows live changes and only forwards real changes', () async {
      await engine.activate();
      final seen = <String>[];
      final sub = engine.states.listen((s) => seen.add(s.title));

      bridge.push(FakeExternalBridge.playing(t: FakeExternalBridge.track(title: 'Next Song', positionMs: 0)));
      bridge.push(FakeExternalBridge.playing(t: FakeExternalBridge.track(title: 'Next Song', positionMs: 0)));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel();
      expect(seen, ['Next Song'], reason: 'the identical update was dropped');
    });

    test('the position keeps moving between updates while playing', () async {
      await engine.activate();
      final before = engine.state.positionSeconds;
      await Future<void>.delayed(const Duration(milliseconds: 1250));
      expect(engine.state.positionSeconds, greaterThan(before));
    });

    test('the position does not run past the end', () async {
      bridge.snapshot = FakeExternalBridge.playing(
          t: FakeExternalBridge.track(durationMs: 2000, positionMs: 1500));
      await engine.activate();
      await Future<void>.delayed(const Duration(milliseconds: 2300));
      expect(engine.state.positionSeconds, lessThanOrEqualTo(2));
    });

    test('leaving pauses the other app and releases the listener', () async {
      await engine.activate();
      await engine.deactivate();
      expect(bridge.calls.skip(1), ['pause', 'stop']);
      expect(engine.isActive, isFalse);
      await expectLater(engine.play(), playbackError(ErrorCodes.invalidAction));
    });

    test('leaving does not pause an app that is already paused', () async {
      bridge.snapshot = FakeExternalBridge.playing(t: FakeExternalBridge.track(isPlaying: false));
      await engine.activate();
      await engine.deactivate();
      expect(bridge.calls, ['start', 'stop']);
    });

    test('commands before activating are refused', () async {
      await expectLater(engine.play(), playbackError(ErrorCodes.invalidAction));
    });

    test('Android-side failures become plain PlaybackExceptions', () async {
      await engine.activate();
      bridge.failWith = ExternalMediaException('Notification access is not allowed.', noAccess: true);
      await expectLater(engine.play(), playbackError(ErrorCodes.permissionDenied));
      bridge.failWith = ExternalMediaException("The Player couldn't control that app right now.");
      await expectLater(engine.next(), playbackError(ErrorCodes.playbackFailed));
    });

    test('the user can choose which app to control', () async {
      await engine.activate();
      await engine.selectApp('com.google.android.apps.youtube.music');
      await engine.selectApp(null);
      expect(bridge.calls.skip(1), ['select:com.google.android.apps.youtube.music', 'select:auto']);
    });
  });

  group('ControlModeEngine', () {
    late FakeAudioBackend backend;
    late QueuePlaybackEngine local;
    late FakeExternalBridge bridge;
    late ControlModeEngine engine;

    PlayableSong song(int id) => PlayableSong(
          id: id,
          title: 'Local $id',
          artist: 'A',
          album: 'B',
          filePath: '/m/$id.mp3',
          durationSeconds: 100,
        );

    setUp(() {
      backend = FakeAudioBackend();
      local = QueuePlaybackEngine(backend: backend, fileExists: (_) => true);
      bridge = FakeExternalBridge()..snapshot = FakeExternalBridge.playing();
      engine = ControlModeEngine(local: local, external: ExternalAppEngine(bridge: bridge));
    });

    tearDown(() => engine.dispose());

    test('starts on RemoteTunes and tells Controllers external is available', () async {
      expect(engine.controlMode, ControlMode.local);
      await engine.playSongs([song(1)]);
      expect(engine.state.source, 'local_file');
      expect(engine.state.title, 'Local 1');
      expect(engine.state.externalEnabled, isTrue);
      expect(bridge.calls, isEmpty, reason: 'nothing touches other apps until asked');
    });

    test('without the opt-in nothing external is offered or possible', () async {
      final plain = ControlModeEngine(local: local);
      expect(plain.externalAvailable, isFalse);
      expect(plain.state.externalEnabled, isFalse);
      await expectLater(
        plain.setControlMode(ControlMode.external),
        throwsA(isA<PlaybackException>()
            .having((e) => e.code, 'code', ErrorCodes.permissionDenied)
            .having((e) => e.message, 'message', contains('turned off'))),
      );
      expect(bridge.calls, isEmpty);
    });

    test('switching to external pauses RemoteTunes and controls the other app',
        () async {
      await engine.playSongs([song(1)]);
      expect(backend.playing, isTrue);

      await engine.setControlMode(ControlMode.external);
      expect(engine.controlMode, ControlMode.external);
      expect(backend.playing, isFalse, reason: 'two apps never play at once');
      expect(engine.state.isExternal, isTrue);
      expect(engine.state.externalApp, 'Spotify');
      expect(engine.state.title, 'Blue Song');

      await engine.next();
      await engine.seek(30);
      expect(bridge.calls, containsAllInOrder(['start', 'next', 'seekTo:30000']));
      expect(backend.loaded, ['/m/1.mp3'], reason: 'RemoteTunes untouched');
    });

    test('its state stream follows the active side only', () async {
      await engine.playSongs([song(1)]);
      final titles = <String>[];
      final sub = engine.states.listen((s) => titles.add(s.title));

      await engine.setControlMode(ControlMode.external);
      // (RemoteTunes pausing as part of the switch is reported before the
      // mode flips; only what happens after matters here.)
      await Future<void>.delayed(const Duration(milliseconds: 20));
      titles.clear();
      bridge.push(FakeExternalBridge.playing(t: FakeExternalBridge.track(title: 'Live Update')));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await local.play(); // a local change while in external mode
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(titles, contains('Live Update'));
      expect(titles.where((t) => t == 'Local 1'), isEmpty,
          reason: 'local updates are not forwarded in external mode');
      await local.pause();

      await engine.setControlMode(ControlMode.local);
      await local.play();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await sub.cancel();
      expect(titles.last, 'Local 1');
    });

    test('queue, library songs and internet links are refused while external, '
        'with an explanation', () async {
      await engine.setControlMode(ControlMode.external);
      final refusals = <Future<void> Function()>[
        () => engine.playSongs([song(1)]),
        () => engine.enqueue([song(1)]),
        () => engine.playUrl('https://example.com/a.mp3'),
        () => engine.removeQueueItem(1),
        () => engine.moveQueueItem(1, 0),
        () => engine.clearQueue(),
        () => engine.playQueueItem(1),
        () => engine.setRepeatMode(RepeatMode.one),
        () => engine.setShuffle(true),
      ];
      for (final call in refusals) {
        await expectLater(
          call(),
          throwsA(isA<PlaybackException>()
              .having((e) => e.code, 'code', ErrorCodes.invalidAction)
              .having((e) => e.message, 'message',
                  allOf(contains('Spotify'), contains('Switch back to RemoteTunes')))),
        );
      }
      expect(engine.queueSnapshot().items, isEmpty);
    });

    test('switching back pauses the other app and RemoteTunes works again',
        () async {
      await engine.setControlMode(ControlMode.external);
      await engine.setControlMode(ControlMode.local);
      expect(bridge.calls, containsAllInOrder(['start', 'pause', 'stop']));
      expect(engine.state.source, isNot('external'));
      await engine.playSongs([song(2)]);
      expect(engine.state.title, 'Local 2');
    });

    test('no Notification access: stays on RemoteTunes with a clear error', () async {
      bridge.accessGranted = false;
      await engine.playSongs([song(1)]);
      await expectLater(
        engine.setControlMode(ControlMode.external),
        throwsA(isA<PlaybackException>()
            .having((e) => e.code, 'code', ErrorCodes.permissionDenied)
            .having((e) => e.message, 'message', contains('Notification access'))),
      );
      expect(engine.controlMode, ControlMode.local);
      expect(engine.state.title, 'Local 1');
    });

    test('switching to the mode it is already in changes nothing', () async {
      await engine.setControlMode(ControlMode.local);
      expect(bridge.calls, isEmpty);
      await engine.setControlMode(ControlMode.external);
      await engine.setControlMode(ControlMode.external);
      expect(bridge.calls.where((c) => c == 'start'), hasLength(1));
    });

    test('transport commands go to whichever side is active', () async {
      await engine.playSongs([song(1), song(2)]);
      await engine.next();
      expect(engine.state.title, 'Local 2');
      await engine.setControlMode(ControlMode.external);
      await engine.pause();
      expect(bridge.calls.last, 'pause');
      expect(engine.state.title, isNot('Local 2'));
    });

    test('no file path or app package ever appears in state sent to Controllers',
        () async {
      await engine.setControlMode(ControlMode.external);
      final json = jsonEncode(engine.state.toJson());
      expect(json, isNot(contains('com.spotify')));
      expect(json, contains('Spotify'));
    });
  });
}
