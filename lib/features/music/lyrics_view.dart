import 'dart:async';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../core/lyrics/lrc.dart';
import '../../core/protocol/library_models.dart';

/// Loads the lyrics of one song at a time and keeps them, so the card and the
/// full-screen view show the same thing without asking twice.
class LyricsController extends ChangeNotifier {
  LyricsController(this.fetch);

  /// Asks the Player for a song's lyrics (replaced when the screen is rebuilt
  /// with another connection).
  Future<RemoteLyrics> Function(int songId) fetch;

  int? _songId;
  int _request = 0;
  bool loading = false;
  Object? error;
  RemoteLyrics? lyrics;
  List<LyricLine> lines = const [];
  bool _disposed = false;

  /// Reads the lyrics of [songId] (nothing happens if they are already there).
  void load(int songId) {
    if (songId == _songId && error == null && (loading || lyrics != null)) return;
    _start(songId);
  }

  void retry() {
    final id = _songId;
    if (id != null) _start(id);
  }

  Future<void> _start(int songId) async {
    final req = ++_request;
    _songId = songId;
    loading = true;
    error = null;
    lyrics = null;
    lines = const [];
    notifyListeners();
    try {
      final l = await fetch(songId);
      if (_disposed || req != _request) return;
      lyrics = l;
      lines = l.synced.isNotEmpty ? parseLrc(l.synced) : const [];
    } catch (e) {
      if (_disposed || req != _request) return;
      error = e;
    }
    loading = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

/// Where the song is, shared with the full-screen view (which is a separate
/// page and so is not rebuilt by the screen behind it).
class LyricsTick {
  const LyricsTick({
    required this.songId,
    required this.title,
    required this.artist,
    required this.positionSeconds,
    required this.isPlaying,
  });

  final int? songId;
  final String title;
  final String artist;
  final int positionSeconds;
  final bool isPlaying;
}

/// The cover of the song playing, with a button in its top right corner. Press
/// it and the cover fades away completely and the lyrics take its place, in a
/// card the size of the cover. From there they can be opened full screen.
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
    this.title = '',
    this.artist = '',
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
  final String title;
  final String artist;
  final int positionSeconds;
  final bool isPlaying;
  final Future<RemoteLyrics> Function(int songId) fetch;

  /// Called with a position in seconds when a line is tapped.
  final ValueChanged<int>? onSeek;
  final bool enabled;

  @override
  State<CoverWithLyrics> createState() => _CoverWithLyricsState();
}

class _CoverWithLyricsState extends State<CoverWithLyrics> with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 460),
  );
  late final LyricsController _lyrics = LyricsController(widget.fetch);
  late final ValueNotifier<LyricsTick> _tick = ValueNotifier(_currentTick());
  bool _open = false;
  bool _tickQueued = false;

  LyricsTick _currentTick() => LyricsTick(
        songId: widget.songId,
        title: widget.title,
        artist: widget.artist,
        positionSeconds: widget.positionSeconds,
        isPlaying: widget.isPlaying,
      );

  @override
  void didUpdateWidget(CoverWithLyrics old) {
    super.didUpdateWidget(old);
    _lyrics.fetch = widget.fetch;
    final id = widget.songId;
    if (_open && id != null && id > 0 && id != old.songId) _lyrics.load(id);
    // The full-screen view follows along (after this frame, not during it).
    if (!_tickQueued) {
      _tickQueued = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _tickQueued = false;
        if (mounted) _tick.value = _currentTick();
      });
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    _lyrics.dispose();
    _tick.dispose();
    super.dispose();
  }

  void _toggle() {
    Haptics.selection();
    final id = widget.songId;
    setState(() => _open = !_open);
    if (_open) {
      if (id != null && id > 0) _lyrics.load(id);
      _fade.forward();
    } else {
      _fade.reverse();
    }
  }

  void _fullscreen() {
    Haptics.selection();
    Navigator.of(context).push(PageRouteBuilder<void>(
      opaque: false,
      barrierColor: Colors.black87,
      transitionDuration: const Duration(milliseconds: 260),
      reverseTransitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (_, __, ___) => LyricsLightbox(
        controller: _lyrics,
        tick: _tick,
        onSeek: widget.onSeek,
      ),
      transitionsBuilder: (_, anim, __, child) => FadeTransition(
        opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut),
        child: ScaleTransition(
          scale: Tween(begin: 0.96, end: 1.0)
              .animate(CurvedAnimation(parent: anim, curve: Curves.easeOut)),
          child: child,
        ),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final id = widget.songId;
    final hasLyrics = id != null && id > 0;
    final theme = Theme.of(context);
    // The cover goes first (the first half of the time), then the lyrics come
    // in (the second half), so the two are never on top of each other.
    final coverOpacity = Tween(begin: 1.0, end: 0.0)
        .animate(CurvedAnimation(parent: _fade, curve: const Interval(0, 0.5, curve: Curves.easeIn)));
    final lyricsOpacity = CurvedAnimation(
        parent: _fade, curve: const Interval(0.5, 1, curve: Curves.easeOut));
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        children: [
          FadeTransition(opacity: coverOpacity, child: widget.cover),
          if (hasLyrics)
            Positioned.fill(
              child: AnimatedBuilder(
                animation: _fade,
                builder: (context, child) => IgnorePointer(
                  ignoring: _fade.value < 0.5,
                  child: Visibility(
                    visible: _fade.value > 0,
                    maintainState: true,
                    child: child!,
                  ),
                ),
                child: FadeTransition(
                  opacity: lyricsOpacity,
                  child: LyricsCard(
                    controller: _lyrics,
                    positionSeconds: widget.positionSeconds,
                    isPlaying: widget.isPlaying,
                    radius: widget.radius,
                    margin: const EdgeInsets.all(6),
                    onSeek: widget.onSeek,
                    onFullscreen: _fullscreen,
                  ),
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
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.surface.withValues(alpha: 0.55),
                ),
                onPressed: widget.enabled ? _toggle : null,
                icon: Icon(_open ? Icons.image_outlined : Icons.lyrics_outlined),
              ),
            ),
        ],
      ),
    );
  }
}

/// The lyrics in a card with a soft background taken from the accent color.
class LyricsCard extends StatelessWidget {
  const LyricsCard({
    super.key,
    required this.controller,
    required this.positionSeconds,
    required this.isPlaying,
    required this.radius,
    this.margin = EdgeInsets.zero,
    this.onSeek,
    this.onFullscreen,
  });

  final LyricsController controller;
  final int positionSeconds;
  final bool isPlaying;
  final double radius;
  final EdgeInsets margin;
  final ValueChanged<int>? onSeek;

  /// Shows the "Show fullscreen" button when given.
  final VoidCallback? onFullscreen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: margin,
      child: DecoratedBox(
        decoration: lyricsBackground(theme, radius),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            children: [
              Positioned.fill(
                child: LyricsBody(
                  controller: controller,
                  positionSeconds: positionSeconds,
                  isPlaying: isPlaying,
                  onSeek: onSeek,
                  topInset: 44,
                  bottomInset: 26,
                ),
              ),
              if (onFullscreen != null)
                Positioned(
                  top: 4,
                  left: 4,
                  child: IconButton(
                    tooltip: 'Show fullscreen',
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.fullscreen_rounded),
                    onPressed: onFullscreen,
                  ),
                ),
              Positioned(left: 0, right: 0, bottom: 4, child: LyricsCredit(controller: controller)),
            ],
          ),
        ),
      ),
    );
  }
}

/// A background that is not just black: the accent color melting into the
/// surface, with a thin light edge.
BoxDecoration lyricsBackground(ThemeData theme, double radius) {
  final accent = theme.colorScheme.primary;
  final surface = theme.colorScheme.surface;
  return BoxDecoration(
    borderRadius: BorderRadius.circular(radius),
    gradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [
        Color.lerp(surface, accent, 0.34)!,
        Color.lerp(surface, accent, 0.14)!,
        Color.lerp(surface, Colors.black, 0.35)!,
      ],
      stops: const [0, 0.55, 1],
    ),
    border: Border.all(color: accent.withValues(alpha: 0.35)),
    boxShadow: [BoxShadow(color: accent.withValues(alpha: 0.18), blurRadius: 22)],
  );
}

/// "Lyrics: LRCLIB", small and quiet, once they are there.
class LyricsCredit extends StatelessWidget {
  const LyricsCredit({super.key, required this.controller, this.large = false});

  final LyricsController controller;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final l = controller.lyrics;
        if (l == null || !l.hasText || l.source.isEmpty) return const SizedBox.shrink();
        return Text(
          'Lyrics: ${l.source}',
          textAlign: TextAlign.center,
          style: (large ? theme.textTheme.labelMedium : theme.textTheme.labelSmall)
              ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
        );
      },
    );
  }
}

/// The lyrics themselves: the line being sung large and bright, the ones around
/// it smaller and dimmer, fading out at the top and bottom. Lyrics with times
/// follow the song; plain lyrics scroll.
class LyricsBody extends StatefulWidget {
  const LyricsBody({
    super.key,
    required this.controller,
    required this.positionSeconds,
    required this.isPlaying,
    this.onSeek,
    this.large = false,
    this.topInset = 0,
    this.bottomInset = 0,
  });

  final LyricsController controller;
  final int positionSeconds;
  final bool isPlaying;
  final ValueChanged<int>? onSeek;

  /// Bigger type (the full-screen view).
  final bool large;
  final double topInset;
  final double bottomInset;

  @override
  State<LyricsBody> createState() => _LyricsBodyState();
}

class _LyricsBodyState extends State<LyricsBody> {
  final ScrollController _scroll = ScrollController();
  Timer? _tick;
  List<GlobalKey> _keys = const [];
  int _keysFor = -1;

  // The position is reported once a second; between reports it is worked out
  // from the clock so a line changes when it should.
  int _baseSeconds = 0;
  DateTime _baseAt = DateTime.now();
  int _shownLine = -2;

  @override
  void initState() {
    super.initState();
    _baseSeconds = widget.positionSeconds;
    widget.controller.addListener(_onController);
    _tick = Timer.periodic(const Duration(milliseconds: 250), (_) => _onTick());
  }

  @override
  void didUpdateWidget(LyricsBody old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller.removeListener(_onController);
      widget.controller.addListener(_onController);
    }
    if (old.positionSeconds != widget.positionSeconds || old.isPlaying != widget.isPlaying) {
      _baseSeconds = widget.positionSeconds;
      _baseAt = DateTime.now();
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onController);
    _tick?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  void _onController() {
    if (!mounted) return;
    _shownLine = -2;
    setState(() {});
  }

  int get _positionMs {
    final extra = widget.isPlaying ? DateTime.now().difference(_baseAt).inMilliseconds : 0;
    return _baseSeconds * 1000 + extra.clamp(0, 1500);
  }

  void _onTick() {
    final lines = widget.controller.lines;
    if (!mounted || lines.isEmpty) return;
    final line = currentLyricLine(lines, _positionMs);
    if (line != _shownLine) {
      setState(() => _shownLine = line);
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerOn(line));
    }
  }

  /// Eases the line being sung to the middle.
  void _centerOn(int line) {
    if (!mounted || line < 0 || line >= _keys.length) return;
    final ctx = _keys[line].currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      alignment: 0.5,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeInOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final theme = Theme.of(context);
    if (c.loading) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (c.error != null) {
      return _message(context, "Couldn't get the lyrics from the Player.", retry: true);
    }
    final l = c.lyrics;
    if (l == null) return const SizedBox.shrink();
    if (l.disabled) {
      return _message(context,
          'Lyrics are switched off. Turn them on in Settings on the Player (Look and feel).');
    }
    if (l.failed) {
      return _message(context, "Couldn't reach the lyrics service. Check the Player's internet.",
          retry: true);
    }
    if (l.instrumental && !l.hasText) return _message(context, 'Instrumental. No lyrics.');
    if (!l.hasText) return _message(context, 'No lyrics found for this song.');

    final body = c.lines.isNotEmpty ? _synced(theme, c.lines) : _plain(theme, l.plain);
    // Fade the text out at the top and bottom edges.
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) => const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
        stops: [0, 0.16, 0.84, 1],
      ).createShader(rect),
      child: body,
    );
  }

  Widget _message(BuildContext context, String text, {bool retry = false}) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lyrics_outlined,
                size: widget.large ? 40 : 28,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.5)),
            const SizedBox(height: 10),
            Text(
              text,
              textAlign: TextAlign.center,
              style: (widget.large ? theme.textTheme.titleMedium : theme.textTheme.bodyMedium)
                  ?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.8)),
            ),
            if (retry) TextButton(onPressed: widget.controller.retry, child: const Text('Try again')),
          ],
        ),
      ),
    );
  }

  /// How a line looks by how far it is from the one being sung.
  TextStyle _styleFor(ThemeData theme, int distance) {
    final base = widget.large ? theme.textTheme.headlineSmall : theme.textTheme.titleMedium;
    final scale = switch (distance) {
      0 => 1.0,
      1 => 0.84,
      2 => 0.76,
      _ => 0.7,
    };
    final alpha = switch (distance) {
      0 => 1.0,
      1 => 0.62,
      2 => 0.42,
      _ => 0.3,
    };
    return (base ?? const TextStyle()).copyWith(
      fontSize: (base?.fontSize ?? 16) * scale,
      fontWeight: distance == 0 ? FontWeight.w800 : FontWeight.w500,
      height: 1.25,
      color: distance == 0
          ? Colors.white
          : theme.colorScheme.onSurface.withValues(alpha: alpha),
    );
  }

  Widget _synced(ThemeData theme, List<LyricLine> lines) {
    if (_keysFor != lines.length || _keys.length != lines.length) {
      _keys = List.generate(lines.length, (_) => GlobalKey());
      _keysFor = lines.length;
    }
    // Right away (not only at the next tick), so the line being sung is already
    // big when the lyrics appear or the full-screen view opens.
    if (_shownLine == -2) {
      _shownLine = currentLyricLine(lines, _positionMs);
      final line = _shownLine;
      WidgetsBinding.instance.addPostFrameCallback((_) => _centerOn(line));
    }
    final inset = widget.large ? 40.0 : 22.0;
    return LayoutBuilder(
      builder: (context, box) => SingleChildScrollView(
        controller: _scroll,
        padding: EdgeInsets.fromLTRB(
          inset,
          widget.topInset + box.maxHeight * 0.35,
          inset,
          widget.bottomInset + box.maxHeight * 0.35,
        ),
        child: Column(
          children: [
            for (var i = 0; i < lines.length; i++)
              InkWell(
                key: _keys[i],
                borderRadius: BorderRadius.circular(10),
                onTap: widget.onSeek == null ? null : () => widget.onSeek!(lines[i].ms ~/ 1000),
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: widget.large ? 9 : 6),
                  child: Center(
                    child: AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOut,
                      textAlign: TextAlign.center,
                      style: _styleFor(theme, _shownLine < 0 ? 3 : (i - _shownLine).abs()),
                      child: Text(
                        lines[i].text.isEmpty ? '♪' : lines[i].text,
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _plain(ThemeData theme, String text) {
    final inset = widget.large ? 40.0 : 22.0;
    return SingleChildScrollView(
      controller: _scroll,
      padding: EdgeInsets.fromLTRB(inset, widget.topInset + 20, inset, widget.bottomInset + 40),
      child: SelectableText(
        text,
        textAlign: TextAlign.center,
        style: (widget.large ? theme.textTheme.titleLarge : theme.textTheme.bodyLarge)?.copyWith(
          height: 1.6,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.9),
        ),
      ),
    );
  }
}

/// The lyrics full screen, like an image lightbox but with the lyrics: a soft
/// colored backdrop, the song's name, big type that follows the music, and a
/// button to close.
class LyricsLightbox extends StatelessWidget {
  const LyricsLightbox({
    super.key,
    required this.controller,
    required this.tick,
    this.onSeek,
  });

  final LyricsController controller;
  final ValueListenable<LyricsTick> tick;
  final ValueChanged<int>? onSeek;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.5, -0.8),
            radius: 1.4,
            colors: [
              Color.lerp(Colors.black, accent, 0.45)!,
              Color.lerp(Colors.black, accent, 0.16)!,
              Colors.black,
            ],
            stops: const [0, 0.55, 1],
          ),
        ),
        child: SafeArea(
          child: ValueListenableBuilder<LyricsTick>(
            valueListenable: tick,
            builder: (context, t, _) => Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              t.title.isEmpty ? 'Lyrics' : t.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            if (t.artist.isNotEmpty)
                              Text(
                                t.artist,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium
                                    ?.copyWith(color: Colors.white70),
                              ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close lyrics',
                        icon: const Icon(Icons.close_rounded, color: Colors.white),
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LyricsBody(
                    controller: controller,
                    positionSeconds: t.positionSeconds,
                    isPlaying: t.isPlaying,
                    onSeek: onSeek,
                    large: true,
                    topInset: 8,
                    bottomInset: 8,
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: LyricsCredit(controller: controller, large: true),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
