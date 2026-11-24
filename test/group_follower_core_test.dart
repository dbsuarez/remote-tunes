import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/features/group/group_follower_core.dart';
import 'package:remote_tunes/features/group/group_models.dart';

import 'helpers/fake_audio_backend.dart';

class FakeAudio implements GroupAudioSource {
  final ready = <int, String>{};
  final fetched = <int>[];
  final failures = <int, String>{};
  final progress = <int, double>{};

  @override
  String? pathIfReady(int id) => ready[id];
  @override
  Future<void> fetch(int id) async => fetched.add(id);
  @override
  String? failureOf(int id) => failures[id];
  @override
  double? progressOf(int id) => progress[id];
}

void main() {
  late FakeAudioBackend backend;
  late FakeAudio audio;
  late GroupFollowerCore core;
  late List<GroupStatus> statuses;

  /// This phone's clock; the Player's clock is [offset] ahead of it.
  var now = 5000.0;
  double? offset = 1000.0;

  GroupFollowerCore make() => GroupFollowerCore(
        backend: backend,
        audio: audio,
        nowMs: () => now,
        offsetMs: () => offset,
        onStatus: statuses.add,
      );

  /// A Player message sampled right now (its clock = ours + offset).
  GroupSync msg({
    int? song = 1,
    int pos = 10000,
    double ageMs = 0,
    bool playing = true,
    double speed = 1.0,
    int? next,
  }) =>
      GroupSync(
        songId: song,
        positionMs: pos,
        atMs: now + (offset ?? 1000.0) - ageMs,
        playing: playing,
        speed: speed,
        nextSongId: next,
      );

  setUp(() {
    backend = FakeAudioBackend();
    audio = FakeAudio()..ready[1] = '/cache/1.mp3';
    statuses = [];
    now = 5000.0;
    offset = 1000.0;
    core = make();
  });

  test('until the clocks are measured it only waits', () async {
    offset = null;
    await core.onSync(msg());
    expect(backend.loaded, isEmpty);
    expect(core.status.phase, GroupPhase.syncing);
  });

  test('starts the song at the right place and plays', () async {
    await core.onSync(msg(pos: 10000));
    expect(backend.loaded, ['/cache/1.mp3']);
    expect(backend.playing, isTrue);
    expect(backend.position.inMilliseconds, 10000);
    expect(core.status.phase, GroupPhase.playing);
  });

  test('a message that took time to arrive is allowed for', () async {
    // The Player sampled 300 ms ago, when the song was at 10 s.
    await core.onSync(msg(pos: 10000, ageMs: 300));
    expect(backend.position.inMilliseconds, 10300);
  });

  test('speed is part of the sum', () async {
    await core.onSync(msg(pos: 10000, ageMs: 200, speed: 1.5));
    expect(backend.position.inMilliseconds, 10300); // 200 ms at 1.5x
    expect(backend.speed, 1.5);
  });

  test('the fine-tune moves the start (positive = sounds late = play ahead)', () async {
    core.nudgeMs = 40;
    await core.onSync(msg(pos: 10000));
    expect(backend.position.inMilliseconds, 10040);
    final other = FakeAudioBackend();
    final c2 = GroupFollowerCore(
        backend: other, audio: audio, nowMs: () => now, offsetMs: () => offset, onStatus: (_) {})
      ..nudgeMs = -25;
    await c2.onSync(msg(pos: 10000));
    expect(other.position.inMilliseconds, 9975);
  });

  test('the song is fetched first if it is not here yet', () async {
    audio.ready.clear();
    audio.progress[1] = 0.4;
    await core.onSync(msg());
    expect(audio.fetched, [1]);
    expect(backend.loaded, isEmpty);
    expect(core.status.phase, GroupPhase.downloading);
    expect(core.status.message, contains('40%'));

    // It arrives; the next update starts it, already at the right place.
    audio.ready[1] = '/cache/1.mp3';
    now += 2000;
    await core.onSync(msg(pos: 12000));
    expect(backend.playing, isTrue);
    expect(backend.position.inMilliseconds, 12000);
  });

  test('a failed download is explained', () async {
    audio.ready.clear();
    audio.failures[1] = 'The Player no longer has that song.';
    await core.onSync(msg());
    expect(core.status.phase, GroupPhase.problem);
    expect(core.status.message, 'The Player no longer has that song.');
  });

  test('the next song is fetched ahead of time', () async {
    await core.onSync(msg(next: 2));
    expect(audio.fetched, [2]);
    // Already here: not fetched again.
    audio.ready[2] = '/cache/2.mp3';
    audio.fetched.clear();
    now += 1000;
    await core.onSync(msg(next: 2));
    expect(audio.fetched, isEmpty);
  });

  group('keeping in step', () {
    Future<void> startThen() async {
      await core.onSync(msg(pos: 10000));
      expect(backend.playing, isTrue);
      now += 1000; // past the settling time after the start
    }

    /// Feeds one second of playing with the audio [errMs] ahead (+) of where it
    /// should be.
    Future<void> second(double errMs) async {
      now += 1000;
      final pos = 11000 + (now - 6000).round();
      backend.position = Duration(milliseconds: pos + errMs.round());
      await core.onSync(msg(pos: pos));
    }

    test('close enough: nothing is touched', () async {
      await startThen();
      final seeks = backend.seekCount;
      backend.position = const Duration(milliseconds: 11005); // 5 ms off
      await core.onSync(msg(pos: 11000));
      expect(backend.seekCount, seeks);
      expect(backend.speed, 1.0);
      expect(core.status.driftMs, closeTo(5, 1));
    });

    test('just after starting nothing is corrected while the engine settles', () async {
      await core.onSync(msg(pos: 10000)); // starts; settles for 800 ms
      now += 300;
      backend.position = const Duration(milliseconds: 10600); // 300 ms ahead: ignored
      final seeks = backend.seekCount;
      await core.onSync(msg(pos: 10300));
      expect(backend.seekCount, seeks);
      expect(backend.speed, 1.0);
      // The drift is still shown honestly.
      expect(core.status.driftMs, closeTo(300, 2));
    });

    test('a little ahead: plays 1% slower until it is close', () async {
      await startThen();
      await second(60);
      expect(backend.speed, closeTo(0.99, 1e-9));
      await second(30);
      expect(backend.speed, closeTo(0.99, 1e-9));
      await second(3);
      await second(3);
      await second(3); // the recent readings are now mostly small
      expect(backend.speed, 1.0);
    });

    test('a little behind: plays 1% faster', () async {
      await startThen();
      await second(-60);
      expect(backend.speed, closeTo(1.01, 1e-9));
    });

    test('in between the limits it does not flip-flop', () async {
      await startThen();
      await second(40);
      expect(backend.speed, closeTo(0.99, 1e-9));
      await second(12);
      await second(12);
      await second(12);
      expect(backend.speed, closeTo(0.99, 1e-9),
          reason: 'keeps its speed until it is under 8 ms');
    });

    test('one noisy reading among good ones does nothing', () async {
      await startThen();
      await second(2);
      await second(3);
      await second(2);
      await second(95); // a glitch in the position reading
      await second(2);
      expect(backend.speed, 1.0);
    });

    test('far off once is not enough to jump; twice in a row is', () async {
      await startThen();
      final before = backend.seekCount;
      await second(-800); // 800 ms behind, first time
      expect(backend.seekCount, before, reason: 'could be a glitch');
      await second(-800);
      expect(backend.seekCount, before + 1, reason: 'confirmed: jumped');
    });

    test('it does not keep jumping: a pause between jumps', () async {
      await startThen();
      await second(-800);
      await second(-800); // jumps
      final seeks = backend.seekCount;
      // Still far off straight away (the seek did not take): not again so soon.
      // (The Player's own position carries on normally.)
      for (var i = 0; i < 3; i++) {
        now += 300;
        backend.position = const Duration(milliseconds: 5000);
        await core.onSync(msg(pos: 11000 + (now - 6000).round()));
      }
      expect(backend.seekCount, seeks);
    });

    test('seeking on the Player is followed at once', () async {
      await startThen();
      now += 1000;
      backend.position = const Duration(milliseconds: 12000);
      await core.onSync(msg(pos: 12000));
      now += 1000;
      backend.position = const Duration(milliseconds: 13000);
      await core.onSync(msg(pos: 60000)); // the Player jumped to 1:00
      expect(backend.position.inMilliseconds, 60000);
    });

    test('the Player pausing pauses this phone at the same spot', () async {
      await startThen();
      now += 1000;
      await core.onSync(msg(pos: 20000, playing: false));
      expect(backend.playing, isFalse);
      expect(backend.position.inMilliseconds, 20000);
      expect(core.status.message, contains('Paused'));
      // And resuming starts right where it should.
      now += 5000;
      await core.onSync(msg(pos: 20000, playing: true));
      expect(backend.playing, isTrue);
      expect(backend.position.inMilliseconds, 20000);
    });

    test('a new song starts from its beginning', () async {
      audio.ready[2] = '/cache/2.mp3';
      await startThen();
      await core.onSync(msg(song: 2, pos: 150));
      expect(backend.loaded, ['/cache/1.mp3', '/cache/2.mp3']);
      expect(backend.playing, isTrue);
      expect(backend.position.inMilliseconds, 150);
    });

    test('the Player changing speed is followed', () async {
      await startThen();
      backend.position = const Duration(milliseconds: 11000);
      await core.onSync(msg(pos: 11000, speed: 1.25));
      expect(backend.speed, 1.25);
    });

    test('nothing playable on the Player: this phone goes quiet', () async {
      await startThen();
      await core.onSync(msg(song: null, pos: 0, playing: false));
      expect(backend.playing, isFalse);
      expect(core.status.phase, GroupPhase.idle);
      expect(core.status.message, contains('library'));
    });

    test('stop leaves it silent, and it can start again', () async {
      await startThen();
      await core.stop();
      expect(backend.playing, isFalse);
      await core.onSync(msg()); // ignored while stopped
      expect(backend.playing, isFalse);
      core.reset();
      await core.onSync(msg(pos: 3000));
      expect(backend.playing, isTrue);
    });

    test('an audio problem is reported, not thrown', () async {
      backend.unplayable.add('/cache/1.mp3');
      await core.onSync(msg());
      expect(core.status.phase, GroupPhase.problem);
      expect(core.status.message, contains('play along'));
    });

    test('muting silences this phone but keeps it in step', () async {
      await startThen();
      await core.setMuted(true);
      expect(backend.volume, 0.0);
      expect(backend.playing, isTrue, reason: 'still playing, just silent');
      await second(2);
      expect(core.isPlayingAlong, isTrue);
      await core.setMuted(false);
      expect(backend.volume, 1.0);
    });

    test('stopping always gives the volume back', () async {
      await startThen();
      await core.setMuted(true);
      await core.stop();
      expect(backend.volume, 1.0);
    });

    test('staying far off for a long time is reported honestly', () async {
      await startThen();
      // 60 ms off, second after second, and the correction never takes.
      for (var i = 0; i < 6; i++) {
        await second(60);
      }
      expect(core.status.warning, isEmpty, reason: 'not yet: give it a chance');
      for (var i = 0; i < 10; i++) {
        await second(60);
      }
      expect(core.status.warning, contains("Can't stay in step"));
      expect(core.status.warning, contains('Auto-align'));
      // When it recovers the warning goes away.
      for (var i = 0; i < 6; i++) {
        await second(2);
      }
      expect(core.status.warning, isEmpty);
    });
  });

  test('a message that arrives while one is being handled is not lost', () async {
    // Handle two in a row without waiting: the newest wins.
    final a = core.onSync(msg(pos: 10000));
    now += 500;
    final b = core.onSync(msg(pos: 10500));
    await Future.wait([a, b]);
    expect(backend.playing, isTrue);
    expect(backend.position.inMilliseconds, closeTo(10500, 5));
  });
}
