import 'dart:typed_data';

import '../../core/protocol/library_models.dart';

/// One possible match for a song, from MusicBrainz.
class LookupMatch {
  const LookupMatch({
    required this.title,
    required this.artist,
    required this.album,
    this.year,
    this.trackNumber,
    this.releaseId,
    this.score = 0,
    this.lengthSeconds,
  });

  final String title;
  final String artist;
  final String album;
  final int? year;
  final int? trackNumber;

  /// For the cover (Cover Art Archive).
  final String? releaseId;
  final int score;
  final int? lengthSeconds;

  /// "Title · Artist · Album (1999) · track 3".
  String get label => [
        title,
        artist,
        if (album.isNotEmpty) year == null ? album : '$album ($year)',
      ].join(' · ');
}

/// A cover picture found for a match.
class LookupCover {
  const LookupCover(this.bytes, this.ext);
  final Uint8List bytes;
  final String ext;
}

/// What the look-up window needs (the phone's [SongLookup] does it; kept apart so the shared
/// screens do not pull in the database).
abstract class SongLookupService {
  Future<List<LookupMatch>> search({
    required String title,
    String artist,
    String album,
    int durationSeconds,
  });
  Future<LookupCover?> coverFor(LookupMatch m);
  Future<RemoteLyrics> lyricsFor(int songId);
  Future<void> discardLyrics(int songId);
  Future<int> applyCover(int songId, LookupCover cover);
}

/// A lookup that could not be done, with a sentence to show.
class LookupException implements Exception {
  const LookupException(this.message);
  final String message;
  @override
  String toString() => message;
}
