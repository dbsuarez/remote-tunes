import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'controller_client.dart';

/// Album art for a library song, fetched from the Player as a small picture.
/// Shows a music note while loading, or if the song has no art.
class RemoteArt extends StatefulWidget {
  const RemoteArt(
      {super.key,
      required this.client,
      required this.songId,
      this.size = 64,
      this.radius});

  final ControllerClient client;
  final int? songId;
  final double size;

  /// Corner radius (default: a fifth of the size).
  final double? radius;

  @override
  State<RemoteArt> createState() => _RemoteArtState();
}

class _RemoteArtState extends State<RemoteArt> {
  Future<Uint8List?>? _art;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(RemoteArt old) {
    super.didUpdateWidget(old);
    if (old.songId != widget.songId) _load();
  }

  void _load() {
    final id = widget.songId;
    _art = id == null ? null : widget.client.artFor(id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = widget.size;
    final radius = widget.radius ?? size / 5;
    final placeholder = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(Icons.music_note_rounded,
          color: theme.colorScheme.primary, size: size / 2),
    );
    final art = _art;
    if (art == null) return placeholder;
    return FutureBuilder<Uint8List?>(
      future: art,
      builder: (context, snap) {
        final bytes = snap.data;
        if (bytes == null) return placeholder;
        return ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Image.memory(
            bytes,
            width: size,
            height: size,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => placeholder,
          ),
        );
      },
    );
  }
}

