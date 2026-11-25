/// A short memory of what the player did at song changes (a fade starting, the
/// next song taking over, a song ending...), shown in Settings > Diagnostics so a
/// problem at the end of a song can be understood. Song titles are not kept, only
/// positions in the queue; nothing leaves the phone unless it is copied by hand.
class PlaybackLog {
  PlaybackLog._();

  static const _keep = 60;
  static final List<String> _lines = [];
  static final Stopwatch _clock = Stopwatch()..start();

  /// Where "now" is taken from (tests replace it).
  static int Function() millis = () => _clock.elapsedMilliseconds;

  static List<String> get lines => List.unmodifiable(_lines);

  static void add(String what) {
    final t = millis();
    final s = (t ~/ 1000).toString().padLeft(5);
    final ms = (t % 1000).toString().padLeft(3, '0');
    _lines.add('$s.$ms  $what');
    if (_lines.length > _keep) _lines.removeAt(0);
  }

  static void clear() => _lines.clear();
}
