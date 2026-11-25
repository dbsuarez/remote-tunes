import 'package:flutter/painting.dart';

/// Where the visualizer sits on the (dimmed) cover.
enum VisualizerCoverPosition {
  top('Top', Alignment.topCenter),
  middle('Middle', Alignment.center),
  bottom('Bottom', Alignment.bottomCenter);

  const VisualizerCoverPosition(this.label, this.alignment);
  final String label;
  final Alignment alignment;

  static VisualizerCoverPosition parse(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => VisualizerCoverPosition.bottom);
}
