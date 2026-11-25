import 'dart:collection';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/widgets/default_art.dart';
import 'music_source.dart';

/// The round picture at the start of a song row: the album art if the song has any, otherwise the
/// default picture. Art is fetched when the row first shows and remembered, so scrolling back to a row
/// shows its picture at once instead of loading it (and flashing) again.
///
/// While the picture is being fetched the row shows the default picture (not a grey circle), so songs
/// that have no cover never flash at all and the others change once, with a short fade.
///
/// [overlayIcon] marks a state (selected, playing now, file missing): it
/// replaces the picture, or sits on a dimmed one.
class SongArt extends StatefulWidget {
  const SongArt({
    super.key,
    required this.source,
    required this.songId,
    this.radius = 20,
    this.overlayIcon,
    this.overlayColor,
  });

  final MusicSource source;

  /// Library id; 0 or less (internet links) never has art.
  final int songId;
  final double radius;
  final IconData? overlayIcon;
  final Color? overlayColor;

  /// What was found per source and song, for a little while (a cover can change when the art finder or
  /// Look up runs). Bytes are shared between the songs of one album, so this stays small.
  static final _known = Expando<_Known>('SongArt');
  static const _keepFor = Duration(minutes: 2);
  static const _maxEntries = 400;

  /// Forgets what is remembered (after covers changed).
  static void forgetAll() {
    // An Expando cannot be emptied; a new generation makes every entry stale.
    _generation++;
  }

  static int _generation = 0;

  @override
  State<SongArt> createState() => _SongArtState();
}

class _Known {
  final LinkedHashMap<int, ({Uint8List? bytes, DateTime at, int generation})> byId = LinkedHashMap();
}

class _SongArtState extends State<SongArt> {
  /// True once it is known whether the song has a picture.
  bool _resolved = false;
  Uint8List? _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SongArt old) {
    super.didUpdateWidget(old);
    if (old.songId != widget.songId || old.source != widget.source) _load();
  }

  void _load() {
    final id = widget.songId;
    if (id <= 0) {
      _resolved = true;
      _bytes = null;
      return;
    }
    final known = SongArt._known[widget.source];
    final hit = known?.byId[id];
    if (hit != null &&
        hit.generation == SongArt._generation &&
        DateTime.now().difference(hit.at) < SongArt._keepFor) {
      _resolved = true;
      _bytes = hit.bytes;
      return;
    }
    _resolved = false;
    _bytes = null;
    final source = widget.source;
    source.artFor(id, size: 96).catchError((Object _) => null).then((bytes) {
      final k = SongArt._known[source] ?? (SongArt._known[source] = _Known());
      k.byId.remove(id);
      k.byId[id] = (bytes: bytes, at: DateTime.now(), generation: SongArt._generation);
      while (k.byId.length > SongArt._maxEntries) {
        k.byId.remove(k.byId.keys.first);
      }
      // Only if this row still shows this song.
      if (mounted && widget.songId == id && identical(widget.source, source)) {
        setState(() {
          _resolved = true;
          _bytes = bytes;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.radius;
    final iconColor = widget.overlayColor ?? theme.colorScheme.primary;
    Widget note(IconData icon) => CircleAvatar(
          radius: r,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          child: Icon(icon, size: r * 1.2, color: iconColor),
        );

    // No cover (or not known yet): the default picture. A state like "playing" or "selected" keeps its icon.
    final plain = widget.overlayIcon == null ? DefaultArt.albumAvatar(radius: r) : note(widget.overlayIcon!);
    final bytes = _bytes;
    final Widget shown;
    if (!_resolved || bytes == null) {
      shown = KeyedSubtree(key: const ValueKey('no-art'), child: plain);
    } else {
      shown = CircleAvatar(
        key: const ValueKey('art'),
        radius: r,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        backgroundImage: MemoryImage(bytes),
        onBackgroundImageError: (_, __) {},
        child: widget.overlayIcon == null
            ? null
            : DecoratedBox(
                decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x99000000)),
                child: Center(child: Icon(widget.overlayIcon, size: r * 1.2, color: iconColor)),
              ),
      );
    }
    // A picture that arrives after the row showed is faded in; one that is known at once just shows.
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 160),
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.center,
        children: [...previous, if (current != null) current],
      ),
      child: shown,
    );
  }
}
