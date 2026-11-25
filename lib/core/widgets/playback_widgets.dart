import 'default_art.dart';
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../haptics.dart';
import '../protocol/protocol.dart';
import 'haptic_button.dart';

/// 2043 -> "2,043".
String formatCount(int n) {
  final s = n.abs().toString();
  final out = StringBuffer(n < 0 ? '-' : '');
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

String formatDuration(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final m = s ~/ 60;
  final r = s % 60;
  return '$m:${r.toString().padLeft(2, '0')}';
}

/// A long time as h:mm:ss (m:ss under an hour), for the total of a list.
String formatTotalTime(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final h = s ~/ 3600;
  final m = (s % 3600) ~/ 60;
  final r = s % 60;
  final rr = r.toString().padLeft(2, '0');
  return h > 0 ? '$h:${m.toString().padLeft(2, '0')}:$rr' : '$m:$rr';
}

/// Title, artist and a seek bar. Seek is sent on release, not while dragging
/// (docs/05_UI_UX_SPEC.md).
class NowPlayingCard extends StatefulWidget {
  const NowPlayingCard({
    super.key,
    required this.state,
    this.onSeek,
    this.enabled = true,
    this.art,
    this.trailing,
    this.hero = false,
    this.actions,
  });

  final PlaybackState state;

  /// The big layout: a large cover, centered title in the accent color, then
  /// [actions] and the seek bar. Without it: the compact card.
  final bool hero;

  /// A row of quick actions shown under the title in the [hero] layout.
  final Widget? actions;

  /// Replaces the album-art picture (the Controller passes the thumbnail it
  /// fetched from the Player).
  final Widget? art;

  /// Shown at the end of the title row (e.g. a favorite heart).
  final Widget? trailing;

  /// Called with the new position (seconds) when the user releases the slider.
  final ValueChanged<int>? onSeek;
  final bool enabled;

  @override
  State<NowPlayingCard> createState() => _NowPlayingCardState();
}

class _NowPlayingCardState extends State<NowPlayingCard> {
  double? _dragging;

  /// Where the user just released the slider. Shown until the Player reports a
  /// position near it, so the bar does not jump back to the old position while
  /// the seek is on its way.
  double? _pendingSeek;
  Timer? _pendingTimer;

  @override
  void dispose() {
    _pendingTimer?.cancel();
    super.dispose();
  }

  void _clearPending() {
    _pendingTimer?.cancel();
    _pendingSeek = null;
  }

  @override
  void didUpdateWidget(NowPlayingCard old) {
    super.didUpdateWidget(old);
    final pending = _pendingSeek;
    if (pending == null) return;
    final s = widget.state;
    // The Player caught up, or moved to another track.
    if ((s.positionSeconds - pending).abs() <= 2 ||
        s.title != old.state.title ||
        s.songId != old.state.songId) {
      _clearPending();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.state;
    final duration = s.durationSeconds <= 0 ? 1 : s.durationSeconds;
    final position = (_dragging ?? _pendingSeek ?? s.positionSeconds.toDouble())
        .clamp(0.0, duration.toDouble());
    // Live streams have no known length, so there is nothing to seek in.
    final canSeek = widget.enabled &&
        widget.onSeek != null &&
        s.hasTrack &&
        s.durationSeconds > 0 &&
        s.canSeek; // another app may not allow seeking

    if (widget.hero) {
      return _hero(theme, s, position, duration, canSeek);
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Now playing',
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                widget.art ?? _ArtTile(path: s.localArtPath),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.hasTrack ? s.title : 'Nothing playing',
                        style: theme.textTheme.titleMedium,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (s.artist.isNotEmpty)
                        Text(
                          s.artist,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      if (s.isExternal)
                        Row(
                          children: [
                            Icon(Icons.open_in_new_rounded,
                                size: 14, color: theme.colorScheme.secondary),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                s.externalApp.isEmpty
                                    ? 'Waiting for a music app'
                                    : 'Playing in ${s.externalApp}',
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall
                                    ?.copyWith(color: theme.colorScheme.secondary),
                              ),
                            ),
                          ],
                        )
                      else if (s.isInternetStream)
                        Row(
                          children: [
                            Icon(Icons.public_rounded,
                                size: 14, color: theme.colorScheme.secondary),
                            const SizedBox(width: 4),
                            Text(
                              'Internet audio',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.secondary),
                            ),
                          ],
                        )
                      else if (s.queueLength > 0)
                        Text(
                          'Track ${s.queueIndex + 1} of ${s.queueLength}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
                if (widget.trailing != null) widget.trailing!,
              ],
            ),
            if (s.isLoading) ...[
              const SizedBox(height: 12),
              const LinearProgressIndicator(),
              const SizedBox(height: 4),
              Text('Opening the stream…', style: theme.textTheme.bodySmall),
            ],
            if (s.error.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline_rounded,
                      size: 18, color: theme.colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.error,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.error),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Slider(
              value: position,
              max: duration.toDouble(),
              onChanged: canSeek ? (v) => setState(() => _dragging = v) : null,
              onChangeEnd: canSeek
                  ? (v) {
                      Haptics.selection();
                      widget.onSeek!(v.round());
                      setState(() {
                        _dragging = null;
                        _pendingSeek = v.roundToDouble();
                      });
                      // Give up waiting if the Player never confirms.
                      _pendingTimer?.cancel();
                      _pendingTimer = Timer(const Duration(seconds: 4), () {
                        if (mounted) setState(() => _pendingSeek = null);
                      });
                    }
                  : null,
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(formatDuration(position.round()),
                      style: theme.textTheme.bodySmall),
                  Text(formatDuration(s.durationSeconds),
                      style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _seekBar(ThemeData theme, PlaybackState s, double position, int duration, bool canSeek,
      {bool showFormat = false}) {
    return Column(
      children: [
        Slider(
          value: position,
          max: duration.toDouble(),
          onChanged: canSeek ? (v) => setState(() => _dragging = v) : null,
          onChangeEnd: canSeek
              ? (v) {
                  Haptics.selection();
                  widget.onSeek!(v.round());
                  setState(() {
                    _dragging = null;
                    _pendingSeek = v.roundToDouble();
                  });
                  // Give up waiting if the Player never confirms.
                  _pendingTimer?.cancel();
                  _pendingTimer = Timer(const Duration(seconds: 4), () {
                    if (mounted) setState(() => _pendingSeek = null);
                  });
                }
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(formatDuration(position.round()), style: theme.textTheme.bodySmall),
              if (showFormat && s.format.isNotEmpty)
                Expanded(
                  child: Text(
                    s.format,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
              Text(formatDuration(s.durationSeconds), style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ],
    );
  }

  /// The big layout: cover, title in the accent color, quick actions, seek bar.
  Widget _hero(ThemeData theme, PlaybackState s, double position, int duration, bool canSeek) {
    final subtitle = [
      if (s.artist.isNotEmpty) s.artist,
      if (s.album.isNotEmpty) s.album,
    ].join(' · ');
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    return Column(
      children: [
        if (widget.art != null) Center(child: widget.art!),
        const SizedBox(height: 16),
        Text(
          s.hasTrack ? s.title : 'Nothing playing',
          textAlign: TextAlign.center,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.titleLarge?.copyWith(
            color: theme.colorScheme.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (subtitle.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(subtitle,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: s.isExternal
              ? Text(
                  s.externalApp.isEmpty
                      ? 'Waiting for a music app'
                      : 'Playing in ${s.externalApp}',
                  style: muted)
              : s.isInternetStream
                  ? Text('Internet audio', style: muted)
                  : s.queueLength > 0
                      ? Text('Track ${s.queueIndex + 1} of ${s.queueLength}', style: muted)
                      : const SizedBox.shrink(),
        ),
        if (s.isLoading) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
          const SizedBox(height: 4),
          Text('Opening the stream…', style: theme.textTheme.bodySmall),
        ],
        if (s.error.isNotEmpty) ...[
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.error_outline_rounded, size: 18, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text(s.error,
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
              ),
            ],
          ),
        ],
        if (widget.actions != null) ...[
          const SizedBox(height: 8),
          widget.actions!,
        ],
        const SizedBox(height: 4),
        _seekBar(theme, s, position, duration, canSeek, showFormat: true),
      ],
    );
  }
}

/// Album art on the Player; a music-note placeholder when there is none (and
/// always on the Controller, which never receives art paths).
class _ArtTile extends StatelessWidget {
  const _ArtTile({this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final placeholder = DefaultArt.album(size: 64, radius: 12);
    final p = path;
    if (p == null) return placeholder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: Image.file(
        File(p),
        width: 64,
        height: 64,
        fit: BoxFit.cover,
        cacheWidth: 192,
        errorBuilder: (_, __, ___) => placeholder,
      ),
    );
  }
}

/// Previous / play-pause / next. Disabled as a group when [enabled] is false.
class TransportControls extends StatelessWidget {
  const TransportControls({
    super.key,
    required this.isPlaying,
    required this.enabled,
    required this.onPrevious,
    required this.onToggle,
    required this.onNext,
    this.canSkip = true,
    this.onSeekBack,
    this.onSeekForward,
  });

  /// Optional 10-second jump buttons next to previous / next.
  final VoidCallback? onSeekBack;
  final VoidCallback? onSeekForward;

  final bool isPlaying;
  final bool enabled;

  /// False when another app does not allow skipping tracks.
  final bool canSkip;
  final VoidCallback onPrevious;
  final VoidCallback onToggle;
  final VoidCallback onNext;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        HapticButton(
          kind: HapticKind.light,
          tooltip: 'Previous',
          iconSize: 36,
          constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
          onPressed: (enabled && canSkip) ? onPrevious : null,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        if (onSeekBack != null)
          HapticButton(
            kind: HapticKind.light,
            tooltip: 'Back 10 seconds',
            iconSize: 30,
            onPressed: enabled ? onSeekBack : null,
            icon: const Icon(Icons.replay_10_rounded),
          ),
        const SizedBox(width: 8),
        HapticButton(
          kind: HapticKind.medium,
          filled: true,
          tooltip: isPlaying ? 'Pause' : 'Play',
          iconSize: 40,
          constraints: const BoxConstraints(minWidth: 72, minHeight: 72),
          onPressed: enabled ? onToggle : null,
          icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
        ),
        const SizedBox(width: 8),
        if (onSeekForward != null)
          HapticButton(
            kind: HapticKind.light,
            tooltip: 'Forward 10 seconds',
            iconSize: 30,
            onPressed: enabled ? onSeekForward : null,
            icon: const Icon(Icons.forward_10_rounded),
          ),
        HapticButton(
          kind: HapticKind.light,
          tooltip: 'Next',
          iconSize: 36,
          constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
          onPressed: (enabled && canSkip) ? onNext : null,
          icon: const Icon(Icons.skip_next_rounded),
        ),
      ],
    );
  }
}

/// Volume slider (0.0–1.0, shown as 0–100%). Changes are debounced to 250 ms
/// (docs/05_UI_UX_SPEC.md) and flushed immediately on release.
class VolumeSlider extends StatefulWidget {
  const VolumeSlider({
    super.key,
    required this.volume,
    required this.enabled,
    required this.onChanged,
  });

  final double volume;
  final bool enabled;
  final ValueChanged<double> onChanged;

  @override
  State<VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends State<VolumeSlider> {
  double? _dragging;
  Timer? _debounce;

  /// Where the user just let go. Shown until the Player reports a volume near
  /// it, so the slider does not jump back to the old value on its way.
  double? _pending;
  Timer? _pendingTimer;

  @override
  void dispose() {
    _debounce?.cancel();
    _pendingTimer?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(VolumeSlider old) {
    super.didUpdateWidget(old);
    final pending = _pending;
    if (pending != null && (widget.volume - pending).abs() <= 0.02) {
      _pendingTimer?.cancel();
      _pending = null;
    }
  }

  void _onChanged(double v) {
    setState(() {
      _dragging = v;
      _pending = null;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => widget.onChanged(v));
  }

  void _onEnd(double v) {
    _debounce?.cancel();
    Haptics.selection();
    widget.onChanged(v);
    setState(() {
      _dragging = null;
      _pending = v;
    });
    // Give up waiting if the Player never confirms.
    _pendingTimer?.cancel();
    _pendingTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _pending = null);
    });
  }

  @override
  Widget build(BuildContext context) {
    final v = (_dragging ?? _pending ?? widget.volume).clamp(0.0, 1.0);
    return Row(
      children: [
        const Icon(Icons.volume_down_rounded),
        Expanded(
          child: Slider(
            value: v,
            onChanged: widget.enabled ? _onChanged : null,
            onChangeEnd: widget.enabled ? _onEnd : null,
          ),
        ),
        SizedBox(
          width: 44,
          child: Text('${(v * 100).round()}%', textAlign: TextAlign.end),
        ),
      ],
    );
  }
}
