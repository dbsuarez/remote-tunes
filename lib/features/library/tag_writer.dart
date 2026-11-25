import 'dart:io';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

/// What happened when tags were written into a music file.
enum TagWriteResult {
  written,

  /// The file is gone.
  missing,

  /// Android (or the file) did not allow the change.
  notAllowed,

  /// The kind of file cannot be tagged by the app.
  unsupported,

  /// Something else went wrong; the file was left as it was.
  failed,
}

/// Writes title, artist, album and track number into the music file itself
/// (MP3, M4A, FLAC, WAV...), keeping the other tags (cover, lyrics, ...).
///
/// On newer Android versions an app cannot change files in shared folders
/// unless it has been given that right, so [notAllowed] is a normal outcome.
class TagWriter {
  const TagWriter();

  TagWriteResult write(
    String path, {
    required String title,
    required String artist,
    required String album,
    int? trackNumber,
  }) {
    final file = File(path);
    if (!file.existsSync()) return TagWriteResult.missing;
    try {
      updateMetadata(file, (m) {
        m.setTitle(title);
        m.setArtist(artist);
        m.setAlbum(album);
        m.setTrackNumber(trackNumber);
      });
      // The library does nothing (and says nothing) for a file it does not
      // recognise: only what reads back counts.
      final back = readMetadata(file, getImage: false);
      return back.title == title ? TagWriteResult.written : TagWriteResult.unsupported;
    } on FileSystemException {
      return TagWriteResult.notAllowed;
    } on UnsupportedError {
      return TagWriteResult.unsupported;
    } on NoMetadataParserException {
      return TagWriteResult.unsupported;
    } catch (_) {
      return TagWriteResult.failed;
    }
  }

  /// Writes only the fields that songs can share: [changes] has the keys `artist`, `album`,
  /// `albumArtist`, `genre`, `year` (an int) and `composer`; a null value clears that field.
  /// Title and track number are never touched. Fields a kind of file has no place for (an album
  /// artist in an M4A, for example) are skipped.
  TagWriteResult writeGroup(String path, Map<String, Object?> changes) {
    final file = File(path);
    if (!file.existsSync()) return TagWriteResult.missing;
    try {
      updateMetadata(file, (m) {
        for (final e in changes.entries) {
          final v = e.value;
          switch (e.key) {
            case 'artist':
              m.setArtist(v as String?);
            case 'album':
              m.setAlbum(v as String?);
            case 'genre':
              m.setGenres(v == null ? const [] : [v as String]);
            case 'year':
              m.setYear(v == null ? null : DateTime(v as int));
            case 'albumArtist':
              final s = v as String?;
              if (m is Mp3Metadata) {
                m.bandOrOrchestra = s;
              } else if (m is VorbisMetadata) {
                m.albumArtist = s == null ? [] : [s];
              } else if (m is ApeMetadata) {
                m.albumArtist = s;
              }
            case 'composer':
              final s = v as String?;
              if (m is Mp3Metadata) {
                m.composer = s;
              } else if (m is VorbisMetadata) {
                m.composer = s == null ? [] : [s];
              } else if (m is ApeMetadata) {
                m.composer = s;
              }
          }
        }
      });
      // Only what reads back counts (the library ignores files it does not know).
      final back = readMetadata(file, getImage: false);
      if (changes.containsKey('artist') && changes['artist'] != null && back.artist != changes['artist']) {
        return TagWriteResult.unsupported;
      }
      if (changes.containsKey('album') && changes['album'] != null && back.album != changes['album']) {
        return TagWriteResult.unsupported;
      }
      return TagWriteResult.written;
    } on FileSystemException {
      return TagWriteResult.notAllowed;
    } on UnsupportedError {
      return TagWriteResult.unsupported;
    } on NoMetadataParserException {
      return TagWriteResult.unsupported;
    } catch (_) {
      return TagWriteResult.failed;
    }
  }

  /// A plain sentence for the result, shown after saving.
  static String message(TagWriteResult r) => switch (r) {
        TagWriteResult.written => 'Saved, and written into the music file',
        TagWriteResult.missing => 'Saved in RemoteTunes; the music file was not found',
        TagWriteResult.notAllowed =>
          'Saved in RemoteTunes only: Android does not let the app change that file (Settings > All files access)',
        TagWriteResult.unsupported =>
          'Saved in RemoteTunes only: this kind of file cannot be tagged by the app',
        TagWriteResult.failed => 'Saved in RemoteTunes only: the file could not be changed',
      };
}
