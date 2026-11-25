/// Where the personal Cloud Library lives: one Cloudflare R2 bucket. Reading needs only the public
/// address; uploading and deleting also need the access keys (kept on this phone only).
class CloudConfig {
  const CloudConfig({
    this.accountId = '',
    this.bucket = '',
    this.publicUrl = '',
    this.accessKeyId = '',
    this.secretKey = '',
  });

  /// The Cloudflare account id (the first part of the S3 address, 32 letters and digits).
  final String accountId;
  final String bucket;

  /// The bucket's public address, for example `https://pub-xxxx.r2.dev` (no slash at the end).
  final String publicUrl;
  final String accessKeyId;
  final String secretKey;

  /// Enough to browse and play.
  bool get canRead => publicUrl.isNotEmpty;

  /// Enough to upload, delete and rewrite the catalog.
  bool get canWrite =>
      accountId.isNotEmpty && bucket.isNotEmpty && accessKeyId.isNotEmpty && secretKey.isNotEmpty && canRead;

  /// The S3 address the keys work against.
  String get host => '$accountId.r2.cloudflarestorage.com';

  /// The public link of a file in the bucket (`songs/<id>.mp3`).
  String urlFor(String key) => '$publicUrl/$key';

  CloudConfig copyWith({String? accountId, String? bucket, String? publicUrl, String? accessKeyId, String? secretKey}) =>
      CloudConfig(
        accountId: accountId ?? this.accountId,
        bucket: bucket ?? this.bucket,
        publicUrl: publicUrl ?? this.publicUrl,
        accessKeyId: accessKeyId ?? this.accessKeyId,
        secretKey: secretKey ?? this.secretKey,
      );

  /// A plain sentence about what is wrong with these settings, or null. [forWriting] also checks the
  /// keys and the S3 address.
  String? problem({bool forWriting = false}) {
    final url = publicUrl.trim();
    if (url.isEmpty) return 'Paste the public address of your bucket (it starts with https://).';
    if (!url.startsWith('https://') || url.contains(' ') || Uri.tryParse(url)?.host.isEmpty != false) {
      return 'The public address should start with https:// and have no spaces.';
    }
    if (url.endsWith('/')) return 'Take the slash off the end of the public address.';
    if (!forWriting) return null;
    if (!RegExp(r'^[a-f0-9]{32}$', caseSensitive: false).hasMatch(accountId.trim())) {
      return 'The account id is 32 letters and digits (the first part of your R2 S3 address).';
    }
    if (!RegExp(r'^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$').hasMatch(bucket.trim())) {
      return 'The bucket name is lowercase letters, digits and dashes.';
    }
    if (accessKeyId.trim().isEmpty || accessKeyId.contains(' ')) return 'Paste the access key id.';
    if (secretKey.trim().isEmpty || secretKey.contains(' ')) return 'Paste the secret access key.';
    return null;
  }
}

/// One song in the cloud.
class CloudSong {
  const CloudSong({
    required this.id,
    required this.title,
    this.artist = '',
    this.album = '',
    this.genre = '',
    this.year,
    this.track,
    this.durationSeconds = 0,
    required this.audioKey,
    this.artKey,
    this.sizeBytes = 0,
    this.added,
  });

  final String id;
  final String title;
  final String artist;
  final String album;
  final String genre;
  final int? year;
  final int? track;
  final int durationSeconds;

  /// Where the file is in the bucket, for example `songs/<id>.mp3`.
  final String audioKey;

  /// Where the cover is (`artwork/<hash>.jpg`), if there is one.
  final String? artKey;
  final int sizeBytes;
  final DateTime? added;

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        if (artist.isNotEmpty) 'artist': artist,
        if (album.isNotEmpty) 'album': album,
        if (genre.isNotEmpty) 'genre': genre,
        if (year != null) 'year': year,
        if (track != null) 'track': track,
        if (durationSeconds > 0) 'duration': durationSeconds,
        'audio': audioKey,
        if (artKey != null) 'art': artKey,
        if (sizeBytes > 0) 'size': sizeBytes,
        if (added != null) 'added': added!.toUtc().toIso8601String(),
      };

  /// Null for an entry that is not a song (a damaged one is skipped, not trusted).
  static CloudSong? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], title = j['title'], audio = j['audio'];
    if (id is! String || id.isEmpty || title is! String || title.trim().isEmpty) return null;
    // A key is a plain path inside the bucket: no way out of it, no address of somewhere else.
    bool safe(Object? k) => k is String && k.isNotEmpty && !k.contains('..') && !k.startsWith('/') && !k.contains('://');
    if (!safe(audio)) return null;
    String text(Object? v) => v is String ? v.trim() : '';
    int? whole(Object? v) => v is num ? v.toInt() : null;
    DateTime? when;
    try {
      when = j['added'] is String ? DateTime.parse(j['added'] as String).toLocal() : null;
    } catch (_) {
      when = null;
    }
    return CloudSong(
      id: id,
      title: title.trim(),
      artist: text(j['artist']),
      album: text(j['album']),
      genre: text(j['genre']),
      year: whole(j['year']),
      track: whole(j['track']),
      durationSeconds: (whole(j['duration']) ?? 0).clamp(0, 86400 * 3),
      audioKey: audio as String,
      artKey: safe(j['art']) ? j['art'] as String : null,
      sizeBytes: (whole(j['size']) ?? 0).clamp(0, 1 << 40),
      added: when,
    );
  }
}

/// The list of everything in the cloud (one file, `catalog.json`, in the bucket).
class CloudCatalog {
  const CloudCatalog([this.songs = const []]);

  static const fileName = 'catalog.json';
  static const version = 1;

  final List<CloudSong> songs;

  bool get isEmpty => songs.isEmpty;
  int get totalBytes => songs.fold(0, (s, x) => s + x.sizeBytes);

  Map<String, dynamic> toJson() => {
        'version': version,
        'updated': DateTime.now().toUtc().toIso8601String(),
        'songs': [for (final s in songs) s.toJson()],
      };

  /// Reads the catalog file. Bad entries are left out; a file that is not a catalog gives an empty one.
  static CloudCatalog fromJson(Object? j) {
    if (j is! Map || j['songs'] is! List) return const CloudCatalog();
    return CloudCatalog([
      for (final e in j['songs'] as List)
        if (CloudSong.fromJson(e) case final s?) s,
    ]);
  }

  /// This catalog with [add] put in (a song already there by id is kept as it was) and [remove] taken out.
  CloudCatalog changed({Iterable<CloudSong> add = const [], Iterable<String> remove = const []}) {
    final gone = remove.toSet();
    final have = {for (final s in songs) s.id};
    return CloudCatalog([
      for (final s in songs)
        if (!gone.contains(s.id)) s,
      for (final s in add)
        if (!have.contains(s.id) && !gone.contains(s.id)) s,
    ]);
  }

  /// The genres, the most songs first.
  List<({String name, int count})> get genres {
    final n = <String, int>{};
    for (final s in songs) {
      if (s.genre.isNotEmpty) n[s.genre] = (n[s.genre] ?? 0) + 1;
    }
    final list = n.entries.map((e) => (name: e.key, count: e.value)).toList()
      ..sort((a, b) => b.count != a.count ? b.count.compareTo(a.count) : a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Songs matching [query] (words, in the title, artist, album or genre) and, if given, one [genre].
  List<CloudSong> search(String query, {String? genre}) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final out = [
      for (final s in songs)
        if ((genre == null || s.genre.toLowerCase() == genre.toLowerCase()) &&
            words.every((w) => '${s.title} ${s.artist} ${s.album} ${s.genre}'.toLowerCase().contains(w)))
          s,
    ];
    out.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    return out;
  }

  /// A song already here with the same title and artist and about the same length (so the same
  /// recording): used to warn before uploading it twice.
  CloudSong? duplicateOf({required String title, required String artist, required int durationSeconds}) {
    String n(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    for (final s in songs) {
      if (n(s.title) == n(title) &&
          n(s.artist) == n(artist) &&
          (durationSeconds <= 0 || s.durationSeconds <= 0 || (s.durationSeconds - durationSeconds).abs() <= 3)) {
        return s;
      }
    }
    return null;
  }
}
