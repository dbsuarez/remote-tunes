import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/core/protocol/protocol.dart';
import 'package:remote_tunes/features/player/playback_engine.dart';

void main() {
  group('RemoteMessage', () {
    test('round-trips the documented envelope', () {
      const m = RemoteMessage(
        type: MessageType.command,
        sessionId: 's',
        requestId: 'r',
        token: 't',
        payload: {'action': 'seek', 'positionSeconds': 45},
      );
      final back = RemoteMessage.decode(m.encode());
      expect(back.type, 'command');
      expect(back.sessionId, 's');
      expect(back.requestId, 'r');
      expect(back.token, 't');
      expect(back.payload['positionSeconds'], 45);
    });

    test('ignores unknown fields and tolerates a missing payload', () {
      final m = RemoteMessage.decode(jsonEncode({
        'type': 'ping',
        'somethingNew': {'a': 1},
      }));
      expect(m.type, 'ping');
      expect(m.sessionId, '');
      expect(m.payload, isEmpty);
    });

    test('rejects non-text, bad JSON, non-objects and missing type', () {
      expect(() => RemoteMessage.decode(42), throwsA(isA<ProtocolException>()));
      expect(() => RemoteMessage.decode('{nope'), throwsA(isA<ProtocolException>()));
      expect(() => RemoteMessage.decode('[1,2]'), throwsA(isA<ProtocolException>()));
      expect(() => RemoteMessage.decode('{"payload":{}}'),
          throwsA(isA<ProtocolException>()));
    });

    test('error helper carries code and message', () {
      final e = RemoteMessage.error(ErrorCodes.notPaired, 'Pair first.',
          requestId: 'r1');
      final back = RemoteMessage.decode(e.encode());
      expect(back.type, MessageType.error);
      expect(back.errorCode, ErrorCodes.notPaired);
      expect(back.errorMessage, 'Pair first.');
      expect(back.requestId, 'r1');
    });
  });

  group('PlaybackState', () {
    test('matches the documented state payload', () {
      final s = PlaybackState.fromJson({
        'title': 'Song',
        'artist': 'Artist',
        'positionSeconds': 42,
        'durationSeconds': 210,
        'isPlaying': true,
        'queueIndex': 3,
        'queueLength': 12,
        'volume': 0.8,
        'repeatMode': 'off',
        'shuffleEnabled': false,
        'source': 'local_file',
      });
      expect(s.title, 'Song');
      expect(s.positionSeconds, 42);
      expect(s.isPlaying, isTrue);
      expect(s.queueIndex, 3);
      expect(s.repeatMode, RepeatMode.off);
      expect(PlaybackState.fromJson(s.toJson()).durationSeconds, 210);
    });

    test('bad or missing fields fall back to defaults and clamp volume', () {
      final s = PlaybackState.fromJson({
        'title': 5,
        'positionSeconds': 'x',
        'volume': 9,
        'repeatMode': 'bogus',
      });
      expect(s.title, '');
      expect(s.positionSeconds, 0);
      expect(s.volume, 1.0);
      expect(s.repeatMode, RepeatMode.off);
    });
  });

  group('SimulatedPlaybackEngine', () {
    test('seek and volume are validated', () async {
      final e = SimulatedPlaybackEngine(autoTick: false);
      addTearDown(e.dispose);
      await expectLater(e.seek(-1), throwsA(isA<PlaybackException>()));
      await expectLater(e.seek(100000), throwsA(isA<PlaybackException>()));
      await expectLater(e.setVolume(1.5), throwsA(isA<PlaybackException>()));
      await e.seek(10);
      expect(e.state.positionSeconds, 10);
    });

    test('previous restarts a track that has played a few seconds', () async {
      final e = SimulatedPlaybackEngine(autoTick: false);
      addTearDown(e.dispose);
      await e.next();
      await e.seek(30);
      await e.previous();
      expect(e.state.queueIndex, 1);
      expect(e.state.positionSeconds, 0);
      await e.previous();
      expect(e.state.queueIndex, 0);
    });

    test('plays through to the next track when one ends', () async {
      final e = SimulatedPlaybackEngine(autoTick: false);
      addTearDown(e.dispose);
      await e.play();
      await e.seek(e.state.durationSeconds - 1);
      e.tickForTest();
      expect(e.state.queueIndex, 1);
      expect(e.state.isPlaying, isTrue);
      expect(e.state.positionSeconds, 0);
    });
  });
}
