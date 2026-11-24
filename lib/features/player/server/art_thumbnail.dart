import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Longest side of the album-art thumbnail sent to a Controller (pixels).
const int artThumbnailSize = 256;

/// Smallest size a Controller may ask for (list rows use this).
const int artThumbnailMinSize = 48;

/// Biggest thumbnail we will send; the online relay limits message size.
const int artThumbnailMaxBytes = 60 * 1024;

/// Reads [path] and returns a small JPEG with a longest side of [size], or
/// null if the file is missing or is not an image. The work runs off the UI
/// thread.
Future<Uint8List?> loadArtThumbnail(String path, {int size = artThumbnailSize}) async {
  final File file = File(path);
  if (!await file.exists()) return null;
  final Uint8List bytes;
  try {
    bytes = await file.readAsBytes();
  } on FileSystemException {
    return null;
  }
  final s = size.clamp(artThumbnailMinSize, artThumbnailSize);
  return compute(_thumbnailJob, (bytes, s));
}

Uint8List? _thumbnailJob((Uint8List, int) job) => makeThumbnail(job.$1, size: job.$2);

/// Shrinks image [bytes] to a JPEG thumbnail. Null if they are not an image
/// or the result is still too big.
Uint8List? makeThumbnail(Uint8List bytes, {int size = artThumbnailSize}) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final longest = decoded.width > decoded.height ? decoded.width : decoded.height;
    final small = longest > size
        ? img.copyResize(decoded,
            width: decoded.width >= decoded.height ? size : null,
            height: decoded.height > decoded.width ? size : null)
        : decoded;
    for (final quality in const [80, 60, 40]) {
      final out = Uint8List.fromList(img.encodeJpg(small, quality: quality));
      if (out.length <= artThumbnailMaxBytes) return out;
    }
  } catch (_) {
    // A damaged image: no art.
  }
  return null;
}
