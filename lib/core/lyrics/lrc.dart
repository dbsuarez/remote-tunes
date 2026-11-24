/// One line of time-synced lyrics.
class LyricLine {
  const LyricLine(this.ms, this.text);

  /// When the line starts, in milliseconds from the start of the song.
  final int ms;
  final String text;

  @override
  String toString() => '[$ms] $text';
}

final _timeTag = RegExp(r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]');
final _offsetTag = RegExp(r'^\s*\[offset:\s*([+-]?\d+)\s*\]', caseSensitive: false);

/// Reads an LRC file: lines like `[01:23.45] words` (several time tags on one
/// line repeat the words). Other tags (`[ar:..]`, `[ti:..]`) are ignored, and
/// `[offset:+/-ms]` shifts every time. Lines come back sorted by time.
List<LyricLine> parseLrc(String lrc) {
  final lines = <LyricLine>[];
  var offset = 0;
  for (final raw in lrc.split(RegExp(r'\r?\n'))) {
    final o = _offsetTag.firstMatch(raw);
    if (o != null) {
      offset = int.tryParse(o.group(1)!) ?? 0;
      continue;
    }
    final tags = _timeTag.allMatches(raw).toList();
    if (tags.isEmpty) continue;
    // Words are what follows the last leading tag.
    final text = raw.substring(tags.last.end).trim();
    for (final t in tags) {
      final m = int.parse(t.group(1)!);
      final s = int.parse(t.group(2)!);
      var frac = t.group(3) ?? '0';
      // ".5" is half a second, ".05" a twentieth: scale to milliseconds.
      frac = frac.padRight(3, '0').substring(0, 3);
      final ms = (m * 60 + s) * 1000 + int.parse(frac);
      lines.add(LyricLine(ms, text));
    }
  }
  final shifted = [
    for (final l in lines) LyricLine((l.ms + offset).clamp(0, 1 << 31), l.text),
  ];
  shifted.sort((a, b) => a.ms.compareTo(b.ms));
  return shifted;
}

/// Index of the line being sung at [positionMs], or -1 before the first line.
int currentLyricLine(List<LyricLine> lines, int positionMs) {
  var lo = 0;
  var hi = lines.length - 1;
  var found = -1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (lines[mid].ms <= positionMs) {
      found = mid;
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return found;
}
