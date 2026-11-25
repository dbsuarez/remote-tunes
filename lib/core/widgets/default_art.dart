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

  /// A round picture for an artist with no photo.
  static Widget artistAvatar({double radius = 20}) => CircleAvatar(
        radius: radius,
        backgroundImage: ResizeImage(
          const AssetImage(artistAsset),
          width: (radius * 4).clamp(48, 400).round(),
        ),
      );

  /// A round picture for a song with no cover (in lists).
  static Widget albumAvatar({double radius = 20}) => CircleAvatar(
        radius: radius,
        backgroundImage: ResizeImage(
          const AssetImage(albumAsset),
          width: (radius * 4).clamp(48, 400).round(),
        ),
      );
}
