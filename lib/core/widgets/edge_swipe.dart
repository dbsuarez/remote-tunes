import 'package:flutter/material.dart';

import '../haptics.dart';

/// Lets a swipe that starts at the left or right edge of [child] do something,
/// without getting in the way of the rest of the screen.
///
/// The strips are thin (24 px) and sit on top of [child]. A drag that starts in
/// one wins over a sideways swipe on the page below (such as switching tabs),
/// and taps pass through to what is underneath.
///
/// Note: with Android's gesture navigation the very edge is also "back". A
/// swipe that starts a little in from the edge reaches these strips.
class EdgeSwipe extends StatelessWidget {
  const EdgeSwipe({
    super.key,
    required this.child,
    this.onFromLeft,
    this.onFromRight,
    this.enabled = true,
    this.stripWidth = 24,
    this.distance = 40,
    this.bottomInset = 0,
  });

  final Widget child;

  /// Called when a swipe that began at the left edge moves right.
  final VoidCallback? onFromLeft;

  /// Called when a swipe that began at the right edge moves left.
  final VoidCallback? onFromRight;
  final bool enabled;
  final double stripWidth;

  /// How far (px) or fast the swipe must go to count.
  final double distance;

  /// Space at the bottom the strips leave free (e.g. for a sheet's drag handle).
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    return Stack(
      children: [
        Positioned.fill(child: child),
        if (onFromLeft != null)
          Positioned(
            left: 0,
            top: 0,
            bottom: bottomInset,
            width: stripWidth,
            child: _Strip(
              direction: 1,
              distance: distance,
              onSwipe: onFromLeft!,
            ),
          ),
        if (onFromRight != null)
          Positioned(
            right: 0,
            top: 0,
            bottom: bottomInset,
            width: stripWidth,
            child: _Strip(
              direction: -1,
              distance: distance,
              onSwipe: onFromRight!,
            ),
          ),
      ],
    );
  }
}

class _Strip extends StatefulWidget {
  const _Strip({required this.direction, required this.distance, required this.onSwipe});

  /// 1: a swipe to the right counts; -1: a swipe to the left counts.
  final int direction;
  final double distance;
  final VoidCallback onSwipe;

  @override
  State<_Strip> createState() => _StripState();
}

class _StripState extends State<_Strip> {
  double _travelled = 0;
  bool _fired = false;

  void _fire() {
    if (_fired) return;
    _fired = true;
    Haptics.selection();
    widget.onSwipe();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) {
        _travelled = 0;
        _fired = false;
      },
      onHorizontalDragUpdate: (d) {
        _travelled += d.delta.dx * widget.direction;
        if (_travelled >= widget.distance) _fire();
      },
      onHorizontalDragEnd: (d) {
        // A quick flick counts even if it was short.
        if ((d.primaryVelocity ?? 0) * widget.direction > 700 && _travelled > 8) _fire();
      },
      child: const SizedBox.expand(),
    );
  }
}
