import 'package:flutter/material.dart';

/// RemoteTunes visual identity: dark charcoal + electric teal, with violet
/// reserved for Online mode. Deliberately NOT Spotify green (#1DB954).
/// See docs/15_UX_DESIGN_GUARDRAILS.md.
class RtColors {
  RtColors._();

  static const Color background = Color(0xFF111317);
  static const Color surface = Color(0xFF1A1D23);
  static const Color surfaceHigh = Color(0xFF242830);
  static const Color outline = Color(0xFF3A3F4A);

  /// Primary accent (electric teal).
  static const Color teal = Color(0xFF22E5D0);

  /// Online-mode accent (violet), distinct from the local teal.
  static const Color violet = Color(0xFF9B8CFF);

  static const Color warning = Color(0xFFFFB454);
}

class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: RtColors.teal,
      brightness: Brightness.dark,
    ).copyWith(
      primary: RtColors.teal,
      onPrimary: const Color(0xFF00201C),
      secondary: RtColors.violet,
      onSecondary: const Color(0xFF1B1240),
      surface: RtColors.surface,
      surfaceContainerHighest: RtColors.surfaceHigh,
      outline: RtColors.outline,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: RtColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: RtColors.background,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: RtColors.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: RtColors.outline, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: RtColors.surfaceHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 48)),
          visualDensity: VisualDensity.standard,
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
    );
  }
}
