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
