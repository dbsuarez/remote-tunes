import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';

import 'tag_editor.dart';

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

/// Writes tags and cover pictures into MP3, M4A and FLAC files. Only what is changed is rewritten
/// ([rewriteTags]), so lyrics, loudness values and other tags stay. Other kinds are left untouched:
/// the tag library's writers lose tags, and its WAV writer changes the sound itself.
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
    return _safely(
      path,
      fields: {
        TagField.title: title,
        TagField.artist: artist,
        TagField.album: album,
        TagField.track: trackNumber?.toString(),
      },
      // Only what reads back counts.
      check: (before, after) => after.title == title,
    );
  }

  /// Writes only the fields that songs can share: [changes] has the keys `artist`, `album`,
  /// `albumArtist`, `genre`, `year` (an int) and `composer`; a null value clears that field.
  /// Title and track number are never touched.
  TagWriteResult writeGroup(String path, Map<String, Object?> changes) {
    const names = {
      'artist': TagField.artist,
      'album': TagField.album,
      'albumArtist': TagField.albumArtist,
      'genre': TagField.genre,
      'year': TagField.year,
      'composer': TagField.composer,
    };
    return _safely(
      path,
      fields: {
        for (final e in changes.entries)
          if (names[e.key] case final field?) field: e.value?.toString(),
      },
      // (The artist is not compared: read back, an MP3 with an album artist gives that instead.)
      check: (before, after) => changes['album'] == null || after.album == changes['album'],
    );
  }

  /// Writes a changed copy of the file, checks it, and only then lets it take the file's place, so a
  /// song cannot be left half written.
  TagWriteResult _safely(
    String path, {
    Map<TagField, String?> fields = const {},
    Uint8List? cover,
    required bool Function(AudioMetadata before, AudioMetadata after) check,
  }) {
    final file = File(path);
    if (!file.existsSync()) return TagWriteResult.missing;
    final copy = File('$path.rtcover');
    try {
      if (!rewriteTags(file, copy, fields, cover: cover)) return TagWriteResult.unsupported;
      final before = readMetadata(file, getImage: false);
      final after = readMetadata(copy, getImage: cover != null);
      // Only what reads back counts.
      if (!check(before, after)) return TagWriteResult.unsupported;
      if (cover != null) {
        if (!after.pictures.any((p) => _same(p.bytes, cover))) return TagWriteResult.unsupported;
        // The words must still be there.
        if (after.title != before.title || after.artist != before.artist || after.album != before.album) {
          return TagWriteResult.failed;
        }
      }
      copy.renameSync(path);
      return TagWriteResult.written;
    } on FileSystemException {
      return TagWriteResult.notAllowed;
    } on TagUnsupported {
      return TagWriteResult.unsupported;
    } on UnsupportedError {
      return TagWriteResult.unsupported;
    } on NoMetadataParserException {
      return TagWriteResult.unsupported;
    } catch (_) {
      return TagWriteResult.failed;
    } finally {
      try {
        if (copy.existsSync()) copy.deleteSync();
      } catch (_) {}
    }
  }

  /// Puts [picture] (a JPEG) into the music file as its front cover (MP3, M4A and FLAC).
  TagWriteResult writeCover(String path, Uint8List picture) =>
      _safely(path, cover: picture, check: (_, __) => true);

  static bool _same(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// What happened to the cover across the files it was written into.
  static String coverMessage(List<TagWriteResult> results) {
    if (results.isEmpty) return 'Cover saved in RemoteTunes';
    final done = results.where((r) => r == TagWriteResult.written).length;
    final n = results.length;
    if (done == n) return n == 1 ? 'Cover written into the music file' : 'Cover written into $n music files';
    final why = results.firstWhere((r) => r != TagWriteResult.written);
    final reason = switch (why) {
      TagWriteResult.missing => 'a file was not found',
      TagWriteResult.notAllowed => 'Android does not let the app change them (Settings > All files access)',
      TagWriteResult.unsupported => 'this kind of file cannot take a picture',
      _ => 'a file could not be changed',
    };
    return done == 0 ? 'Cover saved in RemoteTunes only: $reason' : 'Cover written into $done of $n files: $reason';
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
