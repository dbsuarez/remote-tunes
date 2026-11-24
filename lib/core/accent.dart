import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:material_color_utilities/material_color_utilities.dart';

/// Whether the Controller tints its screens with a color taken from the album
/// art (Settings > Colors from album art). Kept in step with the saved setting
/// by the phone app; the web page uses the default.
final accentFromArtProvider = StateProvider<bool>((ref) => true);

/// Spotify's brand green is off limits as an identity (docs/15). A cover that
/// happens to be that green gets its accent nudged toward teal.
const int _spotifyGreen = 0xFF1DB954;

double _hueDistance(double a, double b) {
  final d = (a - b).abs() % 360;
  return d > 180 ? 360 - d : d;
}

/// Makes a color from album art fit the dark Controller: vivid enough to be an
/// accent, light enough to read on the charcoal background (so a progress bar
/// is never lost), not too extreme, and never Spotify's green.
Color normalizeAccent(Color c) {
  final hct = Hct.fromInt(c.toARGB32());
  var hue = hct.hue;
  final chroma = hct.chroma.clamp(42.0, 82.0).toDouble();
  final tone = hct.tone.clamp(62.0, 80.0).toDouble();
  final brand = Hct.fromInt(_spotifyGreen);
  if (_hueDistance(hue, brand.hue) < 16 && chroma > 45) {
    hue = (hue + 32) % 360; // toward teal, which is RemoteTunes' own color
  }
  return Color(Hct.from(hue, chroma, tone).toInt());
}

/// The most characteristic vivid color among [argbPixels] (opaque ARGB ints),
/// or null if the picture has none (grey, black and white, or empty).
Future<Color?> accentFromArgbPixels(List<int> argbPixels) async {
  if (argbPixels.isEmpty) return null;
  final result = await QuantizerCelebi().quantize(argbPixels, 64);
  // Fallback 0 means "nothing suitable": a grey cover gives no accent.
  final ranked = Score.score(result.colorToCount, desired: 1, fallbackColorARGB: 0);
  if (ranked.isEmpty || ranked.first == 0) return null;
  return normalizeAccent(Color(ranked.first));
}

/// Works out the accent color of a small album-art image (any format Flutter
/// decodes). Decodes at a tiny size, so it is quick. Null if there is none or
/// the bytes are not an image.
Future<Color?> accentFromImageBytes(Uint8List bytes) async {
  try {
    final codec =
        await ui.instantiateImageCodec(bytes, targetWidth: 48, targetHeight: 48);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.image.dispose();
    codec.dispose();
    if (data == null) return null;
    final px = <int>[];
    for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
      final a = data.getUint8(i + 3);
      if (a < 128) continue; // see-through pixels say nothing about the cover
      px.add((0xFF << 24) |
          (data.getUint8(i) << 16) |
          (data.getUint8(i + 1) << 8) |
          data.getUint8(i + 2));
    }
    return accentFromArgbPixels(px);
  } catch (_) {
    return null;
  }
}

/// Remembers the accent of recent songs, so going back to one is instant.
class AccentCache {
  AccentCache({this.maxEntries = 100});

  final int maxEntries;
  final Map<int, Future<Color?>> _byId = {};

  /// The accent for [songId], computed once from [loadArt].
  Future<Color?> forSong(int songId, Future<Uint8List?> Function(int id) loadArt) {
    final known = _byId.remove(songId);
    if (known != null) {
      _byId[songId] = known; // most recently used goes last
      return known;
    }
    final job = () async {
      final bytes = await loadArt(songId);
      return bytes == null ? null : accentFromImageBytes(bytes);
    }();
    _byId[songId] = job;
    if (_byId.length > maxEntries) _byId.remove(_byId.keys.first);
    return job;
  }
}
