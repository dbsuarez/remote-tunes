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
  static const playlists = 'playlists';
}

/// Extra song filters for `library_request` (scope `songs`).
class LibraryView {
  LibraryView._();

  static const favorites = 'favorites';
  static const recent = 'recent';
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
  });

  final int id;
  final String title;
  final String artist;
  final String album;
  final int durationSeconds;
  final int? trackNumber;

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

class LibraryPage<T> {
  const LibraryPage({
    required this.items,
    required this.total,
    required this.offset,
  });

  final List<T> items;
  final int total;
  final int offset;

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
