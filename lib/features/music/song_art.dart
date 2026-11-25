import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../core/widgets/default_art.dart';
import 'music_source.dart';

/// The round picture at the start of a song row: the album art if the song has
/// any, otherwise a music note. Art is fetched when the row first shows (and
/// remembered by the source), so long lists stay light.
///
/// [overlayIcon] marks a state (selected, playing now, file missing): it
/// replaces the note, or sits on a dimmed picture.
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

  @override
  State<SongArt> createState() => _SongArtState();
}

class _SongArtState extends State<SongArt> {
  Future<Uint8List?>? _art;

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
    _art = widget.songId > 0
        ? widget.source.artFor(widget.songId, size: 96).catchError((Object _) => null)
        : null;
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

    // No cover: the default picture (a state like "playing" or "selected" keeps its icon).
    Widget none() => widget.overlayIcon == null
        ? DefaultArt.albumAvatar(radius: r)
        : note(widget.overlayIcon!);
    final art = _art;
    if (art == null) return none();
    return FutureBuilder<Uint8List?>(
      future: art,
      builder: (context, snap) {
        final bytes = snap.data;
        // While it loads, a plain circle (not the default picture, which would flash).
        if (snap.connectionState != ConnectionState.done && bytes == null) {
          return widget.overlayIcon != null
              ? note(widget.overlayIcon!)
              : CircleAvatar(
                  radius: r, backgroundColor: theme.colorScheme.surfaceContainerHighest);
        }
        if (bytes == null) return none();
        return CircleAvatar(
          radius: r,
          backgroundColor: theme.colorScheme.surfaceContainerHighest,
          backgroundImage: MemoryImage(bytes),
          onBackgroundImageError: (_, __) {},
          child: widget.overlayIcon == null
              ? null
              : DecoratedBox(
                  decoration: const BoxDecoration(
                      shape: BoxShape.circle, color: Color(0x99000000)),
                  child: Center(
                    child: Icon(widget.overlayIcon, size: r * 1.2, color: iconColor),
                  ),
                ),
        );
      },
    );
  }
}
