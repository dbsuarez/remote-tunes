import 'package:flutter/widgets.dart';

import '../../core/haptics.dart';

/// Tells when two fingers move apart or together over [child], without taking touches away from
/// it (the list under it still scrolls and taps as usual). Each time the fingers have grown or
/// shrunk by about a third since the last step, [onStep] is called with true (apart: bigger) or
/// false (together: smaller).
class PinchZoom extends StatefulWidget {
  const PinchZoom({super.key, required this.child, required this.onStep});

  final Widget child;
  final void Function(bool bigger) onStep;

  @override
  State<PinchZoom> createState() => _PinchZoomState();
}

class _PinchZoomState extends State<PinchZoom> {
  final Map<int, Offset> _fingers = {};
  double _base = 0;

  double? get _distance {
    if (_fingers.length != 2) return null;
    final p = _fingers.values.toList();
    return (p[0] - p[1]).distance;
  }

  void _down(PointerDownEvent e) {
    _fingers[e.pointer] = e.position;
    _base = _distance ?? 0;
  }

  void _move(PointerMoveEvent e) {
    if (!_fingers.containsKey(e.pointer)) return;
    _fingers[e.pointer] = e.position;
    final d = _distance;
    if (d == null || _base < 20) return;
    final ratio = d / _base;
    if (ratio > 1.35 || ratio < 0.74) {
      Haptics.selection();
      widget.onStep(ratio > 1);
      _base = d;
    }
  }

  void _up(PointerEvent e) {
    _fingers.remove(e.pointer);
    _base = _distance ?? 0;
  }

  @override
  Widget build(BuildContext context) => Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _up,
        child: widget.child,
      );
}
