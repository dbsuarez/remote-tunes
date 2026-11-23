import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;

/// Longest side of the album-art thumbnail sent to a Controller (pixels).
const int artThumbnailSize = 256;

/// Biggest thumbnail we will send; the online relay limits message size.
const int artThumbnailMaxBytes = 60 * 1024;

/// Reads [path] and returns a small JPEG, or null if the file is missing or
/// is not an image. The work runs off the UI thread.
Future<Uint8List?> loadArtThumbnail(String path) async {
  final File file = File(path);
  if (!await file.exists()) return null;
  final Uint8List bytes;
  try {
    bytes = await file.readAsBytes();
  } on FileSystemException {
    return null;
  }
  return compute(makeThumbnail, bytes);
}

/// Shrinks image [bytes] to a JPEG thumbnail. Null if they are not an image
/// or the result is still too big.
Uint8List? makeThumbnail(Uint8List bytes) {
  try {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) return null;
    final longest = decoded.width > decoded.height ? decoded.width : decoded.height;
    final small = longest > artThumbnailSize
        ? img.copyResize(decoded,
            width: decoded.width >= decoded.height ? artThumbnailSize : null,
            height: decoded.height > decoded.width ? artThumbnailSize : null)
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
