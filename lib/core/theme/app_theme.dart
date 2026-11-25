import 'package:flutter/material.dart';

import 'skin.dart';

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

  /// The dark theme in the colors of [skin] (the RemoteTunes look by default).
  static ThemeData dark({Skin skin = Skin.remoteTunes}) {
    final onPrimary = skin.primary.computeLuminance() > 0.4 ? const Color(0xFF101010) : Colors.white;
    final scheme = ColorScheme.fromSeed(
      seedColor: skin.primary,
      brightness: Brightness.dark,
    ).copyWith(
      primary: skin.primary,
      onPrimary: onPrimary,
      secondary: skin.secondary,
      onSecondary: skin.secondary.computeLuminance() > 0.4 ? const Color(0xFF101010) : Colors.white,
      surface: skin.surface,
      surfaceContainerHighest: skin.surfaceHigh,
      surfaceContainerHigh: skin.surfaceHigh,
      outline: skin.outline,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      scaffoldBackgroundColor: skin.background,
      appBarTheme: AppBarTheme(
        backgroundColor: skin.background,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: skin.surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: skin.primary.withValues(alpha: 0.22),
      ),
      drawerTheme: DrawerThemeData(backgroundColor: skin.surface),
      cardTheme: CardThemeData(
        color: skin.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(skin.cardRadius),
          side: BorderSide(color: skin.outline, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: skin.surfaceHigh,
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
