import 'dart:io';
import 'dart:isolate';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

import '../../library/metadata_extractor.dart' show extensionOf;

/// Builds the short description shown under the seek bar, such as
/// `48 kHz · 256 kbps · MP3`. Anything unknown is left out; null when nothing
/// is known.
String? describeAudio({String? codec, int? bitrate, int? sampleRate}) {
  final parts = <String>[];
  if (sampleRate != null && sampleRate >= 8000 && sampleRate <= 768000) {
    final khz = sampleRate / 1000;
    final text = khz == khz.roundToDouble() ? khz.toStringAsFixed(0) : khz.toStringAsFixed(1);
    parts.add('$text kHz');
  }
  if (bitrate != null && bitrate > 0) {
    // Some readers give bits per second, others kilobits.
    final kbps = bitrate > 8000 ? (bitrate / 1000).round() : bitrate;
    if (kbps >= 8 && kbps <= 10000) parts.add('$kbps kbps');
  }
  if (codec != null && codec.isNotEmpty) parts.add(codec);
  return parts.isEmpty ? null : parts.join(' · ');
}

/// The name shown for a file extension.
String? codecName(String extension) => switch (extension.toLowerCase()) {
      'mp3' => 'MP3',
      'm4a' => 'M4A',
      'aac' => 'AAC',
      'flac' => 'FLAC',
      'wav' => 'WAV',
      'ogg' => 'OGG',
      'opus' => 'OPUS',
      '' => null,
      final e => e.toUpperCase(),
    };

/// Reads a file's sample rate and bitrate (in a background isolate, so the
/// player never waits for it).
class AudioFormatReader {
  Future<String?> describe(String path) => Isolate.run(() => _read(path));
}

String? _read(String path) {
  final codec = codecName(extensionOf(path));
  try {
    final tag = readAllMetadata(File(path), getImage: false);
    int? bitrate;
    int? rate;
    if (tag is Mp3Metadata) {
      bitrate = tag.bitrate;
      rate = tag.samplerate;
    } else if (tag is Mp4Metadata) {
      bitrate = tag.bitrate;
      rate = tag.sampleRate;
    } else if (tag is VorbisMetadata) {
      bitrate = tag.bitrate;
      rate = tag.sampleRate;
    } else if (tag is RiffMetadata) {
      bitrate = tag.bitrate;
      rate = tag.samplerate;
    } else if (tag is ApeMetadata) {
      bitrate = tag.bitrate;
      rate = tag.sampleRate;
    }
    return describeAudio(codec: codec, bitrate: bitrate, sampleRate: rate);
  } catch (_) {
    return describeAudio(codec: codec);
  }
}
