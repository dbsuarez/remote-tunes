import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../protocol/protocol.dart';

String formatDuration(int seconds) {
  final s = seconds < 0 ? 0 : seconds;
  final m = s ~/ 60;
  final r = s % 60;
  return '$m:${r.toString().padLeft(2, '0')}';
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
  });

  final PlaybackState state;

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
}

/// Album art on the Player; a music-note placeholder when there is none (and
/// always on the Controller, which never receives art paths).
class _ArtTile extends StatelessWidget {
  const _ArtTile({this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final placeholder = Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(Icons.music_note_rounded,
          color: theme.colorScheme.primary, size: 32),
    );
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
  });

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
        IconButton(
          tooltip: 'Previous',
          iconSize: 36,
          constraints: const BoxConstraints(minWidth: 56, minHeight: 56),
          onPressed: (enabled && canSkip) ? onPrevious : null,
          icon: const Icon(Icons.skip_previous_rounded),
        ),
        const SizedBox(width: 12),
        IconButton.filled(
          tooltip: isPlaying ? 'Pause' : 'Play',
          iconSize: 40,
          constraints: const BoxConstraints(minWidth: 72, minHeight: 72),
          onPressed: enabled ? onToggle : null,
          icon: Icon(isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
        ),
        const SizedBox(width: 12),
        IconButton(
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

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  void _onChanged(double v) {
    setState(() => _dragging = v);
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 250), () => widget.onChanged(v));
  }

  void _onEnd(double v) {
    _debounce?.cancel();
    widget.onChanged(v);
    setState(() => _dragging = null);
  }

  @override
  Widget build(BuildContext context) {
    final v = (_dragging ?? widget.volume).clamp(0.0, 1.0);
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
