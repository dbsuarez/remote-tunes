import 'dart:math';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Three parts stacked in at least [height]: the top and bottom take what they need, and the middle
/// gets all that is left (never less than [least]; then the whole is taller than [height], for a
/// scrolling page). Every part is as wide as the page.
class FillMiddle extends MultiChildRenderObjectWidget {
  FillMiddle({
    super.key,
    required this.height,
    required Widget top,
    required Widget middle,
    required Widget bottom,
    this.least = 96,
  }) : super(children: [top, middle, bottom]);

  final double height;
  final double least;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderFillMiddle(height, least);

  @override
  void updateRenderObject(BuildContext context, covariant RenderObject renderObject) {
    (renderObject as _RenderFillMiddle)
      ..wanted = height
      ..least = least;
  }
}

class _Part extends ContainerBoxParentData<RenderBox> {}

class _RenderFillMiddle extends RenderBox
    with ContainerRenderObjectMixin<RenderBox, _Part>, RenderBoxContainerDefaultsMixin<RenderBox, _Part> {
  _RenderFillMiddle(this._wanted, this._least);

  double _wanted;
  set wanted(double v) {
    if (v == _wanted) return;
    _wanted = v;
    markNeedsLayout();
  }

  double _least;
  set least(double v) {
    if (v == _least) return;
    _least = v;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _Part) child.parentData = _Part();
  }

  @override
  void performLayout() {
    final width = constraints.maxWidth;
    final top = firstChild!;
    final middle = childAfter(top)!;
    final bottom = childAfter(middle)!;
    final wide = BoxConstraints.tightFor(width: width);
    top.layout(wide, parentUsesSize: true);
    bottom.layout(wide, parentUsesSize: true);
    final room = max(_least, _wanted - top.size.height - bottom.size.height);
    middle.layout(BoxConstraints.tightFor(width: width, height: room), parentUsesSize: true);
    (top.parentData! as _Part).offset = Offset.zero;
    (middle.parentData! as _Part).offset = Offset(0, top.size.height);
    (bottom.parentData! as _Part).offset = Offset(0, top.size.height + room);
    size = constraints.constrain(Size(width, top.size.height + room + bottom.size.height));
  }

  @override
  void paint(PaintingContext context, Offset offset) => defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}
