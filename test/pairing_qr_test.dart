import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/pairing_qr.dart';

void main() {
  test('encode then parse round-trips', () {
    const q = PairingQr(
        ticket: 'ABCDEFGH23', host: '192.168.1.20', port: 8765, roomCode: 'ABCDEFGH');
    final back = PairingQr.parse(q.encode())!;
    expect(back.ticket, 'ABCDEFGH23');
    expect(back.host, '192.168.1.20');
    expect(back.port, 8765);
    expect(back.roomCode, 'ABCDEFGH');
  });

  test('online-only and local-only codes parse', () {
    expect(PairingQr.parse(const PairingQr(ticket: 'ABCDEFGH23', roomCode: 'ABCDEFGH').encode())!.hasLocal, isFalse);
    expect(PairingQr.parse(const PairingQr(ticket: 'ABCDEFGH23', host: '10.0.0.2', port: 1).encode())!.hasOnline, isFalse);
  });

  test('the code is a link to the web Controller with everything after the #', () {
    const q = PairingQr(
        ticket: 'ABCDEFGH23', host: '192.168.1.20', port: 8765, roomCode: 'ABCDEFGH', playerName: 'GT30 Pro');
    final text = q.encode();
    final uri = Uri.parse(text);
    expect(text, startsWith('https://dbsuarez.github.io/remote-tunes/#/pair?'));
    expect(uri.query, isEmpty, reason: 'nothing reaches the web server');
    expect(PairingQr.parse(text)!.playerName, 'GT30 Pro');
  });

  test('the web page reads its own address fragment', () {
    final q = PairingQr.fromFragment('/pair?v=1&r=ABCDEFGH&t=ABCDEFGH23&n=GT30+Pro')!;
    expect(q.roomCode, 'ABCDEFGH');
    expect(q.ticket, 'ABCDEFGH23');
    expect(q.hasLocal, isFalse);
    expect(PairingQr.fromFragment(''), isNull);
    expect(PairingQr.fromFragment('/'), isNull);
    expect(PairingQr.fromFragment('/pair?v=1&r=ABCDEFGH'), isNull, reason: 'no ticket');
    expect(PairingQr.fromFragment('/pair?v=9&r=ABCDEFGH&t=ABCDEFGH23'), isNull);
  });

  test('the old remotetunes:// form still works', () {
    final q = PairingQr.parse('remotetunes://pair?v=1&h=1.2.3.4&p=8765&t=ABCDEFGH23')!;
    expect(q.host, '1.2.3.4');
  });

  test('links to other sites are not pairing codes', () {
    for (final bad in [
      'https://evil.example/remote-tunes/#/pair?v=1&r=ABCDEFGH&t=ABCDEFGH23',
      'http://dbsuarez.github.io/remote-tunes/#/pair?v=1&r=ABCDEFGH&t=ABCDEFGH23',
      'https://dbsuarez.github.io/other/#/pair?v=1&r=ABCDEFGH&t=ABCDEFGH23',
      'https://dbsuarez.github.io/remote-tunes/',
    ]) {
      expect(PairingQr.parse(bad), isNull, reason: bad);
    }
  });

  test('rejects foreign or damaged codes', () {
    for (final bad in [
      'https://example.com',
      'hello',
      'remotetunes://pair?v=2&h=1.2.3.4&p=1&t=ABCDEFGH23',
      'remotetunes://pair?v=1&h=1.2.3.4&p=1',
      'remotetunes://pair?v=1&t=ABCDEFGH23',
      'remotetunes://pair?v=1&h=1.2.3.4&p=99999&t=ABCDEFGH23',
      'remotetunes://pair?v=1&h=a%20b&p=80&t=ABCDEFGH23',
      'remotetunes://pair?v=1&r=BAD&t=ABCDEFGH23',
    ]) {
      expect(PairingQr.parse(bad), isNull, reason: bad);
    }
  });
}
