import 'package:flutter/material.dart';

import 'ambience_models.dart';

/// The name the "what is on" page has for its color.
const ambienceSelectedPage = 'Selected';

/// Each page has its own color (all dark enough for white words).
const _colors = <String, Color>{
  'Selected': Color(0xFF37474F),
  'Rain': Color(0xFF1F6F94),
  'Ocean': Color(0xFF3F6C7D),
  'Water': Color(0xFF52688C),
  'Wind and Fire': Color(0xFF7D6248),
  'Night': Color(0xFF16294A),
  'Countryside': Color(0xFF1F6B2A),
  'City': Color(0xFF0B4A82),
  'Home': Color(0xFF6E6352),
  'Zen Garden': Color(0xFF0F766B),
  'Noise': Color(0xFF52666F),
  'Relaxing Music': Color(0xFF9C5A5A),
  'Traditional': Color(0xFF545C94),
  'ASMR': Color(0xFF0C7A62),
  'Binaural Beats': Color(0xFF2A5F58),
  ambienceEnvironmentCategory: Color(0xFF2E5E3E),
  ambienceOwnCategory: Color(0xFF2561A8),
};

/// The color of a page; null is the page of the sounds ready to play.
Color ambienceColor(String? page) {
  if (page == null) return const Color(0xFF34407A);
  final known = _colors[page];
  if (known != null) return known;
  // The owner's categories get one of a few, always the same for one category.
  if (!page.startsWith('cat-')) return const Color(0xFF34407A);
  final pick = page.codeUnits.fold(0, (h, u) => (h * 31 + u) & 0x7fffffff);
  return _customColors[pick % _customColors.length];
}

const _customColors = [
  Color(0xFF7A3E6B),
  Color(0xFF2F6B6B),
  Color(0xFF8A4B32),
  Color(0xFF4A5A2A),
  Color(0xFF5B4B8A),
  Color(0xFF1F5F7A),
];

/// White words and controls over a page of [color].
ThemeData ambienceTheme(ThemeData base, Color color) {
  final scheme = ColorScheme.fromSeed(seedColor: color, brightness: Brightness.dark).copyWith(
    primary: Colors.white,
    onPrimary: color,
    onSurface: Colors.white,
    onSurfaceVariant: Colors.white70,
  );
  return base.copyWith(
    colorScheme: scheme,
    textTheme: base.textTheme.apply(bodyColor: Colors.white, displayColor: Colors.white),
    iconTheme: const IconThemeData(color: Colors.white),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: Colors.white, disabledForegroundColor: Colors.white38),
    ),
    sliderTheme: base.sliderTheme.copyWith(activeTrackColor: Colors.white, inactiveTrackColor: Colors.white30, thumbColor: Colors.white),
  );
}
