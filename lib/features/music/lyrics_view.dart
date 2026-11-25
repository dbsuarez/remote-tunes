import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../core/lyrics/lrc.dart';
import '../../core/protocol/library_models.dart';

/// The cover of the song playing, with a button in its top right corner that
/// shows the lyrics in the same place. Lyrics with times follow the song line
/// by line; plain lyrics just scroll. [fetch] asks the Player.
class CoverWithLyrics extends StatefulWidget {
  const CoverWithLyrics({
    super.key,
    required this.cover,
    required this.size,
    required this.radius,
    required this.songId,
    required this.positionSeconds,
    required this.isPlaying,
    required this.fetch,
    this.onSeek,
    this.enabled = true,
  });

  /// The picture itself (already [size] pixels square).
  final Widget cover;
  final double size;
  final double radius;

  /// The library song playing (null or 0 or less: no lyrics to look up, so no
  /// button).
  final int? songId;
  final int positionSeconds;
  final bool isPlaying;
  final Future<RemoteLyrics> Function(int songId) fetch;

  /// Called with a position in seconds when a line is tapped.
  final ValueChanged<int>? onSeek;
  final bool enabled;

  @override
  State<CoverWithLyrics> createState() => _CoverWithLyricsState();
}

class _CoverWithLyricsState extends State<CoverWithLyrics> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final id = widget.songId;
    final hasLyrics = id != null && id > 0;
    final theme = Theme.of(context);
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        children: [
          widget.cover,
          if (_open && hasLyrics)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withValues(alpha: 0.93),
                  borderRadius: BorderRadius.circular(widget.radius),
                ),
                padding: const EdgeInsets.fromLTRB(14, 52, 14, 10),
                child: LyricsPanel(
                  key: ValueKey(id),
                  songId: id,
                  positionSeconds: widget.positionSeconds,
                  isPlaying: widget.isPlaying,
                  fetch: widget.fetch,
                  onSeek: widget.onSeek,
                  style: theme.textTheme,
                ),
              ),
            ),
          if (hasLyrics)
            Positioned(
              top: 6,
              right: 6,
              child: IconButton.filledTonal(
                tooltip: _open ? 'Show cover' : 'Show lyrics',
                visualDensity: VisualDensity.compact,
                onPressed: widget.enabled
                    ? () {
                        Haptics.selection();
                        setState(() => _open = !_open);
                      }
                    : null,
                icon: Icon(_open ? Icons.image_outlined : Icons.lyrics_outlined),
              ),
            ),
        ],
      ),
    );
  }
}

/// The lyrics themselves (loading, not found, plain or following the song).
class LyricsPanel extends StatefulWidget {
  const LyricsPanel({
    super.key,
    required this.songId,
    required this.positionSeconds,
    required this.isPlaying,
    required this.fetch,
    this.onSeek,
    this.style,
  });

  final int songId;
  final int positionSeconds;
  final bool isPlaying;
  final Future<RemoteLyrics> Function(int songId) fetch;
  final ValueChanged<int>? onSeek;
  final TextTheme? style;

  @override
  State<LyricsPanel> createState() => _LyricsPanelState();
}

class _LyricsPanelState extends State<LyricsPanel> {
  static const _lineHeight = 44.0;

  RemoteLyrics? _lyrics;
  bool _loading = true;
  Object? _error;
  List<LyricLine> _lines = const [];
  int _request = 0;

  final ScrollController _scroll = ScrollController();
  Timer? _tick;

  // The position is reported once a second; between reports it is worked out
  // from the clock so a line changes when it should.
  int _baseSeconds = 0;
  DateTime _baseAt = DateTime.now();
  int _shownLine = -2;

  @override
  void initState() {
    super.initState();
    _baseSeconds = widget.positionSeconds;
    _load();
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _onTick());
  }

  @override
  void didUpdateWidget(LyricsPanel old) {
    super.didUpdateWidget(old);
    if (old.songId != widget.songId) {
      _load();
    }
    if (old.positionSeconds != widget.positionSeconds || old.isPlaying != widget.isPlaying) {
      _baseSeconds = widget.positionSeconds;
      _baseAt = DateTime.now();
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final req = ++_request;
    setState(() {
      _loading = true;
      _error = null;
      _lyrics = null;
      _lines = const [];
      _shownLine = -2;
    });
    try {
      final l = await widget.fetch(widget.songId);
      if (!mounted || req != _request) return;
      setState(() {
        _lyrics = l;
        _lines = l.synced.isNotEmpty ? parseLrc(l.synced) : const [];
        _loading = false;
      });
    } catch (e) {
      if (!mounted || req != _request) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  int get _positionMs {
    final extra = widget.isPlaying ? DateTime.now().difference(_baseAt).inMilliseconds : 0;
    return _baseSeconds * 1000 + extra.clamp(0, 1500);
  }

  void _onTick() {
    if (!mounted || _lines.isEmpty) return;
    final line = currentLyricLine(_lines, _positionMs);
    if (line != _shownLine) {
      setState(() => _shownLine = line);
      _centerOn(line);
    }
  }

  void _centerOn(int line) {
    if (line < 0 || !_scroll.hasClients) return;
    final view = _scroll.position.viewportDimension;
    final target = (line * _lineHeight - view / 2 + _lineHeight / 2)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    _scroll.animateTo(target,
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (_loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (_error != null) {
      return _message(context, "Couldn't get the lyrics from the Player.", retry: true);
    }
    final l = _lyrics!;
    if (l.disabled) {
      return _message(context,
          'Lyrics are switched off. Turn them on in Settings on the Player (Look and feel).');
    }
    if (l.failed) {
      return _message(context, "Couldn't reach the lyrics service. Check the Player's internet.",
          retry: true);
    }
    if (l.instrumental && !l.hasText) {
      return _message(context, 'Instrumental. No lyrics.');
    }
    if (!l.hasText) return _message(context, 'No lyrics found for this song.');

    final body = _lines.isNotEmpty ? _synced(theme) : _plain(theme, l.plain);
    return Column(
      children: [
        Expanded(child: body),
        if (l.source.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text('Lyrics: ${l.source}',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
      ],
    );
  }

  Widget _message(BuildContext context, String text, {bool retry = false}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(text, textAlign: TextAlign.center),
          if (retry)
            TextButton(onPressed: _load, child: const Text('Try again')),
        ],
      ),
    );
  }

  Widget _plain(ThemeData theme, String text) => SingleChildScrollView(
        controller: _scroll,
        child: SelectableText(text, style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
      );

  Widget _synced(ThemeData theme) {
    final primary = theme.colorScheme.primary;
    return ListView.builder(
      controller: _scroll,
      itemExtent: _lineHeight,
      itemCount: _lines.length,
      itemBuilder: (context, i) {
        final line = _lines[i];
        final now = i == _shownLine;
        return InkWell(
          onTap: widget.onSeek == null ? null : () => widget.onSeek!(line.ms ~/ 1000),
          child: Align(
            alignment: Alignment.centerLeft,
            child: AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: (theme.textTheme.titleMedium ?? const TextStyle()).copyWith(
                color: now ? primary : theme.colorScheme.onSurfaceVariant,
                fontWeight: now ? FontWeight.w700 : FontWeight.w400,
              ),
              child: Text(
                line.text.isEmpty ? '♪' : line.text,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        );
      },
    );
  }
}
