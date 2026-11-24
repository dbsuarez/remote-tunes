import 'package:flutter/material.dart';

import '../haptics.dart';

/// An icon button that gives a small tap of feedback when pressed. A button
/// that is disabled (no [onPressed]) does neither.
///
/// Standard patterns: [HapticKind.medium] for play/pause, [HapticKind.light]
/// for skip and previous, [HapticKind.selection] for picking something.
class HapticButton extends StatelessWidget {
  const HapticButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.kind = HapticKind.light,
    this.tooltip,
    this.filled = false,
    this.iconSize,
    this.constraints,
    this.isSelected,
    this.selectedIcon,
  });

  final Widget icon;
  final VoidCallback? onPressed;
  final HapticKind kind;
  final String? tooltip;

  /// A filled (prominent) button, like the play button.
  final bool filled;
  final double? iconSize;
  final BoxConstraints? constraints;
  final bool? isSelected;
  final Widget? selectedIcon;

  @override
  Widget build(BuildContext context) {
    final press = onPressed;
    final VoidCallback? handler = press == null
        ? null
        : () {
            Haptics.fire(kind);
            press();
          };
    return filled
        ? IconButton.filled(
            tooltip: tooltip,
            iconSize: iconSize,
            constraints: constraints,
            isSelected: isSelected,
            selectedIcon: selectedIcon,
            onPressed: handler,
            icon: icon,
          )
        : IconButton(
            tooltip: tooltip,
            iconSize: iconSize,
            constraints: constraints,
            isSelected: isSelected,
            selectedIcon: selectedIcon,
            onPressed: handler,
            icon: icon,
          );
  }
}
