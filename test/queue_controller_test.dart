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
}
