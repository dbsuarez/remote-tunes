import 'package:flutter_riverpod/flutter_riverpod.dart';

/// How big the text in song lists is. A setting on the phone app; the web
/// Controller always uses the default.
enum SongListSize {
  small(0.85, 'Small'),
  normal(1.0, 'Normal'),
  large(1.15, 'Large');

  const SongListSize(this.scale, this.label);

  final double scale;
  final String label;

  static SongListSize parse(String? name) => values.firstWhere(
        (s) => s.name == name,
        orElse: () => SongListSize.small,
      );
}

/// Kept in step with the saved setting by the phone app (see app.dart).
final songListSizeProvider =
    StateProvider<SongListSize>((ref) => SongListSize.small);
