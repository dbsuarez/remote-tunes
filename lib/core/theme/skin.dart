import 'dart:convert';

import 'package:flutter/material.dart';

/// A look for the app: the colors behind the screens and the default accent
/// (used when a song has no cover color), and how round the cards are.
///
/// Written as JSON so skins can be shared:
/// ```json
/// {"name":"Ocean","background":"#0B1220","surface":"#111B2E","surfaceHigh":"#18263F",
///  "outline":"#2C3E5E","primary":"#4FC3F7","secondary":"#B388FF","cardRadius":16}
/// ```
class Skin {
  const Skin({
    required this.id,
    required this.name,
    required this.background,
    required this.surface,
    required this.surfaceHigh,
    required this.outline,
    required this.primary,
    required this.secondary,
    this.cardRadius = 16,
    this.builtIn = false,
  });

  /// What is saved to remember the choice (the name, lower case, for built-in and
  /// shared skins).
  final String id;
  final String name;
  final Color background;
  final Color surface;
  final Color surfaceHigh;
  final Color outline;

  /// The accent when the song has no cover color.
  final Color primary;
  final Color secondary;
  final double cardRadius;
  final bool builtIn;

  static const defaultId = 'remotetunes';

  /// The look the app has always had: charcoal with electric teal and violet.
  static const remoteTunes = Skin(
    id: defaultId,
    name: 'RemoteTunes',
    background: Color(0xFF111317),
    surface: Color(0xFF1A1D23),
    surfaceHigh: Color(0xFF242830),
    outline: Color(0xFF3A3F4A),
    primary: Color(0xFF22E5D0),
    secondary: Color(0xFF9B8CFF),
    builtIn: true,
  );

  static const builtIns = <Skin>[
    remoteTunes,
    Skin(
      id: 'midnight',
      name: 'Midnight',
      background: Color(0xFF0B1220),
      surface: Color(0xFF111B2E),
      surfaceHigh: Color(0xFF18263F),
      outline: Color(0xFF2C3E5E),
      primary: Color(0xFF4FC3F7),
      secondary: Color(0xFFB388FF),
      builtIn: true,
    ),
    Skin(
      id: 'ember',
      name: 'Ember',
      background: Color(0xFF16100E),
      surface: Color(0xFF211815),
      surfaceHigh: Color(0xFF2E2220),
      outline: Color(0xFF4A3834),
      primary: Color(0xFFFF8A50),
      secondary: Color(0xFFFFC857),
      cardRadius: 20,
      builtIn: true,
    ),
    Skin(
      id: 'forest',
      name: 'Forest',
      background: Color(0xFF0E1511),
      surface: Color(0xFF16201A),
      surfaceHigh: Color(0xFF1F2C24),
      outline: Color(0xFF34473B),
      primary: Color(0xFF9ACD32),
      secondary: Color(0xFF4DB6AC),
      builtIn: true,
    ),
    Skin(
      id: 'rose',
      name: 'Rose',
      background: Color(0xFF170F14),
      surface: Color(0xFF22171E),
      surfaceHigh: Color(0xFF2F2029),
      outline: Color(0xFF4D3A46),
      primary: Color(0xFFFF6B8B),
      secondary: Color(0xFFCE93D8),
      cardRadius: 24,
      builtIn: true,
    ),
    Skin(
      id: 'amoled',
      name: 'Pure black',
      background: Color(0xFF000000),
      surface: Color(0xFF0B0B0B),
      surfaceHigh: Color(0xFF161616),
      outline: Color(0xFF2A2A2A),
      primary: Color(0xFF22E5D0),
      secondary: Color(0xFF9B8CFF),
      cardRadius: 12,
      builtIn: true,
    ),
    Skin(
      id: 'mono',
      name: 'Mono',
      background: Color(0xFF121212),
      surface: Color(0xFF1C1C1C),
      surfaceHigh: Color(0xFF282828),
      outline: Color(0xFF444444),
      primary: Color(0xFFE0E0E0),
      secondary: Color(0xFF9E9E9E),
      cardRadius: 8,
      builtIn: true,
    ),
  ];

  static Skin byId(String? id, [List<Skin> custom = const []]) {
    for (final s in [...builtIns, ...custom]) {
      if (s.id == id) return s;
    }
    return remoteTunes;
  }

  String toJson() => const JsonEncoder.withIndent('  ').convert({
        'name': name,
        'background': _hex(background),
        'surface': _hex(surface),
        'surfaceHigh': _hex(surfaceHigh),
        'outline': _hex(outline),
        'primary': _hex(primary),
        'secondary': _hex(secondary),
        'cardRadius': cardRadius,
      });

  /// Reads a skin from JSON text. Throws a [SkinException] saying what is wrong.
  static Skin parse(String text) {
    final Object? raw;
    try {
      raw = jsonDecode(text);
    } catch (_) {
      throw const SkinException('That is not valid JSON.');
    }
    if (raw is! Map) throw const SkinException('A skin is a JSON object, like {"name": ...}.');
    final Map map = raw;
    final name = map['name'];
    if (name is! String || name.trim().isEmpty) {
      throw const SkinException('The skin needs a "name".');
    }
    if (name.trim().length > 30) throw const SkinException('The name is too long (30 letters at most).');
    Color color(String key) {
      final v = map[key];
      if (v is! String) throw SkinException('"$key" is missing: use a color like "#22E5D0".');
      final c = _parseHex(v);
      if (c == null) throw SkinException('"$key" is not a color (use #RRGGBB).');
      return c;
    }

    final background = color('background');
    final surface = color('surface');
    final surfaceHigh = color('surfaceHigh');
    final outline = color('outline');
    final primary = color('primary');
    final secondary = color('secondary');
    // The app is a dark one: light backgrounds would make the white text
    // unreadable.
    if (background.computeLuminance() > 0.25 || surface.computeLuminance() > 0.3) {
      throw const SkinException('Skins are dark: the background and surface must be dark colors.');
    }
    if (_contrast(primary, background) < 3 || _contrast(secondary, background) < 3) {
      throw const SkinException(
          'The primary and secondary colors are too dark to read on the background.');
    }
    final r = map['cardRadius'];
    final radius = r is num ? r.toDouble().clamp(0.0, 32.0) : 16.0;
    final id = name.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '-');
    return Skin(
      id: id,
      name: name.trim(),
      background: background,
      surface: surface,
      surfaceHigh: surfaceHigh,
      outline: outline,
      primary: primary,
      secondary: secondary,
      cardRadius: radius,
    );
  }

  static String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

  static Color? _parseHex(String s) {
    final m = RegExp(r'^#?([0-9a-fA-F]{6})$').firstMatch(s.trim());
    if (m == null) return null;
    return Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
  }

  static double _contrast(Color a, Color b) {
    final la = a.computeLuminance() + 0.05;
    final lb = b.computeLuminance() + 0.05;
    return la > lb ? la / lb : lb / la;
  }

  @override
  bool operator ==(Object other) =>
      other is Skin && other.id == id && other.toJson() == toJson();

  @override
  int get hashCode => Object.hash(id, toJson());
}

class SkinException implements Exception {
  const SkinException(this.message);
  final String message;
  @override
  String toString() => message;
}
