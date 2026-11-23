import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/online/relay.dart';
import 'package:remote_tunes/core/online/room_code.dart';

import 'helpers/in_memory_relay.dart';

void main() {
  group('RoomCode', () {
    test('generates 8 symbols from the look-alike-free alphabet', () {
      final r = Random(1);
      for (var i = 0; i < 200; i++) {
        final c = RoomCode.generate(r);
        expect(c, hasLength(8));
        expect(RoomCode.isValid(c), isTrue, reason: c);
        expect(c, isNot(matches(RegExp(r'[01ILO]'))));
      }
    });

    test('is random: no repeats across many codes, and not a fixed sequence', () {
      final codes = {for (var i = 0; i < 2000; i++) RoomCode.generate()};
      expect(codes.length, 2000);
    });

    test('uses every position of the alphabet eventually (no biased slice)', () {
      final seen = <String>{};
      final r = Random(7);
      for (var i = 0; i < 400; i++) {
        seen.addAll(RoomCode.generate(r).split(''));
      }
      expect(seen.length, RoomCode.alphabet.length);
    });

    test('channel name follows remotetunes:<room-code>', () {
      expect(RoomCode.channelName('ABCD2345'), 'remotetunes:ABCD2345');
    });

    test('normalize accepts dashes, spaces and lower case', () {
      expect(RoomCode.normalize(' abcd-2345 '), 'ABCD2345');
      expect(RoomCode.normalize('ab cd_23 45'), 'ABCD2345');
      expect(RoomCode.isValid(RoomCode.normalize('abcd-2345')), isTrue);
    });

    test('format shows two groups of four', () {
      expect(RoomCode.format('ABCD2345'), 'ABCD-2345');
      expect(RoomCode.format('SHORT'), 'SHORT');
    });

    test('problem explains what is wrong, in plain words', () {
      expect(RoomCode.problem(''), contains('Enter the room code'));
      expect(RoomCode.problem('ABC'), contains('8 letters and numbers'));
      expect(RoomCode.problem('ABCD-23456'), contains('8 letters and numbers'));
      expect(RoomCode.problem('ABCD-2340'), contains('never used'));
      expect(RoomCode.problem('ABCDEFGI'), contains('never used'));
      expect(RoomCode.problem('abcd 2345'), isNull);
    });
  });

  group('RelayFrame', () {
    test('round-trips', () {
      const f = RelayFrame(from: 'c-1', to: 'player', message: '{"type":"ping"}');
      final back = RelayFrame.fromPayload(f.toPayload())!;
      expect(back.from, 'c-1');
      expect(back.to, 'player');
      expect(back.message, '{"type":"ping"}');
    });

    test('accepts the shape Supabase delivers (payload nested under "payload")', () {
      const f = RelayFrame(from: 'c-1', to: 'player', message: '{}');
      final wrapped = {'type': 'broadcast', 'event': 'rt', 'payload': f.toPayload()};
      expect(RelayFrame.fromPayload(wrapped)!.from, 'c-1');
    });

    test('ignores junk from other participants', () {
      for (final bad in [
        null,
        'text',
        42,
        <String, dynamic>{},
        {'from': 'a'},
        {'from': 'a', 'to': 'b'},
        {'from': 1, 'to': 'b', 'm': 'x'},
        {'from': '', 'to': 'b', 'm': 'x'},
        {'from': 'a' * 65, 'to': 'b', 'm': 'x'},
        {'payload': 'nope'},
      ]) {
        expect(RelayFrame.fromPayload(bad), isNull, reason: '$bad');
      }
    });
  });

  group('InMemoryRelayHub (test double sanity)', () {
    test('broadcasts to others in the same room only, never to the sender', () async {
      final hub = InMemoryRelayHub();
      final a = hub.channel('R1')..join();
      final b = hub.channel('R1')..join();
      final other = hub.channel('R2')..join();
      await Future<void>.delayed(Duration.zero);
      final gotA = <RelayFrame>[], gotB = <RelayFrame>[], gotOther = <RelayFrame>[];
      a.frames.listen(gotA.add);
      b.frames.listen(gotB.add);
      other.frames.listen(gotOther.add);

      await a.send(const RelayFrame(from: 'a', to: 'b', message: 'hi'));
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(gotB.single.message, 'hi');
      expect(gotA, isEmpty);
      expect(gotOther, isEmpty);
      expect(hub.membersIn('R1'), 2);
    });

    test('join fails when offline; send fails before join', () async {
      final hub = InMemoryRelayHub()..offline = true;
      await expectLater(hub.channel('R').join(), throwsA(isA<RelayException>()));
      await expectLater(
        hub.channel('R').send(const RelayFrame(from: 'a', to: 'b', message: 'x')),
        throwsA(isA<RelayException>()),
      );
    });
  });
}
