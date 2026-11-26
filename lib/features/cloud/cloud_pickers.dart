import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// A file chosen to upload: its name, its size, and a way to read it (called when it is uploaded, so
/// a long list is never all held in memory).
class PickedFile {
  const PickedFile({required this.name, required this.size, required this.open});

  final String name;
  final int size;
  final Stream<List<int>> Function() open;

  /// The file name without its extension.
  String get baseName {
    final dot = name.lastIndexOf('.');
    return dot > 0 ? name.substring(0, dot) : name;
  }

  /// The extension without the dot, lowercase (empty if none).
  String get ext {
    final dot = name.lastIndexOf('.');
    return dot > 0 && dot < name.length - 1 ? name.substring(dot + 1).toLowerCase() : '';
  }
}

/// Lets the user pick a notes file with the Cloudflare details and gives its text (null: not offered
/// here, or nothing picked). The phone app and tests provide one.
final cloudNotesPickerProvider = Provider<Future<String?> Function()?>((ref) => null);

/// Lets the user pick songs to upload (the web page provides one; the phone uploads from the Library).
/// An empty list means nothing was picked.
final cloudSongPickerProvider = Provider<Future<List<PickedFile>> Function()?>((ref) => null);

/// Lets the user pick a picture to use as a cover (null: not offered here). Gives null if nothing was picked.
final cloudCoverPickerProvider = Provider<Future<Uint8List?> Function()?>((ref) => null);
