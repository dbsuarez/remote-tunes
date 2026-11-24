/// A song the Player can actually play: a local file or an internet URL.
/// Includes the file path/URL, so it stays on the Player and is never
/// serialized to a Controller.
class PlayableSong {
  const PlayableSong({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    this.filePath,
    this.url,
    this.durationSeconds = 0,
    this.trackNumber,
    this.albumArtPath,
    this.licenseUrl,
    this.imageUrl,
  }) : assert((filePath == null) != (url == null),
            'A song has either a file path or a url, not both.');

  /// A one-off internet stream. It is not part of the library (id 0).
  const PlayableSong.stream({
    required String this.url,
    required this.title,
    this.artist = 'Internet',
    this.album = 'Web audio',
    this.licenseUrl,
    this.imageUrl,
  })  : id = 0,
        filePath = null,
        durationSeconds = 0,
        trackNumber = null,
        albumArtPath = null;

  /// Library id (0 for internet streams).
  final int id;
  final String title;
  final String artist;
  final String album;
  final String? filePath;
  final String? url;
  final int durationSeconds;
  final int? trackNumber;
  final String? albumArtPath;

  /// Online Library tracks: the Creative Commons licence link and the artwork
  /// link (always on jamendo.com / creativecommons.org). Null otherwise.
  final String? licenseUrl;
  final String? imageUrl;

  bool get isUrl => url != null;

  /// Id reported in playback state: null for streams, which are not in the
  /// library.
  int? get libraryId => isUrl ? null : id;
}
