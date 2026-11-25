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
    this.albumArtist,
    this.genre,
    this.year,
    this.replayGainDb,
    this.albumGainDb,
  });

  /// Replay Gain tags in dB (see [parseReplayGain]).
  final double? replayGainDb;
  final double? albumGainDb;

  final String? albumArtist;

  /// The first genre in the tags.
  final String? genre;
  final int? year;

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

/// Reads a Replay Gain value such as `-6.54 dB`, `+3 dB` or `0.5`. Returns null
/// for anything that is not a sensible number (a gain beyond +-30 dB is a bad tag).
double? parseReplayGain(String? text) {
  if (text == null) return null;
  final m = RegExp(r'^\s*([+-]?\d+(?:[.,]\d+)?)\s*(?:db)?\s*$', caseSensitive: false)
      .firstMatch(text.trim());
  if (m == null) return null;
  final v = double.tryParse(m.group(1)!.replaceAll(',', '.'));
  if (v == null || v.isNaN || v.abs() > 30) return null;
  return v;
}

({double? track, double? album}) _readGains(String path) {
  try {
    final tag = readAllMetadata(File(path), getImage: false);
    if (tag is Mp3Metadata) {
      String? find(String key) {
        for (final e in tag.customMetadata.entries) {
          if (e.key.toUpperCase() == key) return e.value;
        }
        return null;
      }

      return (
        track: parseReplayGain(find('REPLAYGAIN_TRACK_GAIN')),
        album: parseReplayGain(find('REPLAYGAIN_ALBUM_GAIN')),
      );
    }
    if (tag is VorbisMetadata) {
      return (
        track: parseReplayGain(tag.replayGainTrackGain.isEmpty ? null : tag.replayGainTrackGain.first),
        album: parseReplayGain(tag.replayGainAlbumGain.isEmpty ? null : tag.replayGainAlbumGain.first),
      );
    }
  } catch (_) {
    // No gains for this file.
  }
  return (track: null, album: null);
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

  String? genre;
  try {
    genre = m.genres.isEmpty ? null : clean(m.genres.first);
  } catch (_) {
    genre = null; // some formats never set it
  }
  final year = m.year?.year;

  final gains = _readGains(path);

  return ExtractedMetadata(
    replayGainDb: gains.track,
    albumGainDb: gains.album,
    albumArtist: clean(m.albumArtist),
    genre: genre,
    year: (year != null && year >= 1000 && year <= 2999) ? year : null,
    title: clean(m.title),
    artist: clean(m.artist),
    album: clean(m.album),
    durationSeconds: m.duration?.inSeconds,
    trackNumber: m.trackNumber,
    artBytes: (cover != null && cover.bytes.isNotEmpty) ? cover.bytes : null,
    artMimeType: cover?.mimetype,
  );
}
