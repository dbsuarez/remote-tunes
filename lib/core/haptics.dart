import 'package:flutter/services.dart';

/// The kinds of tap feedback RemoteTunes uses.
enum HapticKind {
  /// Play / pause: a firm tap.
  medium,

  /// Skip, previous: a light tap.
  light,

  /// Picking something: a small click.
  selection,
}

/// Tap feedback (a short vibration) for buttons and choices. One switch turns
/// it all off (Settings > Haptic feedback). Safe everywhere: where a device
/// cannot vibrate (the web page, most desktops) it simply does nothing.
class Haptics {
  Haptics._();

  /// Kept in step with the saved setting by the phone app.
  static bool enabled = true;

  static void fire(HapticKind kind) {
    if (!enabled) return;
    // Feedback must never get in the way of the tap itself.
    try {
      switch (kind) {
        case HapticKind.medium:
          HapticFeedback.mediumImpact();
        case HapticKind.light:
          HapticFeedback.lightImpact();
        case HapticKind.selection:
          HapticFeedback.selectionClick();
      }
    } catch (_) {}
  }

  static void medium() => fire(HapticKind.medium);
  static void light() => fire(HapticKind.light);
  static void selection() => fire(HapticKind.selection);
}
