import 'playlist_picker.dart';
import 'package:flutter/material.dart';

import '../../core/haptics.dart';
import '../../core/models/enums.dart';
import '../../core/protocol/protocol.dart';
import '../../core/session/playback_session.dart';
import '../../core/widgets/edge_swipe.dart';
import '../../core/widgets/haptic_button.dart';
import '../../core/widgets/playback_widgets.dart';
import 'lyrics_view.dart';
import 'music_source.dart';
import 'now_playing_controls.dart';
import 'queue_peek.dart';

/// The Now Playing screen, the same on both phones: a big cover, the title in
/// the accent color, favorite / shuffle / repeat / speed / sleep timer, the
/// transport controls, volume, lyrics and the queue peek sheet.
///
/// It works on a [PlaybackSession], so it does not matter whether the music is
/// on this phone or on another one.
class NowPlayingView extends StatefulWidget {
  const NowPlayingView({
    super.key,
    required this.session,
    this.header,
    this.extras,
    this.onOpenLibrary,
    this.lyricsRequests,
    this.visualizer,
    this.visualizerButton,
    this.visualizerOnCover = false,
    this.visualizerPosition = Alignment.bottomCenter,
  });

  /// Where on the cover the visualizer sits (when it is on the cover).
  final Alignment visualizerPosition;

  /// The visualizer goes over the dimmed cover, and gives way to the lyrics.
  final bool visualizerOnCover;

  /// A button in the row of quick actions, to the left of the volume button, that shows or
  /// hides the visualizer (null: none, e.g. when controlling another phone).
  final Widget? visualizerButton;

  /// Moving bars under the cover (built with whether music is playing).
  final Widget Function(bool isPlaying)? visualizer;

  final PlaybackSession session;

  /// Notifies to show the lyrics (from the menu).
  final Listenable? lyricsRequests;

  /// Shown above the cover (for example the switch to another music app).
  final Widget? header;

  /// Shown at the bottom of the page (for example "Play on this phone too").
  final Widget? extras;

  /// A swipe in from the left edge calls this (null: no left-edge swipe).
  final VoidCallback? onOpenLibrary;

  @override
  State<NowPlayingView> createState() => NowPlayingViewState();
}

class NowPlayingViewState extends State<NowPlayingView> {
  final DraggableScrollableController _sheet = DraggableScrollableController();

  PlaybackSession get session => widget.session;

  @override
  void dispose() {
    _sheet.dispose();
    super.dispose();
  }

  /// A swipe in from the right edge raises the queue: first to the middle, then
  /// all the way up.
  void _raiseQueue() {
    if (!_sheet.isAttached) return;
    final mid = QueuePeekSheet.midSize;
    final target = _sheet.size < mid - 0.03 ? mid : QueuePeekSheet.fullSize;
    _sheet.animateTo(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// A tap or click outside the queue sheet (on the player behind it) slides it
  /// back down.
  void _lowerQueue(Offset local, double height) {
    if (!_sheet.isAttached) return;
    // Only a tap above the sheet counts, not one on the sheet itself.
    if (local.dy >= height * (1 - _sheet.size)) return;
    final rest = _sheet.pixelsToSize(QueuePeekSheet.handleHeight);
    if (_sheet.size <= rest + 0.02) return;
    _sheet.animateTo(
      rest,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  /// Runs a command; a refusal is shown as a plain message.
  Future<void> _run(Future<void> Function() command) async {
    try {
      await command();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  /// Jumps [seconds] back or forward in the song.
  void _jump(PlaybackState p, int seconds) {
    final to = (p.positionSeconds + seconds).clamp(0, p.durationSeconds);
    _run(() => session.seek(to));
  }

  /// The small "add to a playlist" button on the cover's top-left corner (it gives that corner
  /// to *Show fullscreen* while the lyrics show).
  Widget? _playlistButton(BuildContext context, PlaybackState p) {
    final id = p.songId ?? 0;
    if (id <= 0 || p.isExternal) return null;
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: IconButton(
        tooltip: 'Add to a playlist',
        iconSize: 22,
        visualDensity: VisualDensity.compact,
        color: Colors.white,
        icon: const Icon(Icons.playlist_add_rounded),
        onPressed: () => addSongsToPlaylistFlow(context, session.source, [id]),
      ),
    );
  }

  /// Favorite, shuffle, repeat, speed and the sleep timer, right under the title.
  Widget _quickActions(PlaybackState p, bool enabled) {
    final primary = Theme.of(context).colorScheme.primary;
    final hasSong = p.songId != null && p.songId! > 0;
    final repeatIcon = switch (p.repeatMode) {
      RepeatMode.one => Icons.repeat_one_rounded,
      _ => Icons.repeat_rounded,
    };
    final count = widget.visualizerButton == null ? 6 : 7;
    return LayoutBuilder(
      builder: (context, box) {
        // Seven buttons need a little less room each on a narrow phone.
        final tight = box.maxWidth < count * 48;
        final row = Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            HapticButton(
              kind: HapticKind.selection,
              tooltip: p.favorite
                  ? 'Remove from favorites'
                  : 'Add to favorites',
              onPressed: enabled && hasSong
                  ? () =>
                        _run(() => session.setFavorite(p.songId!, !p.favorite))
                  : null,
              icon: Icon(
                p.favorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
                color: p.favorite ? primary : null,
              ),
            ),
            HapticButton(
              kind: HapticKind.selection,
              tooltip: p.shuffleEnabled ? 'Shuffle is on' : 'Shuffle is off',
              onPressed: enabled
                  ? () => _run(() => session.setShuffle(!p.shuffleEnabled))
                  : null,
              icon: Icon(
                Icons.shuffle_rounded,
                color: p.shuffleEnabled ? primary : null,
              ),
            ),
            HapticButton(
              kind: HapticKind.selection,
              tooltip: 'Repeat: ${p.repeatMode.label}',
              onPressed: enabled
                  ? () => _run(
                      () => session.setRepeat(switch (p.repeatMode) {
                        RepeatMode.off => RepeatMode.queue,
                        RepeatMode.queue => RepeatMode.one,
                        RepeatMode.one => RepeatMode.off,
                      }),
                    )
                  : null,
              icon: Icon(
                repeatIcon,
                color: p.repeatMode == RepeatMode.off ? null : primary,
              ),
            ),
            SpeedButton(
              speed: p.speed,
              enabled: enabled,
              onSet: (v) => _run(() => session.setSpeed(v)),
            ),
            SleepTimerControl(
              compact: true,
              secondsLeft: p.sleepTimerSeconds,
              enabled: enabled,
              onSet: (m) => _run(() => session.setSleepTimer(m)),
            ),
            if (widget.visualizerButton != null) widget.visualizerButton!,
            VolumeButton(
              volume: p.volume,
              enabled: enabled,
              onChanged: (v) => _run(() => session.setVolume(v)),
            ),
          ],
        );
        if (!tight) return row;
        return Theme(
          data: Theme.of(context).copyWith(
            iconButtonTheme: IconButtonThemeData(
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ),
          child: row,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final enabled = session.enabled;
    final p = session.state;

    // The queue peek rests along the bottom; the page scrolls clear of it.
    return LayoutBuilder(
      builder: (context, box) {
        final peekSpace = p.isExternal ? 0.0 : QueuePeekSheet.handleHeight + 12;
        // The cover is as wide as the page allows, but not taller than about half
        // the screen so the controls stay in reach on a small phone.
        final heroSize = [
          box.maxWidth - 64,
          box.maxHeight * 0.42,
          340.0,
        ].reduce((a, b) => a < b ? a : b).clamp(120.0, 340.0);
        return EdgeSwipe(
          enabled: enabled,
          onFromLeft: widget.onOpenLibrary,
          onFromRight: p.isExternal ? null : _raiseQueue,
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: (e) => _lowerQueue(e.localPosition, box.maxHeight),
            child: Stack(
              children: [
                ListView(
                  padding: EdgeInsets.fromLTRB(16, 16, 16, 24 + peekSpace),
                  children: [
                    if (widget.header != null) ...[
                      widget.header!,
                      const SizedBox(height: 12),
                    ],
                    if (p.isExternal)
                      NowPlayingCard(
                        state: p,
                        enabled: enabled,
                        onSeek: (s) => _run(() => session.seek(s)),
                        art: session.art(null, size: 64),
                      )
                    else
                      NowPlayingCard(
                        hero: true,
                        state: p,
                        enabled: enabled,
                        onSeek: (s) => _run(() => session.seek(s)),
                        // The cover, with the lyrics button in its corner.
                        art: CoverWithLyrics(
                          cover: session.art(
                            (p.songId ?? 0) <= 0 ? null : p.songId,
                            size: heroSize,
                            radius: 20,
                          ),
                          size: heroSize,
                          radius: 20,
                          openRequests: widget.lyricsRequests,
                          songId: p.songId,
                          title: p.title,
                          artist: p.artist,
                          positionSeconds: p.positionSeconds,
                          isPlaying: p.isPlaying,
                          enabled: enabled,
                          fetch: session.lyrics,
                          onSeek: (s) => _run(() => session.seek(s)),
                          // Top-left while the cover shows; the lyrics' fullscreen button
                          // has that corner when they show.
                          coverAction: _playlistButton(context, p),
                          overlayAlignment: widget.visualizerPosition,
                          overlay: widget.visualizerOnCover && widget.visualizer != null
                              ? widget.visualizer!(p.isPlaying)
                              : null,
                        ),
                        actions: _quickActions(p, enabled),
                      ),
                    if (widget.visualizer != null && !widget.visualizerOnCover && !p.isExternal)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: widget.visualizer!(p.isPlaying),
                      ),
                    const SizedBox(height: 8),
                    TransportControls(
                      canSkip: p.canSkip,
                      isPlaying: p.isPlaying,
                      enabled: enabled,
                      onPrevious: () => _run(session.previous),
                      onToggle: () => _run(session.toggle),
                      onNext: () => _run(session.next),
                      onSeekBack: p.isExternal || p.durationSeconds <= 0
                          ? null
                          : () => _jump(p, -10),
                      onSeekForward: p.isExternal || p.durationSeconds <= 0
                          ? null
                          : () => _jump(p, 10),
                    ),
                    const SizedBox(height: 8),
                    // The volume is a button in the row of quick actions (with a small
                    // vertical slider); when another music app is controlled there is
                    // no such row, so it keeps the slider.
                    if (p.isExternal)
                      VolumeSlider(
                        volume: p.volume,
                        enabled: enabled,
                        onChanged: (v) => _run(() => session.setVolume(v)),
                      ),
                    // Speed and the sleep timer are in the row of quick actions under
                    // the title; when another music app is controlled they keep their
                    // card.
                    if (p.isExternal) ...[
                      const SizedBox(height: 8),
                      SleepTimerControl(
                        secondsLeft: p.sleepTimerSeconds,
                        enabled: enabled,
                        onSet: (m) => _run(() => session.setSleepTimer(m)),
                      ),
                    ],
                    if (widget.extras != null && !p.isExternal) widget.extras!,
                  ],
                ),
                if (!p.isExternal)
                  Positioned.fill(
                    child: QueuePeekSheet(
                      controller: _sheet,
                      source: session.source,
                      revision: p.queueRevision,
                      currentIndex: p.queueIndex,
                      enabled: enabled,
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
