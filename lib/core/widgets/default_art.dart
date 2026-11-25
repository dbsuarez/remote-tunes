import 'package:flutter/material.dart';

/// The pictures shown where a song has no cover and an artist has no photo.
class DefaultArt {
  DefaultArt._();

  static const albumAsset = 'assets/art/default_album_art.jpg';
  static const artistAsset = 'assets/art/default_artist_art.jpg';

  /// A square cover for a song with none ([size] logical pixels, rounded by [radius]).
  static Widget album({required double size, double radius = 0}) => ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.asset(
          albumAsset,
          width: size,
          height: size,
          fit: BoxFit.cover,
          // Decoded at about the size it is shown, so long lists stay light.
          cacheWidth: (size * 2).clamp(48, 600).round(),
          semanticLabel: 'No cover',
        ),
      );

  /// The width the round pictures are decoded at: the same for every size of row, so the picture is
  /// decoded once and kept, and a row never waits for its own copy (that wait showed as a flash).
  static const avatarDecodeWidth = 256;

  /// A round picture for an artist with no photo.
  static Widget artistAvatar({double radius = 20}) => CircleAvatar(
        radius: radius,
        backgroundImage: const ResizeImage(AssetImage(artistAsset), width: avatarDecodeWidth),
      );

  /// A round picture for a song with no cover (in lists).
  static Widget albumAvatar({double radius = 20}) => CircleAvatar(
        radius: radius,
        backgroundImage: const ResizeImage(AssetImage(albumAsset), width: avatarDecodeWidth),
      );

  /// Decodes the default pictures ahead of time (call once, when the app opens), so the first list that
  /// shows them does not flash while they load.
  static Future<void> precache(BuildContext context) async {
    try {
      await Future.wait([
        precacheImage(const ResizeImage(AssetImage(albumAsset), width: avatarDecodeWidth), context),
        precacheImage(const ResizeImage(AssetImage(artistAsset), width: avatarDecodeWidth), context),
      ]);
    } catch (_) {
      // A picture that cannot be preloaded is simply loaded when it is first shown.
    }
  }
}
