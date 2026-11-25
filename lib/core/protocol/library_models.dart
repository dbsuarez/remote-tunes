import '../models/enums.dart';

/// Library and queue DTOs sent over the protocol.
///
/// These carry metadata and ids only. **They never contain file paths**: music
/// files stay on the Player (FR-46).

int _int(Object? v, [int fallback = 0]) => v is num ? v.toInt() : fallback;
String _str(Object? v, [String fallback = '']) => v is String ? v : fallback;

/// Library scopes for `library_request`.
class LibraryScope {
  LibraryScope._();

  static const songs = 'songs';
  static const artists = 'artists';
  static const albums = 'albums';
  static const folders = 'folders';

  /// The folder tree: the folders inside one folder (`parentId`; none: the top).
  static const folderChildren = 'folderChildren';

  /// The top folder of the tree (one item).
  static const folderRoot = 'folderRoot';

  /// Genres, years or album artists (`kind`).
  static const groups = 'groups';
  static const playlists = 'playlists';

  /// What was played from the Online Library (kept on the Player).
  static const onlineHistory = 'onlineHistory';
}

/// Extra song filters for `library_request` (scope `songs`).
class LibraryView {
  LibraryView._();

  static const favorites = 'favorites';
  static const recent = 'recent';

  /// Most played first (only songs played at least once).
  static const top = 'top';

  /// The songs added most recently.
  static const newest = 'newest';

  /// Skipped most often first (only songs skipped at least once).
  static const skipped = 'skipped';

  /// Songs that were never played.
  static const never = 'never';
}

class RemoteSong {
  const RemoteSong({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    this.durationSeconds = 0,
    this.trackNumber,
    this.available = true,
    this.favorite = false,
    this.plays = 0,
    this.skips = 0,
    this.audiobook = false,
  });

  /// An audiobook: it remembers where it was left (see Settings > Audiobooks).
  final bool audiobook;

  final int id;
  final String title;
  final String artist;
  final String album;
  final int durationSeconds;
  final int? trackNumber;

  /// How many times it was played and skipped on the Player.
  final int plays;
  final int skips;

  /// False when the file is missing from the Player's storage.
  final bool available;

  /// Marked as a favorite on the Player.
  final bool favorite;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        'durationSeconds': durationSeconds,
        if (trackNumber != null) 'trackNumber': trackNumber,
        'available': available,
        if (favorite) 'favorite': true,
        if (audiobook) 'audiobook': true,
        if (plays > 0) 'plays': plays,
        if (skips > 0) 'skips': skips,
      };

  factory RemoteSong.fromJson(Map<String, dynamic> j) => RemoteSong(
        id: _int(j['id']),
        title: _str(j['title']),
        artist: _str(j['artist']),
        album: _str(j['album']),
        durationSeconds: _int(j['durationSeconds']),
        trackNumber: j['trackNumber'] is num ? _int(j['trackNumber']) : null,
        available: j['available'] != false,
        favorite: j['favorite'] == true,
        audiobook: j['audiobook'] == true,
        plays: _int(j['plays']),
        skips: _int(j['skips']),
      );
}

class RemoteArtist {
  const RemoteArtist({
    required this.name,
    required this.songCount,
    required this.albumCount,
  });

  final String name;
  final int songCount;
  final int albumCount;

  Map<String, dynamic> toJson() =>
      {'name': name, 'songCount': songCount, 'albumCount': albumCount};

  factory RemoteArtist.fromJson(Map<String, dynamic> j) => RemoteArtist(
        name: _str(j['name']),
        songCount: _int(j['songCount']),
        albumCount: _int(j['albumCount']),
      );
}

/// Which grouping of the library a `groups` request is for.
class GroupKind {
  GroupKind._();

  static const genre = 'genre';
  static const year = 'year';
  static const albumArtist = 'albumArtist';
  static const composer = 'composer';

  /// The audiobooks, one entry per book (its album).
  static const audiobook = 'audiobook';
}

/// A genre, a year or an album artist, with how many songs it holds.
class RemoteGroup {
  const RemoteGroup({required this.name, required this.songCount});

  /// The genre, the year (as text) or the artist.
  final String name;
  final int songCount;

  Map<String, dynamic> toJson() => {'name': name, 'songCount': songCount};

  factory RemoteGroup.fromJson(Map<String, dynamic> j) =>
      RemoteGroup(name: _str(j['name']), songCount: _int(j['songCount']));
}

/// Lyrics for one song, as the Player found them.
class RemoteLyrics {
  const RemoteLyrics({
    this.found = false,
    this.plain = '',
    this.synced = '',
    this.instrumental = false,
    this.source = '',
    this.disabled = false,
    this.failed = false,
  });

  /// Something was found (lyrics, or the song is instrumental).
  final bool found;

  /// Plain text, one line per row.
  final String plain;

  /// LRC text with a time on each line (empty when only plain text exists).
  final String synced;
  final bool instrumental;

  /// Where they came from (shown as credit).
  final String source;

  /// The Player has lyrics switched off in Settings.
  final bool disabled;

  /// The lookup could not reach the internet (try again later).
  final bool failed;

  bool get hasText => plain.isNotEmpty || synced.isNotEmpty;

  Map<String, dynamic> toJson() => {
        'found': found,
        'plain': plain,
        'synced': synced,
        'instrumental': instrumental,
        'source': source,
        'disabled': disabled,
        'failed': failed,
      };

  factory RemoteLyrics.fromJson(Map<String, dynamic> j) => RemoteLyrics(
        found: j['found'] == true,
        plain: _str(j['plain']),
        synced: _str(j['synced']),
        instrumental: j['instrumental'] == true,
        source: _str(j['source']),
        disabled: j['disabled'] == true,
        failed: j['failed'] == true,
      );
}

/// A folder of the Player's music. The Controller only gets an id and names,
/// never the path.
class RemoteFolder {
  const RemoteFolder({
    required this.id,
    required this.name,
    this.parent = '',
    required this.songCount,
    this.hasChildren = false,
  });

  /// In the folder tree: there are folders inside it.
  final bool hasChildren;

  final int id;

  /// The folder's own name (last part of its path).
  final String name;

  /// The name of the folder it is in, to tell apart folders with the same name.
  final String parent;
  final int songCount;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'parent': parent, 'songCount': songCount, if (hasChildren) 'hasChildren': true};

  factory RemoteFolder.fromJson(Map<String, dynamic> j) => RemoteFolder(
        id: _int(j['id']),
        name: _str(j['name']),
        parent: _str(j['parent']),
        songCount: _int(j['songCount']),
        hasChildren: j['hasChildren'] == true,
      );
}

class RemoteAlbum {
  const RemoteAlbum({
    required this.name,
    required this.artist,
    required this.songCount,
  });

  final String name;
  final String artist;
  final int songCount;

  Map<String, dynamic> toJson() =>
      {'name': name, 'artist': artist, 'songCount': songCount};

  factory RemoteAlbum.fromJson(Map<String, dynamic> j) => RemoteAlbum(
        name: _str(j['name']),
        artist: _str(j['artist']),
        songCount: _int(j['songCount']),
      );
}

class RemotePlaylist {
  const RemotePlaylist({
    required this.id,
    required this.name,
    required this.songCount,
  });

  final int id;
  final String name;
  final int songCount;

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'songCount': songCount};

  factory RemotePlaylist.fromJson(Map<String, dynamic> j) => RemotePlaylist(
        id: _int(j['id']),
        name: _str(j['name']),
        songCount: _int(j['songCount']),
      );
}

/// One entry of the Online Library history. The stream link stays on the
/// Player: a Controller plays an entry again by [id].
class RemoteHistoryItem {
  const RemoteHistoryItem({
    required this.id,
    required this.title,
    required this.artist,
    required this.album,
    this.licenseUrl,
    this.imageUrl,
    this.playedAtSeconds = 0,
  });

  final int id;
  final String title;
  final String artist;
  final String album;
  final String? licenseUrl;
  final String? imageUrl;

  /// When it was last played, seconds since 1970.
  final int playedAtSeconds;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'artist': artist,
        'album': album,
        if (licenseUrl != null) 'licenseUrl': licenseUrl,
        if (imageUrl != null) 'imageUrl': imageUrl,
        'playedAt': playedAtSeconds,
      };

  factory RemoteHistoryItem.fromJson(Map<String, dynamic> j) => RemoteHistoryItem(
        id: _int(j['id']),
        title: _str(j['title']),
        artist: _str(j['artist']),
        album: _str(j['album']),
        licenseUrl: j['licenseUrl'] is String ? j['licenseUrl'] as String : null,
        imageUrl: j['imageUrl'] is String ? j['imageUrl'] as String : null,
        playedAtSeconds: _int(j['playedAt']),
      );
}

class LibraryPage<T> {
  const LibraryPage({
    required this.items,
    required this.total,
    required this.offset,
    this.totalSeconds = 0,
  });

  final List<T> items;
  final int total;
  final int offset;

  /// How long all the songs of the list play together (0: not known).
  final int totalSeconds;

  bool get hasMore => offset + items.length < total;
}

class RemoteQueueItem {
  const RemoteQueueItem({
    required this.queueItemId,
    required this.song,
    required this.isCurrent,
  });

  final int queueItemId;
  final RemoteSong song;
  final bool isCurrent;

  Map<String, dynamic> toJson() => {
        'queueItemId': queueItemId,
        'song': song.toJson(),
        'isCurrent': isCurrent,
      };

  factory RemoteQueueItem.fromJson(Map<String, dynamic> j) => RemoteQueueItem(
        queueItemId: _int(j['queueItemId']),
        song: RemoteSong.fromJson(
            j['song'] is Map ? Map<String, dynamic>.from(j['song'] as Map) : {}),
        isCurrent: j['isCurrent'] == true,
      );
}

class QueueSnapshot {
  const QueueSnapshot({
    this.items = const [],
    this.currentIndex = -1,
    this.revision = 0,
    this.shuffle = false,
    this.repeat = RepeatMode.off,
    int? total,
  }) : _total = total;

  final List<RemoteQueueItem> items;
  final int currentIndex;
  final int revision;
  final bool shuffle;
  final RepeatMode repeat;
  final int? _total;

  /// Real number of songs in the queue (more than [items] when cut short).
  int get total => _total ?? items.length;
  bool get isTruncated => total > items.length;

  /// The first [max] items, keeping the real total. A current index beyond the
  /// cut becomes -1 (not in the list).
  QueueSnapshot truncated(int max) => QueueSnapshot(
        items: items.take(max).toList(),
        currentIndex: currentIndex < max ? currentIndex : -1,
        revision: revision,
        shuffle: shuffle,
        repeat: repeat,
        total: total,
      );

  Map<String, dynamic> toJson() => {
        'items': [for (final i in items) i.toJson()],
        'currentIndex': currentIndex,
        'revision': revision,
        'shuffle': shuffle,
        'repeat': repeat.name,
        if (isTruncated) 'total': total,
      };

  factory QueueSnapshot.fromJson(Map<String, dynamic> j) {
    final raw = j['items'];
    return QueueSnapshot(
      items: raw is List
          ? [
              for (final e in raw)
                if (e is Map)
                  RemoteQueueItem.fromJson(Map<String, dynamic>.from(e)),
            ]
          : const [],
      currentIndex: _int(j['currentIndex'], -1),
      revision: _int(j['revision']),
      shuffle: j['shuffle'] == true,
      repeat: RepeatModeX.parse(j['repeat'] is String ? j['repeat'] as String : null),
      total: j['total'] is num ? (j['total'] as num).toInt() : null,
    );
  }
}
