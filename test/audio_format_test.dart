import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/protocol/protocol.dart';
import 'package:remote_tunes/features/player/audio/audio_format.dart';
import 'package:remote_tunes/features/player/queue/playable_song.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';

import 'helpers/fake_audio_backend.dart';

PlayableSong song(int id) => PlayableSong(
    id: id, title: 'S$id', artist: 'A', album: 'B', filePath: '/m/$id.mp3', durationSeconds: 100);

void main() {
  group('describing a file', () {
    test('sample rate, bitrate and type', () {
      expect(describeAudio(codec: 'MP3', bitrate: 256000, sampleRate: 48000),
          '48 kHz · 256 kbps · MP3');
    });

    test('44.1 kHz keeps its decimal; whole numbers do not', () {
      expect(describeAudio(sampleRate: 44100), '44.1 kHz');
      expect(describeAudio(sampleRate: 96000), '96 kHz');
    });

    test('a bitrate given in kilobits or in bits both read right', () {
      expect(describeAudio(bitrate: 320), '320 kbps');
      expect(describeAudio(bitrate: 320000), '320 kbps');
    });

    test('unknown or silly values are left out', () {
      expect(describeAudio(codec: 'FLAC'), 'FLAC');
      expect(describeAudio(bitrate: 0, sampleRate: 5), isNull);
      expect(describeAudio(), isNull);
      expect(describeAudio(bitrate: 99999999), isNull);
    });

    test('file types get a readable name', () {
      expect(codecName('mp3'), 'MP3');
      expect(codecName('M4A'), 'M4A');
      expect(codecName('opus'), 'OPUS');
      expect(codecName(''), isNull);
      expect(codecName('wma'), 'WMA');
    });
  });

  group('the line under the seek bar', () {
    late FakeAudioBackend backend;
    late QueuePlaybackEngine engine;
    late List<String> asked;

    QueuePlaybackEngine make(Future<String?> Function(String) reader) {
      return QueuePlaybackEngine(
        backend: backend,
        fileExists: (_) => true,
        formatReader: reader,
      );
    }

    setUp(() {
      backend = FakeAudioBackend();
      asked = [];
    });

    tearDown(() => engine.dispose());

    test('is filled in once the file has been read', () async {
      engine = make((p) async {
        asked.add(p);
        return '48 kHz · 256 kbps · MP3';
      });
      await engine.playSongs([song(1)]);
      await settle();
      expect(asked, ['/m/1.mp3']);
      expect(engine.state.format, '48 kHz · 256 kbps · MP3');
    });

    test('the song starts without waiting for it', () async {
      engine = make((p) => Future.delayed(const Duration(seconds: 5), () => 'late'));
      await engine.playSongs([song(1)]);
      expect(engine.state.isPlaying, isTrue);
      expect(engine.state.format, '');
    });

    test('a failing reader leaves the line empty and breaks nothing', () async {
      engine = make((p) async => throw StateError('bad file'));
      await engine.playSongs([song(1)]);
      await settle();
      expect(engine.state.format, '');
      expect(engine.state.isPlaying, isTrue);
    });

    test('a slow answer for the old song is not shown for the new one', () async {
      engine = make((p) async {
        if (p.endsWith('1.mp3')) await Future<void>.delayed(const Duration(milliseconds: 200));
        return 'format of $p';
      });
      await engine.playSongs([song(1), song(2)]);
      await engine.next();
      await Future<void>.delayed(const Duration(milliseconds: 400));
      expect(engine.state.format, 'format of /m/2.mp3');
    });

    test('moving to the next song with no gap reads the new file', () async {
      engine = make((p) async => 'format of $p');
      await engine.playSongs([song(1), song(2)]);
      await settle();
      expect(engine.state.format, 'format of /m/1.mp3');
      backend.advanceGapless();
      await settle();
      expect(engine.state.format, 'format of /m/2.mp3');
    });

    test('with no reader nothing is shown', () async {
      engine = QueuePlaybackEngine(backend: backend, fileExists: (_) => true);
      await engine.playSongs([song(1)]);
      await settle();
      expect(engine.state.format, '');
    });

    test('the line travels to the Controller, and is left out when empty', () async {
      engine = make((p) async => '44.1 kHz · MP3');
      await engine.playSongs([song(1)]);
      await settle();
      final json = jsonDecode(jsonEncode(engine.state.toJson())) as Map<String, dynamic>;
      expect(PlaybackState.fromJson(json).format, '44.1 kHz · MP3');
      expect(const PlaybackState().toJson().containsKey('format'), isFalse);
      expect(PlaybackState.fromJson(const {}).format, '');
    });
  });
}
