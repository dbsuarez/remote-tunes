import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

/// File extensions RemoteTunes will import (FR-38). Whether a particular file
/// actually plays still depends on the phone's decoders.
const Set<String> supportedAudioExtensions = {
  'mp3',
  'm4a',
  'aac',
  'flac',
  'wav',
  'ogg',
  'opus',
};

String extensionOf(String path) {
  final name = path.split(RegExp(r'[\\/]')).last;
  final dot = name.lastIndexOf('.');
  return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
}

bool isSupportedAudio(String path) =>
    supportedAudioExtensions.contains(extensionOf(path));

/// Tags read from a file. Every field is optional: untagged files fall back to
/// their file name in the import service.
class ExtractedMetadata {
  const ExtractedMetadata({
    this.title,
    this.artist,
    this.album,
    this.durationSeconds,
    this.trackNumber,
    this.artBytes,
    this.artMimeType,
  });

  final String? title;
  final String? artist;
  final String? album;
  final int? durationSeconds;
  final int? trackNumber;
  final Uint8List? artBytes;
  final String? artMimeType;
}

abstract class MetadataExtractor {
  /// Reads tags and embedded cover art. Never needs to throw for files that
  /// simply have no tags; may throw for unreadable files.
  Future<ExtractedMetadata> extract(String path);
}

/// Reads tags with `audio_metadata_reader` in a background isolate so large
/// files and cover images never block the UI.
class AudioMetadataExtractor implements MetadataExtractor {
  @override
  Future<ExtractedMetadata> extract(String path) =>
      Isolate.run(() => _read(path));
}

ExtractedMetadata _read(String path) {
  final file = File(path);
  final AudioMetadata m;
  try {
    m = readMetadata(file, getImage: true);
  } on MetadataParserException {
    return const ExtractedMetadata();
  } on NoMetadataParserException {
    return const ExtractedMetadata();
  }

  Picture? cover;
  for (final p in m.pictures) {
    if (p.pictureType == PictureType.coverFront) {
      cover = p;
      break;
    }
  }
  cover ??= m.pictures.isNotEmpty ? m.pictures.first : null;

  String? clean(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  return ExtractedMetadata(
    title: clean(m.title),
    artist: clean(m.artist),
    album: clean(m.album),
    durationSeconds: m.duration?.inSeconds,
    trackNumber: m.trackNumber,
    artBytes: (cover != null && cover.bytes.isNotEmpty) ? cover.bytes : null,
    artMimeType: cover?.mimetype,
  );
}
