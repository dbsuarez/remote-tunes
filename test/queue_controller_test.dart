import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/features/player/queue/playable_song.dart';
import 'package:remote_tunes/features/player/queue/queue_controller.dart';

PlayableSong song(int id) => PlayableSong(
      id: id,
      title: 'Song $id',
      artist: 'Artist',
      album: 'Album',
      filePath: '/music/$id.mp3',
      durationSeconds: 100,
    );

List<PlayableSong> songs(int n) => [for (var i = 1; i <= n; i++) song(i)];

/// Song ids in display order.
List<int> ids(QueueController q) => [for (final e in q.entries) e.song.id];

void main() {
  late QueueController q;

  setUp(() => q = QueueController(random: Random(42)));

  group('basics', () {
    test('replace sets the entries and current position', () {
      q.replace(songs(4), startIndex: 2);
      expect(ids(q), [1, 2, 3, 4]);
      expect(q.current!.song.id, 3);
      expect(q.currentIndex, 2);
    });

    test('replace with an empty list clears the current entry', () {
      q.replace(songs(2));
      q.replace([]);
      expect(q.current, isNull);
      expect(q.currentIndex, -1);
      expect(q.isEmpty, isTrue);
    });

    test('the same song can be queued twice with distinct entry ids', () {
      q.replace([song(1)]);
      q.add([song(1)]);
      expect(q.entries.map((e) => e.id).toSet(), hasLength(2));
    });

    test('revision bumps on content changes only', () {
      q.replace(songs(3));
      final r = q.revision;
      q.jumpTo(q.entries[1].id);
      q.advance(auto: false);
      q.setShuffle(true);
      q.setRepeat(RepeatMode.queue);
      expect(q.revision, r);
      q.add([song(9)]);
      expect(q.revision, r + 1);
      q.move(q.entries.first.id, 2);
      expect(q.revision, r + 2);
      q.clear();
      expect(q.revision, r + 3);
    });
  });

  group('advance / back', () {
    test('plays in order and stops at the end with repeat off', () {
      q.replace(songs(3));
      expect(q.advance(auto: true)!.song.id, 2);
      expect(q.advance(auto: true)!.song.id, 3);
      expect(q.advance(auto: true), isNull);
      expect(q.current!.song.id, 3, reason: 'stays on the last track');
    });

    test('repeat queue wraps to the first track', () {
      q.setRepeat(RepeatMode.queue);
      q.replace(songs(2));
      q.advance(auto: true);
      expect(q.advance(auto: true)!.song.id, 1);
    });

    test('repeat one replays on auto-advance but manual next moves on', () {
      q.setRepeat(RepeatMode.one);
      q.replace(songs(3));
      expect(q.advance(auto: true)!.song.id, 1);
      expect(q.advance(auto: false)!.song.id, 2);
    });

    test('back goes to the previous track, or restarts at the start', () {
      q.replace(songs(3), startIndex: 2);
      expect(q.back()!.song.id, 2);
      expect(q.back()!.song.id, 1);
      expect(q.back()!.song.id, 1, reason: 'start of queue: caller restarts');
    });

    test('back wraps to the last track with repeat queue', () {
      q.setRepeat(RepeatMode.queue);
      q.replace(songs(3));
      expect(q.back()!.song.id, 3);
    });

    test('advance on an empty queue returns null; with no current it starts', () {
      expect(q.advance(auto: false), isNull);
      q.replace(songs(2));
      q.remove(q.entries[0].id);
      q.remove(q.entries[0].id);
      expect(q.advance(auto: false), isNull);
    });
  });

  group('add / remove / move / clear', () {
    test('add appends; playNext inserts after the current entry', () {
      q.replace(songs(3), startIndex: 1);
      q.add([song(10)]);
      expect(ids(q), [1, 2, 3, 10]);
      q.add([song(11), song(12)], playNext: true);
      expect(ids(q), [1, 2, 11, 12, 3, 10]);
      expect(q.advance(auto: false)!.song.id, 11);
      expect(q.advance(auto: false)!.song.id, 12);
      expect(q.advance(auto: false)!.song.id, 3);
    });

    test('removing a non-current entry keeps the current one', () {
      q.replace(songs(3), startIndex: 1);
      final r = q.remove(q.entries[2].id);
      expect(r.removed, isTrue);
      expect(r.wasCurrent, isFalse);
      expect(q.current!.song.id, 2);
      expect(ids(q), [1, 2]);
    });

    test('removing the current entry selects the next one', () {
      q.replace(songs(3), startIndex: 1);
      final r = q.remove(q.current!.id);
      expect(r.wasCurrent, isTrue);
      expect(q.current!.song.id, 3);
    });

    test('removing the current last entry leaves nothing current', () {
      q.replace(songs(2), startIndex: 1);
      q.remove(q.current!.id);
      expect(q.current, isNull);
    });

    test('removing an unknown id does nothing', () {
      q.replace(songs(2));
      expect(q.remove(9999).removed, isFalse);
      expect(q.length, 2);
    });

    test('move reorders and keeps the current entry', () {
      q.replace(songs(4), startIndex: 0);
      q.move(q.entries[0].id, 3);
      expect(ids(q), [2, 3, 4, 1]);
      expect(q.current!.song.id, 1);
      expect(q.currentIndex, 3);
      q.move(q.entries[3].id, 99); // clamps
      expect(ids(q), [2, 3, 4, 1]);
      q.move(q.entries[0].id, -5); // clamps
      expect(ids(q), [2, 3, 4, 1]);
      expect(q.move(9999, 0), isFalse);
    });

    test('moves are followed by playback order when not shuffled', () {
      q.replace(songs(3), startIndex: 0);
      q.move(q.entries[2].id, 1); // [1,3,2]
      expect(q.advance(auto: false)!.song.id, 3);
      expect(q.advance(auto: false)!.song.id, 2);
    });

    test('clear empties everything', () {
      q.replace(songs(3));
      q.clear();
      expect(q.isEmpty, isTrue);
      expect(q.current, isNull);
    });

    test('jumpTo selects an entry and rejects unknown ids', () {
      q.replace(songs(3));
      expect(q.jumpTo(q.entries[2].id), isTrue);
      expect(q.current!.song.id, 3);
      expect(q.jumpTo(9999), isFalse);
    });
  });

  group('shuffle', () {
    test('plays every track exactly once, current first', () {
      q.replace(songs(8), startIndex: 3);
      q.setShuffle(true);
      final played = [q.current!.song.id];
      for (var i = 0; i < 7; i++) {
        played.add(q.advance(auto: true)!.song.id);
      }
      expect(played.first, 4);
      expect(played.toSet(), {1, 2, 3, 4, 5, 6, 7, 8});
      expect(q.advance(auto: true), isNull);
    });

    test('shuffle does not change the display order', () {
      q.replace(songs(6));
      q.setShuffle(true);
      expect(ids(q), [1, 2, 3, 4, 5, 6]);
    });

    test('turning shuffle off restores sequential play from the current track', () {
      q.replace(songs(5), startIndex: 1);
      q.setShuffle(true);
      q.setShuffle(false);
      expect(q.advance(auto: false)!.song.id, 3);
      expect(q.advance(auto: false)!.song.id, 4);
    });

    test('tracks added while shuffled still get played', () {
      q.replace(songs(3));
      q.setShuffle(true);
      q.add([song(10)]);
      final played = {q.current!.song.id};
      QueueEntry? e;
      while ((e = q.advance(auto: true)) != null) {
        played.add(e!.song.id);
      }
      expect(played, {1, 2, 3, 10});
    });

    test('repeat queue + shuffle reshuffles and does not repeat the last track first',
        () {
      q.setRepeat(RepeatMode.queue);
      q.replace(songs(5));
      q.setShuffle(true);
      for (var round = 0; round < 20; round++) {
        QueueEntry? last;
        for (var i = 0; i < 4; i++) {
          last = q.advance(auto: true);
        }
        final lastId = last!.song.id;
        final first = q.advance(auto: true)!;
        expect(first.song.id, isNot(lastId));
      }
    });

    test('display moves do not disturb a shuffled play order', () {
      q.replace(songs(6));
      q.setShuffle(true);
      final before = <int>[];
      var c = q.current!;
      before.add(c.song.id);
      for (var i = 0; i < 5; i++) {
        before.add(q.advance(auto: true)!.song.id);
      }
      // Re-run the same shuffle with the same seed, moving entries around.
      final q2 = QueueController(random: Random(42));
      q2.replace(songs(6));
      q2.setShuffle(true);
      q2.move(q2.entries[0].id, 5);
      q2.move(q2.entries[1].id, 0);
      final after = [q2.current!.song.id];
      for (var i = 0; i < 5; i++) {
        after.add(q2.advance(auto: true)!.song.id);
      }
      expect(after, before);
    });
  });

  group('shuffle keeps track of what has played', () {
    /// Plays through with Next and returns the song ids in the order they came.
    List<int> playRound(QueueController q, int count) {
      final out = <int>[q.current!.song.id];
      for (var i = 1; i < count; i++) {
        final next = q.advance(auto: false);
        if (next == null) break;
        out.add(next.song.id);
      }
      return out;
    }

    test('every song plays once before any plays again', () {
      for (var seed = 0; seed < 20; seed++) {
        final q = QueueController(random: Random(seed))
          ..replace(songs(8))
          ..setShuffle(true);
        final round = playRound(q, 8);
        expect(round.toSet().length, 8, reason: 'seed $seed: $round');
      }
    });

    test('at the end with repeat off, it stops (nothing is repeated)', () {
      final q = QueueController(random: Random(1))
        ..replace(songs(5))
        ..setShuffle(true);
      playRound(q, 5);
      expect(q.advance(auto: false), isNull);
    });

    test('with repeat on, a new round plays everything again, and the round change is not the same song twice',
        () {
      for (var seed = 0; seed < 20; seed++) {
        final q = QueueController(random: Random(seed))
          ..replace(songs(6))
          ..setShuffle(true)
          ..setRepeat(RepeatMode.queue);
        final all = playRound(q, 12);
        expect(all.sublist(0, 6).toSet().length, 6, reason: 'round one, seed $seed');
        expect(all.sublist(6, 12).toSet().length, 6, reason: 'round two, seed $seed');
        expect(all[5], isNot(all[6]), reason: 'no song twice in a row, seed $seed');
      }
    });

    test('choosing a song counts it as played: it does not come round again, the others still do',
        () {
      final q = QueueController(random: Random(3))
        ..replace(songs(6))
        ..setShuffle(true);
      final first = q.current!.song.id;
      final target = q.entries.last; // jump to a song far away
      q.jumpTo(target.id);
      final rest = <int>[];
      for (var i = 0; i < 4; i++) {
        rest.add(q.advance(auto: false)!.song.id);
      }
      expect(rest, isNot(contains(target.song.id)));
      expect(rest, isNot(contains(first)));
      expect(rest.toSet().length, 4, reason: 'the four others each came once: $rest');
      expect(q.advance(auto: false), isNull);
    });

    test('choosing a song that already played does not make it play twice more', () {
      final q = QueueController(random: Random(5))
        ..replace(songs(5))
        ..setShuffle(true);
      final first = q.current!;
      q.advance(auto: false);
      q.advance(auto: false);
      q.jumpTo(first.id); // back to the first one on purpose
      final next = <int>[];
      while (true) {
        final n = q.advance(auto: false);
        if (n == null) break;
        next.add(n.song.id);
      }
      expect(next.where((i) => i == first.song.id), isEmpty);
      expect(next.toSet().length, next.length, reason: 'no repeats: $next');
    });

    test('Back goes to what really played, and Next goes the same way again', () {
      final q = QueueController(random: Random(7))
        ..replace(songs(6))
        ..setShuffle(true);
      final a = q.current!.song.id;
      final b = q.advance(auto: false)!.song.id;
      final c = q.advance(auto: false)!.song.id;
      expect(q.back()!.song.id, b);
      expect(q.back()!.song.id, a);
      expect(q.advance(auto: false)!.song.id, b, reason: 'the same song, not a new one');
      expect(q.advance(auto: false)!.song.id, c);
      expect(q.peekNext()?.song.id, isNot(anyOf(a, b, c)));
    });

    test('peekNext is the song that will really come, even after Back', () {
      final q = QueueController(random: Random(9))
        ..replace(songs(6))
        ..setShuffle(true);
      q.advance(auto: false);
      final peek = q.peekNext()!;
      expect(q.advance(auto: false)!.id, peek.id);
      q.back();
      expect(q.peekNext()!.id, peek.id);
    });

    test('Play next comes right after the song playing', () {
      final q = QueueController(random: Random(2))
        ..replace(songs(5))
        ..setShuffle(true);
      final added = q.add([song(99)], playNext: true);
      expect(q.advance(auto: false)!.id, added.single.id);
    });

    test('a song added to the queue joins the round: it plays once, in what is still to come', () {
      final q = QueueController(random: Random(4))
        ..replace(songs(4))
        ..setShuffle(true);
      q.add([song(50)]);
      final round = playRound(q, 5);
      expect(round.toSet().length, 5);
      expect(round, contains(50));
    });

    test('removing a song takes it out of the round', () {
      final q = QueueController(random: Random(6))
        ..replace(songs(5))
        ..setShuffle(true);
      final gone = q.peekNext()!;
      q.remove(gone.id);
      final round = playRound(q, 4);
      expect(round.toSet().length, 4);
      expect(round, isNot(contains(gone.song.id)));
    });

    test('removing the song playing moves on to the next one of the round', () {
      final q = QueueController(random: Random(8))
        ..replace(songs(5))
        ..setShuffle(true);
      final expected = q.peekNext()!;
      final r = q.remove(q.current!.id);
      expect(r.wasCurrent, isTrue);
      expect(q.current!.id, expected.id);
    });

    test('turning shuffle off goes back to the list order from the song playing', () {
      final q = QueueController(random: Random(11))
        ..replace(songs(5))
        ..setShuffle(true);
      q.advance(auto: false);
      final at = q.current!.song.id;
      q.setShuffle(false);
      expect(q.advance(auto: false)?.song.id, at == 5 ? isNull : at + 1);
    });

    test('turning shuffle on mid-song: the song playing counts as played', () {
      final q = QueueController(random: Random(13))..replace(songs(6), startIndex: 2);
      q.setShuffle(true);
      final cur = q.current!.song.id;
      final rest = <int>[];
      while (true) {
        final n = q.advance(auto: false);
        if (n == null) break;
        rest.add(n.song.id);
      }
      expect(rest.length, 5);
      expect(rest, isNot(contains(cur)));
    });
  });
}
