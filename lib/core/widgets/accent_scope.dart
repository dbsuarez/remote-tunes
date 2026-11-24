import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../accent.dart';

/// Tints everything below it (progress bars, switches, the play button, tabs)
/// with a color taken from the current song's album art, fading from one song's
/// color to the next. Without art, or with "Colors from album art" off, the
/// normal RemoteTunes colors stay.
///
/// [loadArt] returns the small album-art picture of a library song (the
/// Controller already fetches these); [songId] is the current song, or null.
class AccentScope extends ConsumerStatefulWidget {
  const AccentScope({
    super.key,
    required this.songId,
    required this.loadArt,
    required this.child,
    this.cache,
  });

  final int? songId;
  final Future<Uint8List?> Function(int songId) loadArt;
  final Widget child;

  /// For tests; normally one shared cache is used.
  final AccentCache? cache;

  static final AccentCache _shared = AccentCache();

  @override
  ConsumerState<AccentScope> createState() => _AccentScopeState();
}

class _AccentScopeState extends ConsumerState<AccentScope> {
  Color? _accent;
  int? _asked;

  AccentCache get _cache => widget.cache ?? AccentScope._shared;

  @override
  void initState() {
    super.initState();
    _update();
  }

  @override
  void didUpdateWidget(AccentScope old) {
    super.didUpdateWidget(old);
    if (old.songId != widget.songId) _update();
  }

  Future<void> _update() async {
    final id = widget.songId;
    _asked = id;
    if (id == null || id <= 0) {
      if (_accent != null) setState(() => _accent = null);
      return;
    }
    Color? c;
    try {
      c = await _cache.forSong(id, widget.loadArt);
    } catch (_) {
      c = null;
    }
    // A newer song may have been asked for meanwhile.
    if (!mounted || _asked != id) return;
    setState(() => _accent = c);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final on = ref.watch(accentFromArtProvider);
    final target = on ? (_accent ?? theme.colorScheme.primary) : theme.colorScheme.primary;
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: target),
      duration: const Duration(milliseconds: 500),
      builder: (context, color, child) {
        final accent = color ?? target;
        final dark = ThemeData.estimateBrightnessForColor(accent) == Brightness.dark;
        return Theme(
          data: theme.copyWith(
            colorScheme: theme.colorScheme.copyWith(
              primary: accent,
              onPrimary: dark ? Colors.white : const Color(0xFF101418),
            ),
          ),
          child: child!,
        );
      },
      child: widget.child,
    );
  }
}
