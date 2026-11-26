import 'dart:math';
import 'dart:typed_data';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/features/ambience/ambience_controller.dart';
import 'package:remote_tunes/features/ambience/ambience_icons.dart';
import 'package:remote_tunes/features/ambience/ambience_models.dart';
import 'package:remote_tunes/features/ambience/ambience_noise.dart';

class FakeEngine implements AmbienceEngine {
  final voices = <String, double>{};
  final paths = <String, String>{};
  bool paused = false;
  final broken = <String>{};

  @override
  Future<void> start(String id, String path, double volume) async {
    if (broken.contains(id)) throw Exception('bad file');
    voices[id] = volume;
    paths[id] = path;
  }

  @override
  Future<void> setVolume(String id, double volume) async {
    if (voices.containsKey(id)) voices[id] = volume;
  }

  @override
  Future<void> stop(String id) async => voices.remove(id);
  @override
  Future<void> setPaused(bool v) async => paused = v;
  @override
  Future<void> stopAll() async => voices.clear();

  /// Files already at the level the app aims for, unless a test says otherwise.
  final levels = <String, ({double rms, double peak})>{};
  final measured = <String>[];
  @override
  Future<({double rms, double peak})?> measure(String path) async {
    measured.add(path);
    return levels[path] ?? (rms: ambienceLoudness, peak: 0.5);
  }
}

class _Unmeasured extends FakeEngine {
  @override
  Future<({double rms, double peak})?> measure(String path) async => throw Exception('cannot');
}

class FakeFiles implements AmbienceFiles {
  final removed = <String>[];
  @override
  Future<String?> pathFor(String soundId, String? saved) async => saved ?? '/noise/$soundId.wav';
  @override
  Future<String> add(String soundId, String sourcePath) async => '/kept/$soundId.${sourcePath.split('.').last}';
  @override
  Future<void> remove(String saved) async => removed.add(saved);
  final written = <String, Uint8List>{};
  @override
  Future<String> write(String name, Uint8List bytes) async {
    final saved = '$name-${written.length + 1}.png';
    written[saved] = bytes;
    return saved;
  }
}

class MemoryAmbienceStore implements AmbienceStore {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async => value = v;
}

void main() {
  late FakeEngine engine;
  late FakeFiles files;
  late MemoryAmbienceStore store;
  var musicPaused = 0;

  setUp(() {
    engine = FakeEngine();
    files = FakeFiles();
    store = MemoryAmbienceStore();
    musicPaused = 0;
  });

  AmbienceController make({DateTime Function()? now}) =>
      AmbienceController(engine: engine, files: files, store: store, pauseMusic: () async => musicPaused++, now: now);

  Matcher about(double v) => closeTo(v, 0.001);

  group('sounds', () {
    test('only the noises can be played before files are added', () async {
      final c = make();
      await c.load();
      expect([for (final s in c.state.sounds) if (s.available) s.id],
          ['white-noise', 'pink-noise', 'brown-noise', 'green-noise', 'blue-noise', 'gray-noise']);
      await expectLater(c.setActive('rain', true), throwsA(isA<AmbienceException>()));
      expect(engine.voices, isEmpty);
    });

    test('switching one on pauses the music and plays it; many play together', () async {
      final c = make();
      await c.setMaster(1);
      await c.setActive('white-noise', true);
      expect(musicPaused, 1);
      expect(c.state.playing, isTrue);
      await c.addFile('rain', '/down/rain.mp3');
      await c.setActive('rain', true);
      await c.setActive('brown-noise', true);
      expect(engine.voices.keys, {'white-noise', 'rain', 'brown-noise'});
      expect(engine.paths['rain'], '/kept/rain.mp3');
      await c.setActive('rain', false);
      expect(engine.voices.keys, {'white-noise', 'brown-noise'});
    });

    test('each has its own volume, under the master volume', () async {
      final c = make();
      await c.setMaster(0.5);
      await c.setActive('white-noise', true);
      await c.setActive('pink-noise', true);
      await c.setVolume('pink-noise', 0.8);
      expect(engine.voices['white-noise'], about(0.25));
      expect(engine.voices['pink-noise'], about(0.4));
      await c.setMaster(1);
      expect(engine.voices['pink-noise'], about(0.8));
    });

    test('the maximum caps the master volume, also later', () async {
      final c = make();
      await c.setActive('white-noise', true);
      await c.setVolume('white-noise', 1);
      await c.setMaxVolume(0.4);
      expect(engine.voices['white-noise'], about(0.4));
      expect(c.state.master, about(0.4));
      await c.setMaster(1);
      expect(engine.voices['white-noise'], about(0.4));
      expect(c.state.maxVolume, about(0.4));
    });

    test('pause holds, play goes on, stop silences but remembers what was on', () async {
      final c = make();
      await c.setActive('white-noise', true);
      await c.pause();
      expect((c.state.playing, engine.paused), (false, true));
      await c.play();
      expect((c.state.playing, engine.paused), (true, false));
      await c.stop();
      expect(engine.voices, isEmpty);
      expect(c.state.active.keys, ['white-noise']);
      await c.play();
      expect(engine.voices.keys, ['white-noise']);
    });

    test('switching the last one off stops', () async {
      final c = make();
      await c.setActive('white-noise', true);
      await c.setActive('white-noise', false);
      expect(c.state.playing, isFalse);
    });

    test('music starting stops the ambience', () async {
      final c = make();
      await c.setActive('white-noise', true);
      await c.musicStarted();
      expect((c.state.playing, engine.voices.length), (false, 0));
    });

    test('a file that cannot be played is switched off and named', () async {
      final c = make();
      await c.addFile('owls', '/d/owls.ogg');
      engine.broken.add('owls');
      await c.setActive('owls', true);
      expect(c.state.active, isEmpty);
      expect(c.state.playing, isFalse);
      expect(c.state.error, contains('Owls'));
    });
  });

  group('files', () {
    test('only sound files the player can loop are taken', () async {
      final c = make();
      await expectLater(c.addFile('rain', '/d/rain.m4a'), throwsA(isA<AmbienceException>()));
      await c.addFile('rain', '/d/RAIN.MP3');
      expect(c.state.sound('rain')!.available, isTrue);
    });

    test('a new file replaces the old one, also while playing', () async {
      final c = make();
      await c.addFile('rain', '/d/a.mp3');
      await c.setActive('rain', true);
      await c.addFile('rain', '/d/b.ogg');
      expect(engine.paths['rain'], '/kept/rain.ogg');
      expect(files.removed, ['/kept/rain.mp3']);
    });

    test('a sound of your own has your name, and goes when removed', () async {
      final c = make();
      await c.addOwnSound('  Lullaby box ', '/d/box.wav');
      final own = c.state.sounds.last;
      expect((own.name, own.category, own.available), ('Lullaby box', ambienceOwnCategory, true));
      await c.setActive(own.id, true);
      await c.removeFile(own.id);
      expect(c.state.sound(own.id), isNull);
      expect(engine.voices, isEmpty);
      await expectLater(c.addOwnSound('x', '/d/x.txt'), throwsA(isA<AmbienceException>()));
      expect(c.state.sounds, hasLength(ambienceCatalog.length));
    });
  });

  test('sounds added in the same instant are still separate', () async {
    final c = make(now: () => DateTime(2026));
    await c.addOwnSound('One', '/d/1.wav');
    await c.addOwnSound('Two', '/d/2.wav', environment: true);
    await c.addOwnSound('Three', '/d/3.wav');
    expect([for (final s in c.state.sounds.skip(ambienceCatalog.length)) s.name], ['Two', 'One', 'Three']);
  });

  group('mixes', () {
    test('a preset plays what it has and names what is missing', () async {
      final c = make();
      final missing = await c.startMix('sleep');
      expect(missing, ['Morning Rain']);
      expect(engine.voices.keys, ['white-noise']);
      expect(c.state.mixName, 'Sleep');
    });

    test('a preset with nothing to play says what to add and keeps what is on', () async {
      final c = make();
      await c.setActive('pink-noise', true);
      await expectLater(c.startMix('campfire'),
          throwsA(isA<AmbienceException>().having((e) => e.message, 'message', 'Add files for Campfire and Light Wind first.')));
      expect(engine.voices.keys, ['pink-noise']);
    });

    test('your own mix is saved with the volumes, replaced by name, and deleted', () async {
      final c = make();
      await c.setActive('white-noise', true);
      await c.setActive('brown-noise', true);
      await c.setVolume('brown-noise', 0.9);
      await c.saveMix(' Pampatulog ');
      final mine = c.state.mixes.last;
      expect((mine.name, mine.builtIn), ('Pampatulog', false));
      await c.setActive('brown-noise', false);
      expect(c.state.mixName, isNull, reason: 'changed since');
      await c.startMix(mine.id);
      expect(c.state.active, {'white-noise': 0.5, 'brown-noise': 0.9});
      await c.saveMix('pampatulog');
      expect(c.state.mixes, hasLength(ambiencePresets.length + 1));
      await c.deleteMix(mine.id);
      expect(c.state.mixes, hasLength(ambiencePresets.length));
    });

    test('a mix needs a name and something switched on', () async {
      final c = make();
      await expectLater(c.saveMix('x'), throwsA(isA<AmbienceException>()));
      await c.setActive('white-noise', true);
      await expectLater(c.saveMix('  '), throwsA(isA<AmbienceException>()));
    });

    test('everything is there again after a restart, silent', () async {
      final c = make();
      await c.addFile('rain', '/d/rain.mp3');
      await c.addOwnSound('Box', '/d/box.wav');
      await c.setActive('rain', true);
      await c.setMaxVolume(0.6);
      await c.setTimer(30);
      await c.saveMix('Night');
      engine.voices.clear();
      final again = make();
      await again.load();
      final s = again.state;
      expect(s.playing, isFalse);
      expect(s.active.keys, ['rain']);
      expect((s.maxVolume, s.timerMinutes, s.secondsLeft), (0.6, 30, 1800));
      expect(s.mixes.last.name, 'Night');
      expect(s.sounds.last.name, 'Box');
    });

    test('damaged settings start afresh', () async {
      store.value = '{not json';
      final c = make();
      await c.load();
      expect(c.state.active, isEmpty);
    });
  });

  group('the sleep timer', () {
    void timed(void Function(FakeAsync async, AmbienceController c) body) {
      fakeAsync((async) {
        final start = DateTime(2026);
        final c = make(now: () => start.add(async.elapsed));
        c.setMaster(1);
        c.setActive('white-noise', true);
        c.setVolume('white-noise', 1);
        async.flushMicrotasks();
        body(async, c);
        c.dispose();
      });
    }

    test('plays at full volume, fades over the last five minutes, then stops', () {
      timed((async, c) {
        c.setTimer(15);
        async.elapse(const Duration(minutes: 10));
        expect(engine.voices['white-noise'], about(1));
        async.elapse(const Duration(minutes: 2, seconds: 30));
        expect(engine.voices['white-noise'], closeTo(0.5, 0.01));
        expect(c.state.secondsLeft, 150);
        async.elapse(const Duration(minutes: 2, seconds: 31));
        expect(engine.voices, isEmpty);
        expect(c.state.playing, isFalse);
        expect(c.state.secondsLeft, 900, reason: 'ready for the next time');
      });
    });

    test('does not run while paused', () {
      timed((async, c) {
        c.setTimer(30);
        async.elapse(const Duration(minutes: 10));
        c.pause();
        async.elapse(const Duration(hours: 2));
        expect(c.state.secondsLeft, 1200);
        c.play();
        async.elapse(const Duration(minutes: 5));
        expect(c.state.secondsLeft, 900);
        expect(c.state.playing, isTrue);
      });
    });

    test('can be changed or taken off while fading, and the volume comes back', () {
      timed((async, c) {
        c.setTimer(15);
        async.elapse(const Duration(minutes: 13));
        expect(engine.voices['white-noise']!, lessThan(0.5));
        c.setTimer(null);
        async.flushMicrotasks();
        expect(engine.voices['white-noise'], about(1));
        async.elapse(const Duration(hours: 3));
        expect(c.state.playing, isTrue);
      });
    });
  });

  group('the made noise', () {
    for (final color in NoiseColor.values) {
      test('${color.name} is a good loop', () {
        final wav = noiseWav(color, seconds: 2, random: Random(1));
        final d = ByteData.sublistView(wav);
        expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
        expect(d.getUint32(40, Endian.little), noiseSampleRate * 4);
        expect(wav.length, 44 + noiseSampleRate * 4);
        final samples = [for (var i = 44; i < wav.length; i += 2) d.getInt16(i, Endian.little) / 32767];
        final loud = sqrt(samples.map((v) => v * v).reduce((a, b) => a + b) / samples.length);
        expect(loud, closeTo(0.18, 0.01));
        expect(samples.where((v) => v.abs() > 0.99).length, lessThan(samples.length ~/ 500));
        // The jump from the end to the start is no bigger than the usual step between samples.
        var steps = 0.0;
        for (var i = 1; i < samples.length; i++) {
          steps = max(steps, (samples[i] - samples[i - 1]).abs());
        }
        expect((samples.first - samples.last).abs(), lessThanOrEqualTo(steps));
      });
    }
  });

  group('loudness', () {
    test('quiet files are turned up and loud ones down, without clipping hard', () {
      expect(evenGain((rms: 0.01, peak: 0.05)), about(10));
      expect(evenGain((rms: 0.2, peak: 0.9)), about(0.5));
      expect(evenGain((rms: 0.005, peak: 0.5)), about(5), reason: 'loud crackles hold it back');
      expect(evenGain((rms: 0.0001, peak: 0.001)), 12, reason: 'never more than this');
      expect(evenGain((rms: 0, peak: 0)), 1, reason: 'silence is left alone');
      expect(evenGain(null), 1);
    });

    test('a quiet file plays louder, measured once', () async {
      final c = make();
      await c.setMaster(1);
      await c.addFile('rain', '/d/rain.mp3');
      engine.levels['/kept/rain.mp3'] = (rms: 0.02, peak: 0.1);
      await c.setActive('rain', true);
      expect(engine.voices['rain'], about(0.5 * 5));
      await c.stop();
      await c.play();
      expect(engine.measured, ['/kept/rain.mp3']);
      final again = make();
      await again.load();
      await again.play();
      expect(engine.measured, ['/kept/rain.mp3'], reason: 'remembered');
    });

    test('a new file is measured again', () async {
      final c = make();
      await c.addFile('rain', '/d/a.mp3');
      await c.setActive('rain', true);
      await c.addFile('rain', '/d/b.ogg');
      expect(engine.measured, ['/kept/rain.mp3', '/kept/rain.ogg']);
    });

    test('the owner can make a sound louder or softer, and the maximum still holds it', () async {
      final c = make();
      await c.setMaster(1);
      await c.setActive('white-noise', true);
      await c.setVolume('white-noise', 1);
      await c.setBoost('white-noise', 3);
      expect(engine.voices['white-noise'], about(3));
      expect(c.state.sound('white-noise')!.boost, 3);
      await c.setMaxVolume(0.5);
      expect(engine.voices['white-noise'], about(1.5));
      await c.setBoost('white-noise', 99);
      expect(c.state.sound('white-noise')!.boost, 4);
      await c.setBoost('white-noise', 1);
      expect(AmbienceState.fromJson(c.state.toJson()).sound('white-noise')!.boost, 1);
    });

    test('a file that cannot be measured plays as it is', () async {
      final broken = _Unmeasured();
      final c = AmbienceController(engine: broken, files: files, store: store);
      await c.setMaster(1);
      await c.setActive('white-noise', true);
      expect(broken.voices['white-noise'], about(0.5));
    });
  });

  group('the catalog', () {
    test('has the whole list, with unique ids and a picture each', () {
      final ids = [for (final s in ambienceCatalog) s.id];
      expect(ids.toSet(), hasLength(ids.length));
      expect(ids.length, greaterThan(150));
      expect(ids.every(ambienceDefaultPictures.containsKey), isTrue);
    });

    test('there are plenty of ready-made mixes, with their own ids and names', () {
      expect(ambiencePresets.length, greaterThan(25));
      expect({for (final m in ambiencePresets) m.id}, hasLength(ambiencePresets.length));
      expect({for (final m in ambiencePresets) m.name}, hasLength(ambiencePresets.length));
      final noise = {for (final s in ambienceCatalog) if (s.available) s.id};
      expect(ambiencePresets.where((m) => m.layers.keys.every(noise.contains)), isNotEmpty, reason: 'some work with nothing added');
    });

    test('keeps the ids sounds were saved under, and the mixes still point at sounds', () {
      final ids = {for (final s in ambienceCatalog) s.id};
      expect(ids, containsAll(['rain', 'light-rain', 'thunder', 'distant-thunder', 'ocean', 'seagulls', 'stream', 'crickets',
        'owls', 'frogs', 'campfire', 'wind', 'birds', 'white-noise', 'pink-noise', 'brown-noise']));
      expect([for (final m in ambiencePresets) ...m.layers.keys].every(ids.contains), isTrue);
    });

    test('every noise the app offers can be made', () {
      for (final s in ambienceCatalog.where((s) => s.available)) {
        expect(noiseColorOf(s.id), isNotNull, reason: s.id);
      }
    });

    test('the noises sound different: blue is bright, brown deep, green in between', () {
      double neighbours(NoiseColor c) {
        final d = ByteData.sublistView(noiseWav(c, seconds: 1, random: Random(3)));
        var same = 0.0, power = 0.0, before = 0.0;
        for (var i = 44; i < d.lengthInBytes; i += 2) {
          final v = d.getInt16(i, Endian.little).toDouble();
          same += v * before;
          power += v * v;
          before = v;
        }
        return same / power;
      }

      expect(neighbours(NoiseColor.blue), lessThan(-0.3));
      expect(neighbours(NoiseColor.white).abs(), lessThan(0.05));
      expect(neighbours(NoiseColor.brown), greaterThan(0.95));
      expect(neighbours(NoiseColor.green), allOf(greaterThan(0.75), lessThan(neighbours(NoiseColor.brown))));
      expect(neighbours(NoiseColor.gray), allOf(greaterThan(0.1), lessThan(0.95)));
    });

    test('the other phone is sent only what can be played', () {
      final c = make();
      final sent = AmbienceState.fromJson(c.state.toJson(readyOnly: true));
      expect(sent.sounds, hasLength(6));
    });
  });

  test('the state travels to the other phone and back', () {
    final s = AmbienceState(
      sounds: const [AmbienceSound(id: 'rain', name: 'Rain', category: 'Rain', available: true)],
      mixes: ambiencePresets,
      active: const {'rain': 0.4},
      playing: true,
      master: 0.3,
      maxVolume: 0.5,
      timerMinutes: 45,
      secondsLeft: 100,
      mixName: 'Sleep',
      error: 'x',
    );
    final back = AmbienceState.fromJson(s.toJson());
    expect(back.toJson(), s.toJson());
    expect(AmbienceState.fromJson('junk').sounds, isEmpty);
  });
}
