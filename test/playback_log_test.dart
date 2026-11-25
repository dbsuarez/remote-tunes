import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/features/player/playback_log.dart';

void main() {
  setUp(PlaybackLog.clear);

  test('keeps the lines in order, with a time on each', () {
    var t = 0;
    PlaybackLog.millis = () => t;
    t = 1234;
    PlaybackLog.add('first');
    t = 5000;
    PlaybackLog.add('second');
    expect(PlaybackLog.lines.length, 2);
    expect(PlaybackLog.lines[0], endsWith('first'));
    expect(PlaybackLog.lines[0], contains('1.234'));
    expect(PlaybackLog.lines[1], contains('5.000'));
  });

  test('only the newest sixty are kept', () {
    for (var i = 0; i < 100; i++) {
      PlaybackLog.add('line $i');
    }
    expect(PlaybackLog.lines.length, 60);
    expect(PlaybackLog.lines.first, endsWith('line 40'));
    expect(PlaybackLog.lines.last, endsWith('line 99'));
  });
}
