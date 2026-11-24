// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $SongsTable extends Songs with TableInfo<$SongsTable, Song> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SongsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
    'artist',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _albumMeta = const VerificationMeta('album');
  @override
  late final GeneratedColumn<String> album = GeneratedColumn<String>(
    'album',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _durationSecondsMeta = const VerificationMeta(
    'durationSeconds',
  );
  @override
  late final GeneratedColumn<int> durationSeconds = GeneratedColumn<int>(
    'duration_seconds',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _trackNumberMeta = const VerificationMeta(
    'trackNumber',
  );
  @override
  late final GeneratedColumn<int> trackNumber = GeneratedColumn<int>(
    'track_number',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _filePathMeta = const VerificationMeta(
    'filePath',
  );
  @override
  late final GeneratedColumn<String> filePath = GeneratedColumn<String>(
    'file_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _albumArtPathMeta = const VerificationMeta(
    'albumArtPath',
  );
  @override
  late final GeneratedColumn<String> albumArtPath = GeneratedColumn<String>(
    'album_art_path',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _fileSizeBytesMeta = const VerificationMeta(
    'fileSizeBytes',
  );
  @override
  late final GeneratedColumn<int> fileSizeBytes = GeneratedColumn<int>(
    'file_size_bytes',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: DateTime.now,
  );
  static const VerificationMeta _favoriteMeta = const VerificationMeta(
    'favorite',
  );
  @override
  late final GeneratedColumn<bool> favorite = GeneratedColumn<bool>(
    'favorite',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("favorite" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _lastPlayedAtMeta = const VerificationMeta(
    'lastPlayedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastPlayedAt = GeneratedColumn<DateTime>(
    'last_played_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _playCountMeta = const VerificationMeta(
    'playCount',
  );
  @override
  late final GeneratedColumn<int> playCount = GeneratedColumn<int>(
    'play_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    title,
    artist,
    album,
    durationSeconds,
    trackNumber,
    filePath,
    url,
    albumArtPath,
    fileSizeBytes,
    mimeType,
    source,
    addedAt,
    favorite,
    lastPlayedAt,
    playCount,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'songs';
  @override
  VerificationContext validateIntegrity(
    Insertable<Song> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('artist')) {
      context.handle(
        _artistMeta,
        artist.isAcceptableOrUnknown(data['artist']!, _artistMeta),
      );
    }
    if (data.containsKey('album')) {
      context.handle(
        _albumMeta,
        album.isAcceptableOrUnknown(data['album']!, _albumMeta),
      );
    }
    if (data.containsKey('duration_seconds')) {
      context.handle(
        _durationSecondsMeta,
        durationSeconds.isAcceptableOrUnknown(
          data['duration_seconds']!,
          _durationSecondsMeta,
        ),
      );
    }
    if (data.containsKey('track_number')) {
      context.handle(
        _trackNumberMeta,
        trackNumber.isAcceptableOrUnknown(
          data['track_number']!,
          _trackNumberMeta,
        ),
      );
    }
    if (data.containsKey('file_path')) {
      context.handle(
        _filePathMeta,
        filePath.isAcceptableOrUnknown(data['file_path']!, _filePathMeta),
      );
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    }
    if (data.containsKey('album_art_path')) {
      context.handle(
        _albumArtPathMeta,
        albumArtPath.isAcceptableOrUnknown(
          data['album_art_path']!,
          _albumArtPathMeta,
        ),
      );
    }
    if (data.containsKey('file_size_bytes')) {
      context.handle(
        _fileSizeBytesMeta,
        fileSizeBytes.isAcceptableOrUnknown(
          data['file_size_bytes']!,
          _fileSizeBytesMeta,
        ),
      );
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    }
    if (data.containsKey('favorite')) {
      context.handle(
        _favoriteMeta,
        favorite.isAcceptableOrUnknown(data['favorite']!, _favoriteMeta),
      );
    }
    if (data.containsKey('last_played_at')) {
      context.handle(
        _lastPlayedAtMeta,
        lastPlayedAt.isAcceptableOrUnknown(
          data['last_played_at']!,
          _lastPlayedAtMeta,
        ),
      );
    }
    if (data.containsKey('play_count')) {
      context.handle(
        _playCountMeta,
        playCount.isAcceptableOrUnknown(data['play_count']!, _playCountMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Song map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Song(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      artist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist'],
      ),
      album: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album'],
      ),
      durationSeconds: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}duration_seconds'],
      ),
      trackNumber: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}track_number'],
      ),
      filePath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}file_path'],
      ),
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      ),
      albumArtPath: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album_art_path'],
      ),
      fileSizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}file_size_bytes'],
      ),
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      ),
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
      favorite: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}favorite'],
      )!,
      lastPlayedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_played_at'],
      ),
      playCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}play_count'],
      )!,
    );
  }

  @override
  $SongsTable createAlias(String alias) {
    return $SongsTable(attachedDatabase, alias);
  }
}

class Song extends DataClass implements Insertable<Song> {
  final int id;
  final String title;
  final String? artist;
  final String? album;
  final int? durationSeconds;
  final int? trackNumber;
  final String? filePath;
  final String? url;
  final String? albumArtPath;
  final int? fileSizeBytes;
  final String? mimeType;

  /// `localFile` | `url` (SongSource.name)
  final String source;
  final DateTime addedAt;

  /// Favorite songs (schema v3).
  final bool favorite;

  /// When the song last started playing; null if never (schema v3).
  final DateTime? lastPlayedAt;

  /// How many times the song started playing (schema v5; feeds "Top").
  final int playCount;
  const Song({
    required this.id,
    required this.title,
    this.artist,
    this.album,
    this.durationSeconds,
    this.trackNumber,
    this.filePath,
    this.url,
    this.albumArtPath,
    this.fileSizeBytes,
    this.mimeType,
    required this.source,
    required this.addedAt,
    required this.favorite,
    this.lastPlayedAt,
    required this.playCount,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['title'] = Variable<String>(title);
    if (!nullToAbsent || artist != null) {
      map['artist'] = Variable<String>(artist);
    }
    if (!nullToAbsent || album != null) {
      map['album'] = Variable<String>(album);
    }
    if (!nullToAbsent || durationSeconds != null) {
      map['duration_seconds'] = Variable<int>(durationSeconds);
    }
    if (!nullToAbsent || trackNumber != null) {
      map['track_number'] = Variable<int>(trackNumber);
    }
    if (!nullToAbsent || filePath != null) {
      map['file_path'] = Variable<String>(filePath);
    }
    if (!nullToAbsent || url != null) {
      map['url'] = Variable<String>(url);
    }
    if (!nullToAbsent || albumArtPath != null) {
      map['album_art_path'] = Variable<String>(albumArtPath);
    }
    if (!nullToAbsent || fileSizeBytes != null) {
      map['file_size_bytes'] = Variable<int>(fileSizeBytes);
    }
    if (!nullToAbsent || mimeType != null) {
      map['mime_type'] = Variable<String>(mimeType);
    }
    map['source'] = Variable<String>(source);
    map['added_at'] = Variable<DateTime>(addedAt);
    map['favorite'] = Variable<bool>(favorite);
    if (!nullToAbsent || lastPlayedAt != null) {
      map['last_played_at'] = Variable<DateTime>(lastPlayedAt);
    }
    map['play_count'] = Variable<int>(playCount);
    return map;
  }

  SongsCompanion toCompanion(bool nullToAbsent) {
    return SongsCompanion(
      id: Value(id),
      title: Value(title),
      artist: artist == null && nullToAbsent
          ? const Value.absent()
          : Value(artist),
      album: album == null && nullToAbsent
          ? const Value.absent()
          : Value(album),
      durationSeconds: durationSeconds == null && nullToAbsent
          ? const Value.absent()
          : Value(durationSeconds),
      trackNumber: trackNumber == null && nullToAbsent
          ? const Value.absent()
          : Value(trackNumber),
      filePath: filePath == null && nullToAbsent
          ? const Value.absent()
          : Value(filePath),
      url: url == null && nullToAbsent ? const Value.absent() : Value(url),
      albumArtPath: albumArtPath == null && nullToAbsent
          ? const Value.absent()
          : Value(albumArtPath),
      fileSizeBytes: fileSizeBytes == null && nullToAbsent
          ? const Value.absent()
          : Value(fileSizeBytes),
      mimeType: mimeType == null && nullToAbsent
          ? const Value.absent()
          : Value(mimeType),
      source: Value(source),
      addedAt: Value(addedAt),
      favorite: Value(favorite),
      lastPlayedAt: lastPlayedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastPlayedAt),
      playCount: Value(playCount),
    );
  }

  factory Song.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Song(
      id: serializer.fromJson<int>(json['id']),
      title: serializer.fromJson<String>(json['title']),
      artist: serializer.fromJson<String?>(json['artist']),
      album: serializer.fromJson<String?>(json['album']),
      durationSeconds: serializer.fromJson<int?>(json['durationSeconds']),
      trackNumber: serializer.fromJson<int?>(json['trackNumber']),
      filePath: serializer.fromJson<String?>(json['filePath']),
      url: serializer.fromJson<String?>(json['url']),
      albumArtPath: serializer.fromJson<String?>(json['albumArtPath']),
      fileSizeBytes: serializer.fromJson<int?>(json['fileSizeBytes']),
      mimeType: serializer.fromJson<String?>(json['mimeType']),
      source: serializer.fromJson<String>(json['source']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
      favorite: serializer.fromJson<bool>(json['favorite']),
      lastPlayedAt: serializer.fromJson<DateTime?>(json['lastPlayedAt']),
      playCount: serializer.fromJson<int>(json['playCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'title': serializer.toJson<String>(title),
      'artist': serializer.toJson<String?>(artist),
      'album': serializer.toJson<String?>(album),
      'durationSeconds': serializer.toJson<int?>(durationSeconds),
      'trackNumber': serializer.toJson<int?>(trackNumber),
      'filePath': serializer.toJson<String?>(filePath),
      'url': serializer.toJson<String?>(url),
      'albumArtPath': serializer.toJson<String?>(albumArtPath),
      'fileSizeBytes': serializer.toJson<int?>(fileSizeBytes),
      'mimeType': serializer.toJson<String?>(mimeType),
      'source': serializer.toJson<String>(source),
      'addedAt': serializer.toJson<DateTime>(addedAt),
      'favorite': serializer.toJson<bool>(favorite),
      'lastPlayedAt': serializer.toJson<DateTime?>(lastPlayedAt),
      'playCount': serializer.toJson<int>(playCount),
    };
  }

  Song copyWith({
    int? id,
    String? title,
    Value<String?> artist = const Value.absent(),
    Value<String?> album = const Value.absent(),
    Value<int?> durationSeconds = const Value.absent(),
    Value<int?> trackNumber = const Value.absent(),
    Value<String?> filePath = const Value.absent(),
    Value<String?> url = const Value.absent(),
    Value<String?> albumArtPath = const Value.absent(),
    Value<int?> fileSizeBytes = const Value.absent(),
    Value<String?> mimeType = const Value.absent(),
    String? source,
    DateTime? addedAt,
    bool? favorite,
    Value<DateTime?> lastPlayedAt = const Value.absent(),
    int? playCount,
  }) => Song(
    id: id ?? this.id,
    title: title ?? this.title,
    artist: artist.present ? artist.value : this.artist,
    album: album.present ? album.value : this.album,
    durationSeconds: durationSeconds.present
        ? durationSeconds.value
        : this.durationSeconds,
    trackNumber: trackNumber.present ? trackNumber.value : this.trackNumber,
    filePath: filePath.present ? filePath.value : this.filePath,
    url: url.present ? url.value : this.url,
    albumArtPath: albumArtPath.present ? albumArtPath.value : this.albumArtPath,
    fileSizeBytes: fileSizeBytes.present
        ? fileSizeBytes.value
        : this.fileSizeBytes,
    mimeType: mimeType.present ? mimeType.value : this.mimeType,
    source: source ?? this.source,
    addedAt: addedAt ?? this.addedAt,
    favorite: favorite ?? this.favorite,
    lastPlayedAt: lastPlayedAt.present ? lastPlayedAt.value : this.lastPlayedAt,
    playCount: playCount ?? this.playCount,
  );
  Song copyWithCompanion(SongsCompanion data) {
    return Song(
      id: data.id.present ? data.id.value : this.id,
      title: data.title.present ? data.title.value : this.title,
      artist: data.artist.present ? data.artist.value : this.artist,
      album: data.album.present ? data.album.value : this.album,
      durationSeconds: data.durationSeconds.present
          ? data.durationSeconds.value
          : this.durationSeconds,
      trackNumber: data.trackNumber.present
          ? data.trackNumber.value
          : this.trackNumber,
      filePath: data.filePath.present ? data.filePath.value : this.filePath,
      url: data.url.present ? data.url.value : this.url,
      albumArtPath: data.albumArtPath.present
          ? data.albumArtPath.value
          : this.albumArtPath,
      fileSizeBytes: data.fileSizeBytes.present
          ? data.fileSizeBytes.value
          : this.fileSizeBytes,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      source: data.source.present ? data.source.value : this.source,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      favorite: data.favorite.present ? data.favorite.value : this.favorite,
      lastPlayedAt: data.lastPlayedAt.present
          ? data.lastPlayedAt.value
          : this.lastPlayedAt,
      playCount: data.playCount.present ? data.playCount.value : this.playCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Song(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('trackNumber: $trackNumber, ')
          ..write('filePath: $filePath, ')
          ..write('url: $url, ')
          ..write('albumArtPath: $albumArtPath, ')
          ..write('fileSizeBytes: $fileSizeBytes, ')
          ..write('mimeType: $mimeType, ')
          ..write('source: $source, ')
          ..write('addedAt: $addedAt, ')
          ..write('favorite: $favorite, ')
          ..write('lastPlayedAt: $lastPlayedAt, ')
          ..write('playCount: $playCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    title,
    artist,
    album,
    durationSeconds,
    trackNumber,
    filePath,
    url,
    albumArtPath,
    fileSizeBytes,
    mimeType,
    source,
    addedAt,
    favorite,
    lastPlayedAt,
    playCount,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Song &&
          other.id == this.id &&
          other.title == this.title &&
          other.artist == this.artist &&
          other.album == this.album &&
          other.durationSeconds == this.durationSeconds &&
          other.trackNumber == this.trackNumber &&
          other.filePath == this.filePath &&
          other.url == this.url &&
          other.albumArtPath == this.albumArtPath &&
          other.fileSizeBytes == this.fileSizeBytes &&
          other.mimeType == this.mimeType &&
          other.source == this.source &&
          other.addedAt == this.addedAt &&
          other.favorite == this.favorite &&
          other.lastPlayedAt == this.lastPlayedAt &&
          other.playCount == this.playCount);
}

class SongsCompanion extends UpdateCompanion<Song> {
  final Value<int> id;
  final Value<String> title;
  final Value<String?> artist;
  final Value<String?> album;
  final Value<int?> durationSeconds;
  final Value<int?> trackNumber;
  final Value<String?> filePath;
  final Value<String?> url;
  final Value<String?> albumArtPath;
  final Value<int?> fileSizeBytes;
  final Value<String?> mimeType;
  final Value<String> source;
  final Value<DateTime> addedAt;
  final Value<bool> favorite;
  final Value<DateTime?> lastPlayedAt;
  final Value<int> playCount;
  const SongsCompanion({
    this.id = const Value.absent(),
    this.title = const Value.absent(),
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.trackNumber = const Value.absent(),
    this.filePath = const Value.absent(),
    this.url = const Value.absent(),
    this.albumArtPath = const Value.absent(),
    this.fileSizeBytes = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.source = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.favorite = const Value.absent(),
    this.lastPlayedAt = const Value.absent(),
    this.playCount = const Value.absent(),
  });
  SongsCompanion.insert({
    this.id = const Value.absent(),
    required String title,
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    this.durationSeconds = const Value.absent(),
    this.trackNumber = const Value.absent(),
    this.filePath = const Value.absent(),
    this.url = const Value.absent(),
    this.albumArtPath = const Value.absent(),
    this.fileSizeBytes = const Value.absent(),
    this.mimeType = const Value.absent(),
    required String source,
    this.addedAt = const Value.absent(),
    this.favorite = const Value.absent(),
    this.lastPlayedAt = const Value.absent(),
    this.playCount = const Value.absent(),
  }) : title = Value(title),
       source = Value(source);
  static Insertable<Song> custom({
    Expression<int>? id,
    Expression<String>? title,
    Expression<String>? artist,
    Expression<String>? album,
    Expression<int>? durationSeconds,
    Expression<int>? trackNumber,
    Expression<String>? filePath,
    Expression<String>? url,
    Expression<String>? albumArtPath,
    Expression<int>? fileSizeBytes,
    Expression<String>? mimeType,
    Expression<String>? source,
    Expression<DateTime>? addedAt,
    Expression<bool>? favorite,
    Expression<DateTime>? lastPlayedAt,
    Expression<int>? playCount,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (title != null) 'title': title,
      if (artist != null) 'artist': artist,
      if (album != null) 'album': album,
      if (durationSeconds != null) 'duration_seconds': durationSeconds,
      if (trackNumber != null) 'track_number': trackNumber,
      if (filePath != null) 'file_path': filePath,
      if (url != null) 'url': url,
      if (albumArtPath != null) 'album_art_path': albumArtPath,
      if (fileSizeBytes != null) 'file_size_bytes': fileSizeBytes,
      if (mimeType != null) 'mime_type': mimeType,
      if (source != null) 'source': source,
      if (addedAt != null) 'added_at': addedAt,
      if (favorite != null) 'favorite': favorite,
      if (lastPlayedAt != null) 'last_played_at': lastPlayedAt,
      if (playCount != null) 'play_count': playCount,
    });
  }

  SongsCompanion copyWith({
    Value<int>? id,
    Value<String>? title,
    Value<String?>? artist,
    Value<String?>? album,
    Value<int?>? durationSeconds,
    Value<int?>? trackNumber,
    Value<String?>? filePath,
    Value<String?>? url,
    Value<String?>? albumArtPath,
    Value<int?>? fileSizeBytes,
    Value<String?>? mimeType,
    Value<String>? source,
    Value<DateTime>? addedAt,
    Value<bool>? favorite,
    Value<DateTime?>? lastPlayedAt,
    Value<int>? playCount,
  }) {
    return SongsCompanion(
      id: id ?? this.id,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      trackNumber: trackNumber ?? this.trackNumber,
      filePath: filePath ?? this.filePath,
      url: url ?? this.url,
      albumArtPath: albumArtPath ?? this.albumArtPath,
      fileSizeBytes: fileSizeBytes ?? this.fileSizeBytes,
      mimeType: mimeType ?? this.mimeType,
      source: source ?? this.source,
      addedAt: addedAt ?? this.addedAt,
      favorite: favorite ?? this.favorite,
      lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
      playCount: playCount ?? this.playCount,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (album.present) {
      map['album'] = Variable<String>(album.value);
    }
    if (durationSeconds.present) {
      map['duration_seconds'] = Variable<int>(durationSeconds.value);
    }
    if (trackNumber.present) {
      map['track_number'] = Variable<int>(trackNumber.value);
    }
    if (filePath.present) {
      map['file_path'] = Variable<String>(filePath.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (albumArtPath.present) {
      map['album_art_path'] = Variable<String>(albumArtPath.value);
    }
    if (fileSizeBytes.present) {
      map['file_size_bytes'] = Variable<int>(fileSizeBytes.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (favorite.present) {
      map['favorite'] = Variable<bool>(favorite.value);
    }
    if (lastPlayedAt.present) {
      map['last_played_at'] = Variable<DateTime>(lastPlayedAt.value);
    }
    if (playCount.present) {
      map['play_count'] = Variable<int>(playCount.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SongsCompanion(')
          ..write('id: $id, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('durationSeconds: $durationSeconds, ')
          ..write('trackNumber: $trackNumber, ')
          ..write('filePath: $filePath, ')
          ..write('url: $url, ')
          ..write('albumArtPath: $albumArtPath, ')
          ..write('fileSizeBytes: $fileSizeBytes, ')
          ..write('mimeType: $mimeType, ')
          ..write('source: $source, ')
          ..write('addedAt: $addedAt, ')
          ..write('favorite: $favorite, ')
          ..write('lastPlayedAt: $lastPlayedAt, ')
          ..write('playCount: $playCount')
          ..write(')'))
        .toString();
  }
}

class $QueueItemsTable extends QueueItems
    with TableInfo<$QueueItemsTable, QueueItem> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QueueItemsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _songIdMeta = const VerificationMeta('songId');
  @override
  late final GeneratedColumn<int> songId = GeneratedColumn<int>(
    'song_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES songs (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _addedAtMeta = const VerificationMeta(
    'addedAt',
  );
  @override
  late final GeneratedColumn<DateTime> addedAt = GeneratedColumn<DateTime>(
    'added_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: DateTime.now,
  );
  static const VerificationMeta _addedByMeta = const VerificationMeta(
    'addedBy',
  );
  @override
  late final GeneratedColumn<String> addedBy = GeneratedColumn<String>(
    'added_by',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('player'),
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    songId,
    position,
    source,
    addedAt,
    addedBy,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'queue_items';
  @override
  VerificationContext validateIntegrity(
    Insertable<QueueItem> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('song_id')) {
      context.handle(
        _songIdMeta,
        songId.isAcceptableOrUnknown(data['song_id']!, _songIdMeta),
      );
    } else if (isInserting) {
      context.missing(_songIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    } else if (isInserting) {
      context.missing(_sourceMeta);
    }
    if (data.containsKey('added_at')) {
      context.handle(
        _addedAtMeta,
        addedAt.isAcceptableOrUnknown(data['added_at']!, _addedAtMeta),
      );
    }
    if (data.containsKey('added_by')) {
      context.handle(
        _addedByMeta,
        addedBy.isAcceptableOrUnknown(data['added_by']!, _addedByMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  QueueItem map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return QueueItem(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      songId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}song_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      addedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}added_at'],
      )!,
      addedBy: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}added_by'],
      )!,
    );
  }

  @override
  $QueueItemsTable createAlias(String alias) {
    return $QueueItemsTable(attachedDatabase, alias);
  }
}

class QueueItem extends DataClass implements Insertable<QueueItem> {
  final int id;
  final int songId;
  final int position;
  final String source;
  final DateTime addedAt;

  /// `player` | `controller`
  final String addedBy;
  const QueueItem({
    required this.id,
    required this.songId,
    required this.position,
    required this.source,
    required this.addedAt,
    required this.addedBy,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['song_id'] = Variable<int>(songId);
    map['position'] = Variable<int>(position);
    map['source'] = Variable<String>(source);
    map['added_at'] = Variable<DateTime>(addedAt);
    map['added_by'] = Variable<String>(addedBy);
    return map;
  }

  QueueItemsCompanion toCompanion(bool nullToAbsent) {
    return QueueItemsCompanion(
      id: Value(id),
      songId: Value(songId),
      position: Value(position),
      source: Value(source),
      addedAt: Value(addedAt),
      addedBy: Value(addedBy),
    );
  }

  factory QueueItem.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QueueItem(
      id: serializer.fromJson<int>(json['id']),
      songId: serializer.fromJson<int>(json['songId']),
      position: serializer.fromJson<int>(json['position']),
      source: serializer.fromJson<String>(json['source']),
      addedAt: serializer.fromJson<DateTime>(json['addedAt']),
      addedBy: serializer.fromJson<String>(json['addedBy']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'songId': serializer.toJson<int>(songId),
      'position': serializer.toJson<int>(position),
      'source': serializer.toJson<String>(source),
      'addedAt': serializer.toJson<DateTime>(addedAt),
      'addedBy': serializer.toJson<String>(addedBy),
    };
  }

  QueueItem copyWith({
    int? id,
    int? songId,
    int? position,
    String? source,
    DateTime? addedAt,
    String? addedBy,
  }) => QueueItem(
    id: id ?? this.id,
    songId: songId ?? this.songId,
    position: position ?? this.position,
    source: source ?? this.source,
    addedAt: addedAt ?? this.addedAt,
    addedBy: addedBy ?? this.addedBy,
  );
  QueueItem copyWithCompanion(QueueItemsCompanion data) {
    return QueueItem(
      id: data.id.present ? data.id.value : this.id,
      songId: data.songId.present ? data.songId.value : this.songId,
      position: data.position.present ? data.position.value : this.position,
      source: data.source.present ? data.source.value : this.source,
      addedAt: data.addedAt.present ? data.addedAt.value : this.addedAt,
      addedBy: data.addedBy.present ? data.addedBy.value : this.addedBy,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QueueItem(')
          ..write('id: $id, ')
          ..write('songId: $songId, ')
          ..write('position: $position, ')
          ..write('source: $source, ')
          ..write('addedAt: $addedAt, ')
          ..write('addedBy: $addedBy')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, songId, position, source, addedAt, addedBy);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QueueItem &&
          other.id == this.id &&
          other.songId == this.songId &&
          other.position == this.position &&
          other.source == this.source &&
          other.addedAt == this.addedAt &&
          other.addedBy == this.addedBy);
}

class QueueItemsCompanion extends UpdateCompanion<QueueItem> {
  final Value<int> id;
  final Value<int> songId;
  final Value<int> position;
  final Value<String> source;
  final Value<DateTime> addedAt;
  final Value<String> addedBy;
  const QueueItemsCompanion({
    this.id = const Value.absent(),
    this.songId = const Value.absent(),
    this.position = const Value.absent(),
    this.source = const Value.absent(),
    this.addedAt = const Value.absent(),
    this.addedBy = const Value.absent(),
  });
  QueueItemsCompanion.insert({
    this.id = const Value.absent(),
    required int songId,
    required int position,
    required String source,
    this.addedAt = const Value.absent(),
    this.addedBy = const Value.absent(),
  }) : songId = Value(songId),
       position = Value(position),
       source = Value(source);
  static Insertable<QueueItem> custom({
    Expression<int>? id,
    Expression<int>? songId,
    Expression<int>? position,
    Expression<String>? source,
    Expression<DateTime>? addedAt,
    Expression<String>? addedBy,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (songId != null) 'song_id': songId,
      if (position != null) 'position': position,
      if (source != null) 'source': source,
      if (addedAt != null) 'added_at': addedAt,
      if (addedBy != null) 'added_by': addedBy,
    });
  }

  QueueItemsCompanion copyWith({
    Value<int>? id,
    Value<int>? songId,
    Value<int>? position,
    Value<String>? source,
    Value<DateTime>? addedAt,
    Value<String>? addedBy,
  }) {
    return QueueItemsCompanion(
      id: id ?? this.id,
      songId: songId ?? this.songId,
      position: position ?? this.position,
      source: source ?? this.source,
      addedAt: addedAt ?? this.addedAt,
      addedBy: addedBy ?? this.addedBy,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (songId.present) {
      map['song_id'] = Variable<int>(songId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (addedAt.present) {
      map['added_at'] = Variable<DateTime>(addedAt.value);
    }
    if (addedBy.present) {
      map['added_by'] = Variable<String>(addedBy.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QueueItemsCompanion(')
          ..write('id: $id, ')
          ..write('songId: $songId, ')
          ..write('position: $position, ')
          ..write('source: $source, ')
          ..write('addedAt: $addedAt, ')
          ..write('addedBy: $addedBy')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings with TableInfo<$SettingsTable, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: DateTime.now,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value, updatedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Setting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class Setting extends DataClass implements Insertable<Setting> {
  final String key;
  final String value;
  final DateTime updatedAt;
  const Setting({
    required this.key,
    required this.value,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(
      key: Value(key),
      value: Value(value),
      updatedAt: Value(updatedAt),
    );
  }

  factory Setting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  Setting copyWith({String? key, String? value, DateTime? updatedAt}) =>
      Setting(
        key: key ?? this.key,
        value: value ?? this.value,
        updatedAt: updatedAt ?? this.updatedAt,
      );
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setting &&
          other.key == this.key &&
          other.value == this.value &&
          other.updatedAt == this.updatedAt);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<String> key;
  final Value<String> value;
  final Value<DateTime> updatedAt;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<Setting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<DateTime>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<DateTime>? updatedAt,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PairedControllersTable extends PairedControllers
    with TableInfo<$PairedControllersTable, PairedController> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PairedControllersTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _controllerNameMeta = const VerificationMeta(
    'controllerName',
  );
  @override
  late final GeneratedColumn<String> controllerName = GeneratedColumn<String>(
    'controller_name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _controllerAddressMeta = const VerificationMeta(
    'controllerAddress',
  );
  @override
  late final GeneratedColumn<String> controllerAddress =
      GeneratedColumn<String>(
        'controller_address',
        aliasedName,
        true,
        type: DriftSqlType.string,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _connectionTypeMeta = const VerificationMeta(
    'connectionType',
  );
  @override
  late final GeneratedColumn<String> connectionType = GeneratedColumn<String>(
    'connection_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pairedAtMeta = const VerificationMeta(
    'pairedAt',
  );
  @override
  late final GeneratedColumn<DateTime> pairedAt = GeneratedColumn<DateTime>(
    'paired_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: DateTime.now,
  );
  static const VerificationMeta _lastSeenAtMeta = const VerificationMeta(
    'lastSeenAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeenAt = GeneratedColumn<DateTime>(
    'last_seen_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: DateTime.now,
  );
  static const VerificationMeta _activeMeta = const VerificationMeta('active');
  @override
  late final GeneratedColumn<bool> active = GeneratedColumn<bool>(
    'active',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("active" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _tokenHashMeta = const VerificationMeta(
    'tokenHash',
  );
  @override
  late final GeneratedColumn<String> tokenHash = GeneratedColumn<String>(
    'token_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _trustedMeta = const VerificationMeta(
    'trusted',
  );
  @override
  late final GeneratedColumn<bool> trusted = GeneratedColumn<bool>(
    'trusted',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("trusted" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  @override
  List<GeneratedColumn> get $columns => [
    sessionId,
    controllerName,
    controllerAddress,
    connectionType,
    pairedAt,
    lastSeenAt,
    active,
    tokenHash,
    trusted,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'paired_controllers';
  @override
  VerificationContext validateIntegrity(
    Insertable<PairedController> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('controller_name')) {
      context.handle(
        _controllerNameMeta,
        controllerName.isAcceptableOrUnknown(
          data['controller_name']!,
          _controllerNameMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_controllerNameMeta);
    }
    if (data.containsKey('controller_address')) {
      context.handle(
        _controllerAddressMeta,
        controllerAddress.isAcceptableOrUnknown(
          data['controller_address']!,
          _controllerAddressMeta,
        ),
      );
    }
    if (data.containsKey('connection_type')) {
      context.handle(
        _connectionTypeMeta,
        connectionType.isAcceptableOrUnknown(
          data['connection_type']!,
          _connectionTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_connectionTypeMeta);
    }
    if (data.containsKey('paired_at')) {
      context.handle(
        _pairedAtMeta,
        pairedAt.isAcceptableOrUnknown(data['paired_at']!, _pairedAtMeta),
      );
    }
    if (data.containsKey('last_seen_at')) {
      context.handle(
        _lastSeenAtMeta,
        lastSeenAt.isAcceptableOrUnknown(
          data['last_seen_at']!,
          _lastSeenAtMeta,
        ),
      );
    }
    if (data.containsKey('active')) {
      context.handle(
        _activeMeta,
        active.isAcceptableOrUnknown(data['active']!, _activeMeta),
      );
    }
    if (data.containsKey('token_hash')) {
      context.handle(
        _tokenHashMeta,
        tokenHash.isAcceptableOrUnknown(data['token_hash']!, _tokenHashMeta),
      );
    }
    if (data.containsKey('trusted')) {
      context.handle(
        _trustedMeta,
        trusted.isAcceptableOrUnknown(data['trusted']!, _trustedMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {sessionId};
  @override
  PairedController map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PairedController(
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      controllerName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}controller_name'],
      )!,
      controllerAddress: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}controller_address'],
      ),
      connectionType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}connection_type'],
      )!,
      pairedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}paired_at'],
      )!,
      lastSeenAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen_at'],
      )!,
      active: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}active'],
      )!,
      tokenHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}token_hash'],
      ),
      trusted: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}trusted'],
      )!,
    );
  }

  @override
  $PairedControllersTable createAlias(String alias) {
    return $PairedControllersTable(attachedDatabase, alias);
  }
}

class PairedController extends DataClass
    implements Insertable<PairedController> {
  final String sessionId;
  final String controllerName;
  final String? controllerAddress;

  /// `local` | `online` (ConnectionType.name)
  final String connectionType;
  final DateTime pairedAt;
  final DateTime lastSeenAt;
  final bool active;

  /// SHA-256 of the session token, set when the Controller is trusted so it can
  /// reconnect later without pairing again. The token itself is never stored
  /// on the Player (docs/03_DATA_MODEL.md).
  final String? tokenHash;

  /// True while this Controller is a trusted device (until forgotten).
  final bool trusted;
  const PairedController({
    required this.sessionId,
    required this.controllerName,
    this.controllerAddress,
    required this.connectionType,
    required this.pairedAt,
    required this.lastSeenAt,
    required this.active,
    this.tokenHash,
    required this.trusted,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['session_id'] = Variable<String>(sessionId);
    map['controller_name'] = Variable<String>(controllerName);
    if (!nullToAbsent || controllerAddress != null) {
      map['controller_address'] = Variable<String>(controllerAddress);
    }
    map['connection_type'] = Variable<String>(connectionType);
    map['paired_at'] = Variable<DateTime>(pairedAt);
    map['last_seen_at'] = Variable<DateTime>(lastSeenAt);
    map['active'] = Variable<bool>(active);
    if (!nullToAbsent || tokenHash != null) {
      map['token_hash'] = Variable<String>(tokenHash);
    }
    map['trusted'] = Variable<bool>(trusted);
    return map;
  }

  PairedControllersCompanion toCompanion(bool nullToAbsent) {
    return PairedControllersCompanion(
      sessionId: Value(sessionId),
      controllerName: Value(controllerName),
      controllerAddress: controllerAddress == null && nullToAbsent
          ? const Value.absent()
          : Value(controllerAddress),
      connectionType: Value(connectionType),
      pairedAt: Value(pairedAt),
      lastSeenAt: Value(lastSeenAt),
      active: Value(active),
      tokenHash: tokenHash == null && nullToAbsent
          ? const Value.absent()
          : Value(tokenHash),
      trusted: Value(trusted),
    );
  }

  factory PairedController.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PairedController(
      sessionId: serializer.fromJson<String>(json['sessionId']),
      controllerName: serializer.fromJson<String>(json['controllerName']),
      controllerAddress: serializer.fromJson<String?>(
        json['controllerAddress'],
      ),
      connectionType: serializer.fromJson<String>(json['connectionType']),
      pairedAt: serializer.fromJson<DateTime>(json['pairedAt']),
      lastSeenAt: serializer.fromJson<DateTime>(json['lastSeenAt']),
      active: serializer.fromJson<bool>(json['active']),
      tokenHash: serializer.fromJson<String?>(json['tokenHash']),
      trusted: serializer.fromJson<bool>(json['trusted']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'sessionId': serializer.toJson<String>(sessionId),
      'controllerName': serializer.toJson<String>(controllerName),
      'controllerAddress': serializer.toJson<String?>(controllerAddress),
      'connectionType': serializer.toJson<String>(connectionType),
      'pairedAt': serializer.toJson<DateTime>(pairedAt),
      'lastSeenAt': serializer.toJson<DateTime>(lastSeenAt),
      'active': serializer.toJson<bool>(active),
      'tokenHash': serializer.toJson<String?>(tokenHash),
      'trusted': serializer.toJson<bool>(trusted),
    };
  }

  PairedController copyWith({
    String? sessionId,
    String? controllerName,
    Value<String?> controllerAddress = const Value.absent(),
    String? connectionType,
    DateTime? pairedAt,
    DateTime? lastSeenAt,
    bool? active,
    Value<String?> tokenHash = const Value.absent(),
    bool? trusted,
  }) => PairedController(
    sessionId: sessionId ?? this.sessionId,
    controllerName: controllerName ?? this.controllerName,
    controllerAddress: controllerAddress.present
        ? controllerAddress.value
        : this.controllerAddress,
    connectionType: connectionType ?? this.connectionType,
    pairedAt: pairedAt ?? this.pairedAt,
    lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    active: active ?? this.active,
    tokenHash: tokenHash.present ? tokenHash.value : this.tokenHash,
    trusted: trusted ?? this.trusted,
  );
  PairedController copyWithCompanion(PairedControllersCompanion data) {
    return PairedController(
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      controllerName: data.controllerName.present
          ? data.controllerName.value
          : this.controllerName,
      controllerAddress: data.controllerAddress.present
          ? data.controllerAddress.value
          : this.controllerAddress,
      connectionType: data.connectionType.present
          ? data.connectionType.value
          : this.connectionType,
      pairedAt: data.pairedAt.present ? data.pairedAt.value : this.pairedAt,
      lastSeenAt: data.lastSeenAt.present
          ? data.lastSeenAt.value
          : this.lastSeenAt,
      active: data.active.present ? data.active.value : this.active,
      tokenHash: data.tokenHash.present ? data.tokenHash.value : this.tokenHash,
      trusted: data.trusted.present ? data.trusted.value : this.trusted,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PairedController(')
          ..write('sessionId: $sessionId, ')
          ..write('controllerName: $controllerName, ')
          ..write('controllerAddress: $controllerAddress, ')
          ..write('connectionType: $connectionType, ')
          ..write('pairedAt: $pairedAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('active: $active, ')
          ..write('tokenHash: $tokenHash, ')
          ..write('trusted: $trusted')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    sessionId,
    controllerName,
    controllerAddress,
    connectionType,
    pairedAt,
    lastSeenAt,
    active,
    tokenHash,
    trusted,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PairedController &&
          other.sessionId == this.sessionId &&
          other.controllerName == this.controllerName &&
          other.controllerAddress == this.controllerAddress &&
          other.connectionType == this.connectionType &&
          other.pairedAt == this.pairedAt &&
          other.lastSeenAt == this.lastSeenAt &&
          other.active == this.active &&
          other.tokenHash == this.tokenHash &&
          other.trusted == this.trusted);
}

class PairedControllersCompanion extends UpdateCompanion<PairedController> {
  final Value<String> sessionId;
  final Value<String> controllerName;
  final Value<String?> controllerAddress;
  final Value<String> connectionType;
  final Value<DateTime> pairedAt;
  final Value<DateTime> lastSeenAt;
  final Value<bool> active;
  final Value<String?> tokenHash;
  final Value<bool> trusted;
  final Value<int> rowid;
  const PairedControllersCompanion({
    this.sessionId = const Value.absent(),
    this.controllerName = const Value.absent(),
    this.controllerAddress = const Value.absent(),
    this.connectionType = const Value.absent(),
    this.pairedAt = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.active = const Value.absent(),
    this.tokenHash = const Value.absent(),
    this.trusted = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PairedControllersCompanion.insert({
    required String sessionId,
    required String controllerName,
    this.controllerAddress = const Value.absent(),
    required String connectionType,
    this.pairedAt = const Value.absent(),
    this.lastSeenAt = const Value.absent(),
    this.active = const Value.absent(),
    this.tokenHash = const Value.absent(),
    this.trusted = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : sessionId = Value(sessionId),
       controllerName = Value(controllerName),
       connectionType = Value(connectionType);
  static Insertable<PairedController> custom({
    Expression<String>? sessionId,
    Expression<String>? controllerName,
    Expression<String>? controllerAddress,
    Expression<String>? connectionType,
    Expression<DateTime>? pairedAt,
    Expression<DateTime>? lastSeenAt,
    Expression<bool>? active,
    Expression<String>? tokenHash,
    Expression<bool>? trusted,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (sessionId != null) 'session_id': sessionId,
      if (controllerName != null) 'controller_name': controllerName,
      if (controllerAddress != null) 'controller_address': controllerAddress,
      if (connectionType != null) 'connection_type': connectionType,
      if (pairedAt != null) 'paired_at': pairedAt,
      if (lastSeenAt != null) 'last_seen_at': lastSeenAt,
      if (active != null) 'active': active,
      if (tokenHash != null) 'token_hash': tokenHash,
      if (trusted != null) 'trusted': trusted,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PairedControllersCompanion copyWith({
    Value<String>? sessionId,
    Value<String>? controllerName,
    Value<String?>? controllerAddress,
    Value<String>? connectionType,
    Value<DateTime>? pairedAt,
    Value<DateTime>? lastSeenAt,
    Value<bool>? active,
    Value<String?>? tokenHash,
    Value<bool>? trusted,
    Value<int>? rowid,
  }) {
    return PairedControllersCompanion(
      sessionId: sessionId ?? this.sessionId,
      controllerName: controllerName ?? this.controllerName,
      controllerAddress: controllerAddress ?? this.controllerAddress,
      connectionType: connectionType ?? this.connectionType,
      pairedAt: pairedAt ?? this.pairedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      active: active ?? this.active,
      tokenHash: tokenHash ?? this.tokenHash,
      trusted: trusted ?? this.trusted,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (controllerName.present) {
      map['controller_name'] = Variable<String>(controllerName.value);
    }
    if (controllerAddress.present) {
      map['controller_address'] = Variable<String>(controllerAddress.value);
    }
    if (connectionType.present) {
      map['connection_type'] = Variable<String>(connectionType.value);
    }
    if (pairedAt.present) {
      map['paired_at'] = Variable<DateTime>(pairedAt.value);
    }
    if (lastSeenAt.present) {
      map['last_seen_at'] = Variable<DateTime>(lastSeenAt.value);
    }
    if (active.present) {
      map['active'] = Variable<bool>(active.value);
    }
    if (tokenHash.present) {
      map['token_hash'] = Variable<String>(tokenHash.value);
    }
    if (trusted.present) {
      map['trusted'] = Variable<bool>(trusted.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PairedControllersCompanion(')
          ..write('sessionId: $sessionId, ')
          ..write('controllerName: $controllerName, ')
          ..write('controllerAddress: $controllerAddress, ')
          ..write('connectionType: $connectionType, ')
          ..write('pairedAt: $pairedAt, ')
          ..write('lastSeenAt: $lastSeenAt, ')
          ..write('active: $active, ')
          ..write('tokenHash: $tokenHash, ')
          ..write('trusted: $trusted, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $RecentUrlsTable extends RecentUrls
    with TableInfo<$RecentUrlsTable, RecentUrl> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RecentUrlsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastUsedAtMeta = const VerificationMeta(
    'lastUsedAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastUsedAt = GeneratedColumn<DateTime>(
    'last_used_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: DateTime.now,
  );
  @override
  List<GeneratedColumn> get $columns => [id, url, title, lastUsedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'recent_urls';
  @override
  VerificationContext validateIntegrity(
    Insertable<RecentUrl> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    }
    if (data.containsKey('last_used_at')) {
      context.handle(
        _lastUsedAtMeta,
        lastUsedAt.isAcceptableOrUnknown(
          data['last_used_at']!,
          _lastUsedAtMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RecentUrl map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RecentUrl(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      ),
      lastUsedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_used_at'],
      )!,
    );
  }

  @override
  $RecentUrlsTable createAlias(String alias) {
    return $RecentUrlsTable(attachedDatabase, alias);
  }
}

class RecentUrl extends DataClass implements Insertable<RecentUrl> {
  final int id;
  final String url;
  final String? title;
  final DateTime lastUsedAt;
  const RecentUrl({
    required this.id,
    required this.url,
    this.title,
    required this.lastUsedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['url'] = Variable<String>(url);
    if (!nullToAbsent || title != null) {
      map['title'] = Variable<String>(title);
    }
    map['last_used_at'] = Variable<DateTime>(lastUsedAt);
    return map;
  }

  RecentUrlsCompanion toCompanion(bool nullToAbsent) {
    return RecentUrlsCompanion(
      id: Value(id),
      url: Value(url),
      title: title == null && nullToAbsent
          ? const Value.absent()
          : Value(title),
      lastUsedAt: Value(lastUsedAt),
    );
  }

  factory RecentUrl.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RecentUrl(
      id: serializer.fromJson<int>(json['id']),
      url: serializer.fromJson<String>(json['url']),
      title: serializer.fromJson<String?>(json['title']),
      lastUsedAt: serializer.fromJson<DateTime>(json['lastUsedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'url': serializer.toJson<String>(url),
      'title': serializer.toJson<String?>(title),
      'lastUsedAt': serializer.toJson<DateTime>(lastUsedAt),
    };
  }

  RecentUrl copyWith({
    int? id,
    String? url,
    Value<String?> title = const Value.absent(),
    DateTime? lastUsedAt,
  }) => RecentUrl(
    id: id ?? this.id,
    url: url ?? this.url,
    title: title.present ? title.value : this.title,
    lastUsedAt: lastUsedAt ?? this.lastUsedAt,
  );
  RecentUrl copyWithCompanion(RecentUrlsCompanion data) {
    return RecentUrl(
      id: data.id.present ? data.id.value : this.id,
      url: data.url.present ? data.url.value : this.url,
      title: data.title.present ? data.title.value : this.title,
      lastUsedAt: data.lastUsedAt.present
          ? data.lastUsedAt.value
          : this.lastUsedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RecentUrl(')
          ..write('id: $id, ')
          ..write('url: $url, ')
          ..write('title: $title, ')
          ..write('lastUsedAt: $lastUsedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, url, title, lastUsedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RecentUrl &&
          other.id == this.id &&
          other.url == this.url &&
          other.title == this.title &&
          other.lastUsedAt == this.lastUsedAt);
}

class RecentUrlsCompanion extends UpdateCompanion<RecentUrl> {
  final Value<int> id;
  final Value<String> url;
  final Value<String?> title;
  final Value<DateTime> lastUsedAt;
  const RecentUrlsCompanion({
    this.id = const Value.absent(),
    this.url = const Value.absent(),
    this.title = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
  });
  RecentUrlsCompanion.insert({
    this.id = const Value.absent(),
    required String url,
    this.title = const Value.absent(),
    this.lastUsedAt = const Value.absent(),
  }) : url = Value(url);
  static Insertable<RecentUrl> custom({
    Expression<int>? id,
    Expression<String>? url,
    Expression<String>? title,
    Expression<DateTime>? lastUsedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (url != null) 'url': url,
      if (title != null) 'title': title,
      if (lastUsedAt != null) 'last_used_at': lastUsedAt,
    });
  }

  RecentUrlsCompanion copyWith({
    Value<int>? id,
    Value<String>? url,
    Value<String?>? title,
    Value<DateTime>? lastUsedAt,
  }) {
    return RecentUrlsCompanion(
      id: id ?? this.id,
      url: url ?? this.url,
      title: title ?? this.title,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (lastUsedAt.present) {
      map['last_used_at'] = Variable<DateTime>(lastUsedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RecentUrlsCompanion(')
          ..write('id: $id, ')
          ..write('url: $url, ')
          ..write('title: $title, ')
          ..write('lastUsedAt: $lastUsedAt')
          ..write(')'))
        .toString();
  }
}

class $PlaylistsTable extends Playlists
    with TableInfo<$PlaylistsTable, Playlist> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: DateTime.now,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlists';
  @override
  VerificationContext validateIntegrity(
    Insertable<Playlist> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Playlist map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Playlist(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $PlaylistsTable createAlias(String alias) {
    return $PlaylistsTable(attachedDatabase, alias);
  }
}

class Playlist extends DataClass implements Insertable<Playlist> {
  final int id;
  final String name;
  final DateTime createdAt;
  const Playlist({
    required this.id,
    required this.name,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['name'] = Variable<String>(name);
    map['created_at'] = Variable<DateTime>(createdAt);
    return map;
  }

  PlaylistsCompanion toCompanion(bool nullToAbsent) {
    return PlaylistsCompanion(
      id: Value(id),
      name: Value(name),
      createdAt: Value(createdAt),
    );
  }

  factory Playlist.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Playlist(
      id: serializer.fromJson<int>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'name': serializer.toJson<String>(name),
      'createdAt': serializer.toJson<DateTime>(createdAt),
    };
  }

  Playlist copyWith({int? id, String? name, DateTime? createdAt}) => Playlist(
    id: id ?? this.id,
    name: name ?? this.name,
    createdAt: createdAt ?? this.createdAt,
  );
  Playlist copyWithCompanion(PlaylistsCompanion data) {
    return Playlist(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Playlist(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Playlist &&
          other.id == this.id &&
          other.name == this.name &&
          other.createdAt == this.createdAt);
}

class PlaylistsCompanion extends UpdateCompanion<Playlist> {
  final Value<int> id;
  final Value<String> name;
  final Value<DateTime> createdAt;
  const PlaylistsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  PlaylistsCompanion.insert({
    this.id = const Value.absent(),
    required String name,
    this.createdAt = const Value.absent(),
  }) : name = Value(name);
  static Insertable<Playlist> custom({
    Expression<int>? id,
    Expression<String>? name,
    Expression<DateTime>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  PlaylistsCompanion copyWith({
    Value<int>? id,
    Value<String>? name,
    Value<DateTime>? createdAt,
  }) {
    return PlaylistsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

class $PlaylistSongsTable extends PlaylistSongs
    with TableInfo<$PlaylistSongsTable, PlaylistSong> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PlaylistSongsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _playlistIdMeta = const VerificationMeta(
    'playlistId',
  );
  @override
  late final GeneratedColumn<int> playlistId = GeneratedColumn<int>(
    'playlist_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES playlists (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _songIdMeta = const VerificationMeta('songId');
  @override
  late final GeneratedColumn<int> songId = GeneratedColumn<int>(
    'song_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES songs (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, playlistId, songId, position];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'playlist_songs';
  @override
  VerificationContext validateIntegrity(
    Insertable<PlaylistSong> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('playlist_id')) {
      context.handle(
        _playlistIdMeta,
        playlistId.isAcceptableOrUnknown(data['playlist_id']!, _playlistIdMeta),
      );
    } else if (isInserting) {
      context.missing(_playlistIdMeta);
    }
    if (data.containsKey('song_id')) {
      context.handle(
        _songIdMeta,
        songId.isAcceptableOrUnknown(data['song_id']!, _songIdMeta),
      );
    } else if (isInserting) {
      context.missing(_songIdMeta);
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PlaylistSong map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PlaylistSong(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      playlistId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}playlist_id'],
      )!,
      songId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}song_id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
    );
  }

  @override
  $PlaylistSongsTable createAlias(String alias) {
    return $PlaylistSongsTable(attachedDatabase, alias);
  }
}

class PlaylistSong extends DataClass implements Insertable<PlaylistSong> {
  final int id;
  final int playlistId;
  final int songId;
  final int position;
  const PlaylistSong({
    required this.id,
    required this.playlistId,
    required this.songId,
    required this.position,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['playlist_id'] = Variable<int>(playlistId);
    map['song_id'] = Variable<int>(songId);
    map['position'] = Variable<int>(position);
    return map;
  }

  PlaylistSongsCompanion toCompanion(bool nullToAbsent) {
    return PlaylistSongsCompanion(
      id: Value(id),
      playlistId: Value(playlistId),
      songId: Value(songId),
      position: Value(position),
    );
  }

  factory PlaylistSong.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PlaylistSong(
      id: serializer.fromJson<int>(json['id']),
      playlistId: serializer.fromJson<int>(json['playlistId']),
      songId: serializer.fromJson<int>(json['songId']),
      position: serializer.fromJson<int>(json['position']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'playlistId': serializer.toJson<int>(playlistId),
      'songId': serializer.toJson<int>(songId),
      'position': serializer.toJson<int>(position),
    };
  }

  PlaylistSong copyWith({
    int? id,
    int? playlistId,
    int? songId,
    int? position,
  }) => PlaylistSong(
    id: id ?? this.id,
    playlistId: playlistId ?? this.playlistId,
    songId: songId ?? this.songId,
    position: position ?? this.position,
  );
  PlaylistSong copyWithCompanion(PlaylistSongsCompanion data) {
    return PlaylistSong(
      id: data.id.present ? data.id.value : this.id,
      playlistId: data.playlistId.present
          ? data.playlistId.value
          : this.playlistId,
      songId: data.songId.present ? data.songId.value : this.songId,
      position: data.position.present ? data.position.value : this.position,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistSong(')
          ..write('id: $id, ')
          ..write('playlistId: $playlistId, ')
          ..write('songId: $songId, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, playlistId, songId, position);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PlaylistSong &&
          other.id == this.id &&
          other.playlistId == this.playlistId &&
          other.songId == this.songId &&
          other.position == this.position);
}

class PlaylistSongsCompanion extends UpdateCompanion<PlaylistSong> {
  final Value<int> id;
  final Value<int> playlistId;
  final Value<int> songId;
  final Value<int> position;
  const PlaylistSongsCompanion({
    this.id = const Value.absent(),
    this.playlistId = const Value.absent(),
    this.songId = const Value.absent(),
    this.position = const Value.absent(),
  });
  PlaylistSongsCompanion.insert({
    this.id = const Value.absent(),
    required int playlistId,
    required int songId,
    required int position,
  }) : playlistId = Value(playlistId),
       songId = Value(songId),
       position = Value(position);
  static Insertable<PlaylistSong> custom({
    Expression<int>? id,
    Expression<int>? playlistId,
    Expression<int>? songId,
    Expression<int>? position,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (playlistId != null) 'playlist_id': playlistId,
      if (songId != null) 'song_id': songId,
      if (position != null) 'position': position,
    });
  }

  PlaylistSongsCompanion copyWith({
    Value<int>? id,
    Value<int>? playlistId,
    Value<int>? songId,
    Value<int>? position,
  }) {
    return PlaylistSongsCompanion(
      id: id ?? this.id,
      playlistId: playlistId ?? this.playlistId,
      songId: songId ?? this.songId,
      position: position ?? this.position,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (playlistId.present) {
      map['playlist_id'] = Variable<int>(playlistId.value);
    }
    if (songId.present) {
      map['song_id'] = Variable<int>(songId.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PlaylistSongsCompanion(')
          ..write('id: $id, ')
          ..write('playlistId: $playlistId, ')
          ..write('songId: $songId, ')
          ..write('position: $position')
          ..write(')'))
        .toString();
  }
}

class $QueueStreamsTable extends QueueStreams
    with TableInfo<$QueueStreamsTable, QueueStream> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $QueueStreamsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _positionMeta = const VerificationMeta(
    'position',
  );
  @override
  late final GeneratedColumn<int> position = GeneratedColumn<int>(
    'position',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
    'artist',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _albumMeta = const VerificationMeta('album');
  @override
  late final GeneratedColumn<String> album = GeneratedColumn<String>(
    'album',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _licenseUrlMeta = const VerificationMeta(
    'licenseUrl',
  );
  @override
  late final GeneratedColumn<String> licenseUrl = GeneratedColumn<String>(
    'license_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _imageUrlMeta = const VerificationMeta(
    'imageUrl',
  );
  @override
  late final GeneratedColumn<String> imageUrl = GeneratedColumn<String>(
    'image_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    position,
    url,
    title,
    artist,
    album,
    licenseUrl,
    imageUrl,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'queue_streams';
  @override
  VerificationContext validateIntegrity(
    Insertable<QueueStream> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('position')) {
      context.handle(
        _positionMeta,
        position.isAcceptableOrUnknown(data['position']!, _positionMeta),
      );
    } else if (isInserting) {
      context.missing(_positionMeta);
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('artist')) {
      context.handle(
        _artistMeta,
        artist.isAcceptableOrUnknown(data['artist']!, _artistMeta),
      );
    } else if (isInserting) {
      context.missing(_artistMeta);
    }
    if (data.containsKey('album')) {
      context.handle(
        _albumMeta,
        album.isAcceptableOrUnknown(data['album']!, _albumMeta),
      );
    } else if (isInserting) {
      context.missing(_albumMeta);
    }
    if (data.containsKey('license_url')) {
      context.handle(
        _licenseUrlMeta,
        licenseUrl.isAcceptableOrUnknown(data['license_url']!, _licenseUrlMeta),
      );
    }
    if (data.containsKey('image_url')) {
      context.handle(
        _imageUrlMeta,
        imageUrl.isAcceptableOrUnknown(data['image_url']!, _imageUrlMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  QueueStream map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return QueueStream(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      position: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}position'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      artist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist'],
      )!,
      album: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album'],
      )!,
      licenseUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}license_url'],
      ),
      imageUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_url'],
      ),
    );
  }

  @override
  $QueueStreamsTable createAlias(String alias) {
    return $QueueStreamsTable(attachedDatabase, alias);
  }
}

class QueueStream extends DataClass implements Insertable<QueueStream> {
  final int id;
  final int position;
  final String url;
  final String title;
  final String artist;
  final String album;
  final String? licenseUrl;
  final String? imageUrl;
  const QueueStream({
    required this.id,
    required this.position,
    required this.url,
    required this.title,
    required this.artist,
    required this.album,
    this.licenseUrl,
    this.imageUrl,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['position'] = Variable<int>(position);
    map['url'] = Variable<String>(url);
    map['title'] = Variable<String>(title);
    map['artist'] = Variable<String>(artist);
    map['album'] = Variable<String>(album);
    if (!nullToAbsent || licenseUrl != null) {
      map['license_url'] = Variable<String>(licenseUrl);
    }
    if (!nullToAbsent || imageUrl != null) {
      map['image_url'] = Variable<String>(imageUrl);
    }
    return map;
  }

  QueueStreamsCompanion toCompanion(bool nullToAbsent) {
    return QueueStreamsCompanion(
      id: Value(id),
      position: Value(position),
      url: Value(url),
      title: Value(title),
      artist: Value(artist),
      album: Value(album),
      licenseUrl: licenseUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(licenseUrl),
      imageUrl: imageUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(imageUrl),
    );
  }

  factory QueueStream.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return QueueStream(
      id: serializer.fromJson<int>(json['id']),
      position: serializer.fromJson<int>(json['position']),
      url: serializer.fromJson<String>(json['url']),
      title: serializer.fromJson<String>(json['title']),
      artist: serializer.fromJson<String>(json['artist']),
      album: serializer.fromJson<String>(json['album']),
      licenseUrl: serializer.fromJson<String?>(json['licenseUrl']),
      imageUrl: serializer.fromJson<String?>(json['imageUrl']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'position': serializer.toJson<int>(position),
      'url': serializer.toJson<String>(url),
      'title': serializer.toJson<String>(title),
      'artist': serializer.toJson<String>(artist),
      'album': serializer.toJson<String>(album),
      'licenseUrl': serializer.toJson<String?>(licenseUrl),
      'imageUrl': serializer.toJson<String?>(imageUrl),
    };
  }

  QueueStream copyWith({
    int? id,
    int? position,
    String? url,
    String? title,
    String? artist,
    String? album,
    Value<String?> licenseUrl = const Value.absent(),
    Value<String?> imageUrl = const Value.absent(),
  }) => QueueStream(
    id: id ?? this.id,
    position: position ?? this.position,
    url: url ?? this.url,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    album: album ?? this.album,
    licenseUrl: licenseUrl.present ? licenseUrl.value : this.licenseUrl,
    imageUrl: imageUrl.present ? imageUrl.value : this.imageUrl,
  );
  QueueStream copyWithCompanion(QueueStreamsCompanion data) {
    return QueueStream(
      id: data.id.present ? data.id.value : this.id,
      position: data.position.present ? data.position.value : this.position,
      url: data.url.present ? data.url.value : this.url,
      title: data.title.present ? data.title.value : this.title,
      artist: data.artist.present ? data.artist.value : this.artist,
      album: data.album.present ? data.album.value : this.album,
      licenseUrl: data.licenseUrl.present
          ? data.licenseUrl.value
          : this.licenseUrl,
      imageUrl: data.imageUrl.present ? data.imageUrl.value : this.imageUrl,
    );
  }

  @override
  String toString() {
    return (StringBuffer('QueueStream(')
          ..write('id: $id, ')
          ..write('position: $position, ')
          ..write('url: $url, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('licenseUrl: $licenseUrl, ')
          ..write('imageUrl: $imageUrl')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    position,
    url,
    title,
    artist,
    album,
    licenseUrl,
    imageUrl,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is QueueStream &&
          other.id == this.id &&
          other.position == this.position &&
          other.url == this.url &&
          other.title == this.title &&
          other.artist == this.artist &&
          other.album == this.album &&
          other.licenseUrl == this.licenseUrl &&
          other.imageUrl == this.imageUrl);
}

class QueueStreamsCompanion extends UpdateCompanion<QueueStream> {
  final Value<int> id;
  final Value<int> position;
  final Value<String> url;
  final Value<String> title;
  final Value<String> artist;
  final Value<String> album;
  final Value<String?> licenseUrl;
  final Value<String?> imageUrl;
  const QueueStreamsCompanion({
    this.id = const Value.absent(),
    this.position = const Value.absent(),
    this.url = const Value.absent(),
    this.title = const Value.absent(),
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    this.licenseUrl = const Value.absent(),
    this.imageUrl = const Value.absent(),
  });
  QueueStreamsCompanion.insert({
    this.id = const Value.absent(),
    required int position,
    required String url,
    required String title,
    required String artist,
    required String album,
    this.licenseUrl = const Value.absent(),
    this.imageUrl = const Value.absent(),
  }) : position = Value(position),
       url = Value(url),
       title = Value(title),
       artist = Value(artist),
       album = Value(album);
  static Insertable<QueueStream> custom({
    Expression<int>? id,
    Expression<int>? position,
    Expression<String>? url,
    Expression<String>? title,
    Expression<String>? artist,
    Expression<String>? album,
    Expression<String>? licenseUrl,
    Expression<String>? imageUrl,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (position != null) 'position': position,
      if (url != null) 'url': url,
      if (title != null) 'title': title,
      if (artist != null) 'artist': artist,
      if (album != null) 'album': album,
      if (licenseUrl != null) 'license_url': licenseUrl,
      if (imageUrl != null) 'image_url': imageUrl,
    });
  }

  QueueStreamsCompanion copyWith({
    Value<int>? id,
    Value<int>? position,
    Value<String>? url,
    Value<String>? title,
    Value<String>? artist,
    Value<String>? album,
    Value<String?>? licenseUrl,
    Value<String?>? imageUrl,
  }) {
    return QueueStreamsCompanion(
      id: id ?? this.id,
      position: position ?? this.position,
      url: url ?? this.url,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      licenseUrl: licenseUrl ?? this.licenseUrl,
      imageUrl: imageUrl ?? this.imageUrl,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (position.present) {
      map['position'] = Variable<int>(position.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (album.present) {
      map['album'] = Variable<String>(album.value);
    }
    if (licenseUrl.present) {
      map['license_url'] = Variable<String>(licenseUrl.value);
    }
    if (imageUrl.present) {
      map['image_url'] = Variable<String>(imageUrl.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('QueueStreamsCompanion(')
          ..write('id: $id, ')
          ..write('position: $position, ')
          ..write('url: $url, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('licenseUrl: $licenseUrl, ')
          ..write('imageUrl: $imageUrl')
          ..write(')'))
        .toString();
  }
}

class $OnlineHistoryTable extends OnlineHistory
    with TableInfo<$OnlineHistoryTable, OnlineHistoryData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $OnlineHistoryTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _urlMeta = const VerificationMeta('url');
  @override
  late final GeneratedColumn<String> url = GeneratedColumn<String>(
    'url',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _artistMeta = const VerificationMeta('artist');
  @override
  late final GeneratedColumn<String> artist = GeneratedColumn<String>(
    'artist',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _albumMeta = const VerificationMeta('album');
  @override
  late final GeneratedColumn<String> album = GeneratedColumn<String>(
    'album',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _licenseUrlMeta = const VerificationMeta(
    'licenseUrl',
  );
  @override
  late final GeneratedColumn<String> licenseUrl = GeneratedColumn<String>(
    'license_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _imageUrlMeta = const VerificationMeta(
    'imageUrl',
  );
  @override
  late final GeneratedColumn<String> imageUrl = GeneratedColumn<String>(
    'image_url',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _playedAtMeta = const VerificationMeta(
    'playedAt',
  );
  @override
  late final GeneratedColumn<DateTime> playedAt = GeneratedColumn<DateTime>(
    'played_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
    clientDefault: DateTime.now,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    url,
    title,
    artist,
    album,
    licenseUrl,
    imageUrl,
    playedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'online_history';
  @override
  VerificationContext validateIntegrity(
    Insertable<OnlineHistoryData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('url')) {
      context.handle(
        _urlMeta,
        url.isAcceptableOrUnknown(data['url']!, _urlMeta),
      );
    } else if (isInserting) {
      context.missing(_urlMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    if (data.containsKey('artist')) {
      context.handle(
        _artistMeta,
        artist.isAcceptableOrUnknown(data['artist']!, _artistMeta),
      );
    } else if (isInserting) {
      context.missing(_artistMeta);
    }
    if (data.containsKey('album')) {
      context.handle(
        _albumMeta,
        album.isAcceptableOrUnknown(data['album']!, _albumMeta),
      );
    } else if (isInserting) {
      context.missing(_albumMeta);
    }
    if (data.containsKey('license_url')) {
      context.handle(
        _licenseUrlMeta,
        licenseUrl.isAcceptableOrUnknown(data['license_url']!, _licenseUrlMeta),
      );
    }
    if (data.containsKey('image_url')) {
      context.handle(
        _imageUrlMeta,
        imageUrl.isAcceptableOrUnknown(data['image_url']!, _imageUrlMeta),
      );
    }
    if (data.containsKey('played_at')) {
      context.handle(
        _playedAtMeta,
        playedAt.isAcceptableOrUnknown(data['played_at']!, _playedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  OnlineHistoryData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return OnlineHistoryData(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      url: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}url'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
      artist: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}artist'],
      )!,
      album: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}album'],
      )!,
      licenseUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}license_url'],
      ),
      imageUrl: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}image_url'],
      ),
      playedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}played_at'],
      )!,
    );
  }

  @override
  $OnlineHistoryTable createAlias(String alias) {
    return $OnlineHistoryTable(attachedDatabase, alias);
  }
}

class OnlineHistoryData extends DataClass
    implements Insertable<OnlineHistoryData> {
  final int id;
  final String url;
  final String title;
  final String artist;
  final String album;
  final String? licenseUrl;
  final String? imageUrl;
  final DateTime playedAt;
  const OnlineHistoryData({
    required this.id,
    required this.url,
    required this.title,
    required this.artist,
    required this.album,
    this.licenseUrl,
    this.imageUrl,
    required this.playedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['url'] = Variable<String>(url);
    map['title'] = Variable<String>(title);
    map['artist'] = Variable<String>(artist);
    map['album'] = Variable<String>(album);
    if (!nullToAbsent || licenseUrl != null) {
      map['license_url'] = Variable<String>(licenseUrl);
    }
    if (!nullToAbsent || imageUrl != null) {
      map['image_url'] = Variable<String>(imageUrl);
    }
    map['played_at'] = Variable<DateTime>(playedAt);
    return map;
  }

  OnlineHistoryCompanion toCompanion(bool nullToAbsent) {
    return OnlineHistoryCompanion(
      id: Value(id),
      url: Value(url),
      title: Value(title),
      artist: Value(artist),
      album: Value(album),
      licenseUrl: licenseUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(licenseUrl),
      imageUrl: imageUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(imageUrl),
      playedAt: Value(playedAt),
    );
  }

  factory OnlineHistoryData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return OnlineHistoryData(
      id: serializer.fromJson<int>(json['id']),
      url: serializer.fromJson<String>(json['url']),
      title: serializer.fromJson<String>(json['title']),
      artist: serializer.fromJson<String>(json['artist']),
      album: serializer.fromJson<String>(json['album']),
      licenseUrl: serializer.fromJson<String?>(json['licenseUrl']),
      imageUrl: serializer.fromJson<String?>(json['imageUrl']),
      playedAt: serializer.fromJson<DateTime>(json['playedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'url': serializer.toJson<String>(url),
      'title': serializer.toJson<String>(title),
      'artist': serializer.toJson<String>(artist),
      'album': serializer.toJson<String>(album),
      'licenseUrl': serializer.toJson<String?>(licenseUrl),
      'imageUrl': serializer.toJson<String?>(imageUrl),
      'playedAt': serializer.toJson<DateTime>(playedAt),
    };
  }

  OnlineHistoryData copyWith({
    int? id,
    String? url,
    String? title,
    String? artist,
    String? album,
    Value<String?> licenseUrl = const Value.absent(),
    Value<String?> imageUrl = const Value.absent(),
    DateTime? playedAt,
  }) => OnlineHistoryData(
    id: id ?? this.id,
    url: url ?? this.url,
    title: title ?? this.title,
    artist: artist ?? this.artist,
    album: album ?? this.album,
    licenseUrl: licenseUrl.present ? licenseUrl.value : this.licenseUrl,
    imageUrl: imageUrl.present ? imageUrl.value : this.imageUrl,
    playedAt: playedAt ?? this.playedAt,
  );
  OnlineHistoryData copyWithCompanion(OnlineHistoryCompanion data) {
    return OnlineHistoryData(
      id: data.id.present ? data.id.value : this.id,
      url: data.url.present ? data.url.value : this.url,
      title: data.title.present ? data.title.value : this.title,
      artist: data.artist.present ? data.artist.value : this.artist,
      album: data.album.present ? data.album.value : this.album,
      licenseUrl: data.licenseUrl.present
          ? data.licenseUrl.value
          : this.licenseUrl,
      imageUrl: data.imageUrl.present ? data.imageUrl.value : this.imageUrl,
      playedAt: data.playedAt.present ? data.playedAt.value : this.playedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('OnlineHistoryData(')
          ..write('id: $id, ')
          ..write('url: $url, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('licenseUrl: $licenseUrl, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('playedAt: $playedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    url,
    title,
    artist,
    album,
    licenseUrl,
    imageUrl,
    playedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is OnlineHistoryData &&
          other.id == this.id &&
          other.url == this.url &&
          other.title == this.title &&
          other.artist == this.artist &&
          other.album == this.album &&
          other.licenseUrl == this.licenseUrl &&
          other.imageUrl == this.imageUrl &&
          other.playedAt == this.playedAt);
}

class OnlineHistoryCompanion extends UpdateCompanion<OnlineHistoryData> {
  final Value<int> id;
  final Value<String> url;
  final Value<String> title;
  final Value<String> artist;
  final Value<String> album;
  final Value<String?> licenseUrl;
  final Value<String?> imageUrl;
  final Value<DateTime> playedAt;
  const OnlineHistoryCompanion({
    this.id = const Value.absent(),
    this.url = const Value.absent(),
    this.title = const Value.absent(),
    this.artist = const Value.absent(),
    this.album = const Value.absent(),
    this.licenseUrl = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.playedAt = const Value.absent(),
  });
  OnlineHistoryCompanion.insert({
    this.id = const Value.absent(),
    required String url,
    required String title,
    required String artist,
    required String album,
    this.licenseUrl = const Value.absent(),
    this.imageUrl = const Value.absent(),
    this.playedAt = const Value.absent(),
  }) : url = Value(url),
       title = Value(title),
       artist = Value(artist),
       album = Value(album);
  static Insertable<OnlineHistoryData> custom({
    Expression<int>? id,
    Expression<String>? url,
    Expression<String>? title,
    Expression<String>? artist,
    Expression<String>? album,
    Expression<String>? licenseUrl,
    Expression<String>? imageUrl,
    Expression<DateTime>? playedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (url != null) 'url': url,
      if (title != null) 'title': title,
      if (artist != null) 'artist': artist,
      if (album != null) 'album': album,
      if (licenseUrl != null) 'license_url': licenseUrl,
      if (imageUrl != null) 'image_url': imageUrl,
      if (playedAt != null) 'played_at': playedAt,
    });
  }

  OnlineHistoryCompanion copyWith({
    Value<int>? id,
    Value<String>? url,
    Value<String>? title,
    Value<String>? artist,
    Value<String>? album,
    Value<String?>? licenseUrl,
    Value<String?>? imageUrl,
    Value<DateTime>? playedAt,
  }) {
    return OnlineHistoryCompanion(
      id: id ?? this.id,
      url: url ?? this.url,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      album: album ?? this.album,
      licenseUrl: licenseUrl ?? this.licenseUrl,
      imageUrl: imageUrl ?? this.imageUrl,
      playedAt: playedAt ?? this.playedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (url.present) {
      map['url'] = Variable<String>(url.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (artist.present) {
      map['artist'] = Variable<String>(artist.value);
    }
    if (album.present) {
      map['album'] = Variable<String>(album.value);
    }
    if (licenseUrl.present) {
      map['license_url'] = Variable<String>(licenseUrl.value);
    }
    if (imageUrl.present) {
      map['image_url'] = Variable<String>(imageUrl.value);
    }
    if (playedAt.present) {
      map['played_at'] = Variable<DateTime>(playedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('OnlineHistoryCompanion(')
          ..write('id: $id, ')
          ..write('url: $url, ')
          ..write('title: $title, ')
          ..write('artist: $artist, ')
          ..write('album: $album, ')
          ..write('licenseUrl: $licenseUrl, ')
          ..write('imageUrl: $imageUrl, ')
          ..write('playedAt: $playedAt')
          ..write(')'))
        .toString();
  }
}

class $LyricsCacheTable extends LyricsCache
    with TableInfo<$LyricsCacheTable, LyricsCacheData> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $LyricsCacheTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _trackKeyMeta = const VerificationMeta(
    'trackKey',
  );
  @override
  late final GeneratedColumn<String> trackKey = GeneratedColumn<String>(
    'track_key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _foundMeta = const VerificationMeta('found');
  @override
  late final GeneratedColumn<bool> found = GeneratedColumn<bool>(
    'found',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("found" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _plainLyricsMeta = const VerificationMeta(
    'plainLyrics',
  );
  @override
  late final GeneratedColumn<String> plainLyrics = GeneratedColumn<String>(
    'plain_lyrics',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _syncedLyricsMeta = const VerificationMeta(
    'syncedLyrics',
  );
  @override
  late final GeneratedColumn<String> syncedLyrics = GeneratedColumn<String>(
    'synced_lyrics',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _instrumentalMeta = const VerificationMeta(
    'instrumental',
  );
  @override
  late final GeneratedColumn<bool> instrumental = GeneratedColumn<bool>(
    'instrumental',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("instrumental" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _sourceMeta = const VerificationMeta('source');
  @override
  late final GeneratedColumn<String> source = GeneratedColumn<String>(
    'source',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _fetchedAtMeta = const VerificationMeta(
    'fetchedAt',
  );
  @override
  late final GeneratedColumn<DateTime> fetchedAt = GeneratedColumn<DateTime>(
    'fetched_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    trackKey,
    found,
    plainLyrics,
    syncedLyrics,
    instrumental,
    source,
    fetchedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'lyrics_cache';
  @override
  VerificationContext validateIntegrity(
    Insertable<LyricsCacheData> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('track_key')) {
      context.handle(
        _trackKeyMeta,
        trackKey.isAcceptableOrUnknown(data['track_key']!, _trackKeyMeta),
      );
    } else if (isInserting) {
      context.missing(_trackKeyMeta);
    }
    if (data.containsKey('found')) {
      context.handle(
        _foundMeta,
        found.isAcceptableOrUnknown(data['found']!, _foundMeta),
      );
    }
    if (data.containsKey('plain_lyrics')) {
      context.handle(
        _plainLyricsMeta,
        plainLyrics.isAcceptableOrUnknown(
          data['plain_lyrics']!,
          _plainLyricsMeta,
        ),
      );
    }
    if (data.containsKey('synced_lyrics')) {
      context.handle(
        _syncedLyricsMeta,
        syncedLyrics.isAcceptableOrUnknown(
          data['synced_lyrics']!,
          _syncedLyricsMeta,
        ),
      );
    }
    if (data.containsKey('instrumental')) {
      context.handle(
        _instrumentalMeta,
        instrumental.isAcceptableOrUnknown(
          data['instrumental']!,
          _instrumentalMeta,
        ),
      );
    }
    if (data.containsKey('source')) {
      context.handle(
        _sourceMeta,
        source.isAcceptableOrUnknown(data['source']!, _sourceMeta),
      );
    }
    if (data.containsKey('fetched_at')) {
      context.handle(
        _fetchedAtMeta,
        fetchedAt.isAcceptableOrUnknown(data['fetched_at']!, _fetchedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_fetchedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {trackKey};
  @override
  LyricsCacheData map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return LyricsCacheData(
      trackKey: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}track_key'],
      )!,
      found: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}found'],
      )!,
      plainLyrics: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}plain_lyrics'],
      ),
      syncedLyrics: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}synced_lyrics'],
      ),
      instrumental: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}instrumental'],
      )!,
      source: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source'],
      )!,
      fetchedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}fetched_at'],
      )!,
    );
  }

  @override
  $LyricsCacheTable createAlias(String alias) {
    return $LyricsCacheTable(attachedDatabase, alias);
  }
}

class LyricsCacheData extends DataClass implements Insertable<LyricsCacheData> {
  final String trackKey;
  final bool found;
  final String? plainLyrics;

  /// LRC text (`[01:23.45] words`), when the source has timings.
  final String? syncedLyrics;
  final bool instrumental;
  final String source;
  final DateTime fetchedAt;
  const LyricsCacheData({
    required this.trackKey,
    required this.found,
    this.plainLyrics,
    this.syncedLyrics,
    required this.instrumental,
    required this.source,
    required this.fetchedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['track_key'] = Variable<String>(trackKey);
    map['found'] = Variable<bool>(found);
    if (!nullToAbsent || plainLyrics != null) {
      map['plain_lyrics'] = Variable<String>(plainLyrics);
    }
    if (!nullToAbsent || syncedLyrics != null) {
      map['synced_lyrics'] = Variable<String>(syncedLyrics);
    }
    map['instrumental'] = Variable<bool>(instrumental);
    map['source'] = Variable<String>(source);
    map['fetched_at'] = Variable<DateTime>(fetchedAt);
    return map;
  }

  LyricsCacheCompanion toCompanion(bool nullToAbsent) {
    return LyricsCacheCompanion(
      trackKey: Value(trackKey),
      found: Value(found),
      plainLyrics: plainLyrics == null && nullToAbsent
          ? const Value.absent()
          : Value(plainLyrics),
      syncedLyrics: syncedLyrics == null && nullToAbsent
          ? const Value.absent()
          : Value(syncedLyrics),
      instrumental: Value(instrumental),
      source: Value(source),
      fetchedAt: Value(fetchedAt),
    );
  }

  factory LyricsCacheData.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return LyricsCacheData(
      trackKey: serializer.fromJson<String>(json['trackKey']),
      found: serializer.fromJson<bool>(json['found']),
      plainLyrics: serializer.fromJson<String?>(json['plainLyrics']),
      syncedLyrics: serializer.fromJson<String?>(json['syncedLyrics']),
      instrumental: serializer.fromJson<bool>(json['instrumental']),
      source: serializer.fromJson<String>(json['source']),
      fetchedAt: serializer.fromJson<DateTime>(json['fetchedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'trackKey': serializer.toJson<String>(trackKey),
      'found': serializer.toJson<bool>(found),
      'plainLyrics': serializer.toJson<String?>(plainLyrics),
      'syncedLyrics': serializer.toJson<String?>(syncedLyrics),
      'instrumental': serializer.toJson<bool>(instrumental),
      'source': serializer.toJson<String>(source),
      'fetchedAt': serializer.toJson<DateTime>(fetchedAt),
    };
  }

  LyricsCacheData copyWith({
    String? trackKey,
    bool? found,
    Value<String?> plainLyrics = const Value.absent(),
    Value<String?> syncedLyrics = const Value.absent(),
    bool? instrumental,
    String? source,
    DateTime? fetchedAt,
  }) => LyricsCacheData(
    trackKey: trackKey ?? this.trackKey,
    found: found ?? this.found,
    plainLyrics: plainLyrics.present ? plainLyrics.value : this.plainLyrics,
    syncedLyrics: syncedLyrics.present ? syncedLyrics.value : this.syncedLyrics,
    instrumental: instrumental ?? this.instrumental,
    source: source ?? this.source,
    fetchedAt: fetchedAt ?? this.fetchedAt,
  );
  LyricsCacheData copyWithCompanion(LyricsCacheCompanion data) {
    return LyricsCacheData(
      trackKey: data.trackKey.present ? data.trackKey.value : this.trackKey,
      found: data.found.present ? data.found.value : this.found,
      plainLyrics: data.plainLyrics.present
          ? data.plainLyrics.value
          : this.plainLyrics,
      syncedLyrics: data.syncedLyrics.present
          ? data.syncedLyrics.value
          : this.syncedLyrics,
      instrumental: data.instrumental.present
          ? data.instrumental.value
          : this.instrumental,
      source: data.source.present ? data.source.value : this.source,
      fetchedAt: data.fetchedAt.present ? data.fetchedAt.value : this.fetchedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('LyricsCacheData(')
          ..write('trackKey: $trackKey, ')
          ..write('found: $found, ')
          ..write('plainLyrics: $plainLyrics, ')
          ..write('syncedLyrics: $syncedLyrics, ')
          ..write('instrumental: $instrumental, ')
          ..write('source: $source, ')
          ..write('fetchedAt: $fetchedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    trackKey,
    found,
    plainLyrics,
    syncedLyrics,
    instrumental,
    source,
    fetchedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is LyricsCacheData &&
          other.trackKey == this.trackKey &&
          other.found == this.found &&
          other.plainLyrics == this.plainLyrics &&
          other.syncedLyrics == this.syncedLyrics &&
          other.instrumental == this.instrumental &&
          other.source == this.source &&
          other.fetchedAt == this.fetchedAt);
}

class LyricsCacheCompanion extends UpdateCompanion<LyricsCacheData> {
  final Value<String> trackKey;
  final Value<bool> found;
  final Value<String?> plainLyrics;
  final Value<String?> syncedLyrics;
  final Value<bool> instrumental;
  final Value<String> source;
  final Value<DateTime> fetchedAt;
  final Value<int> rowid;
  const LyricsCacheCompanion({
    this.trackKey = const Value.absent(),
    this.found = const Value.absent(),
    this.plainLyrics = const Value.absent(),
    this.syncedLyrics = const Value.absent(),
    this.instrumental = const Value.absent(),
    this.source = const Value.absent(),
    this.fetchedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  LyricsCacheCompanion.insert({
    required String trackKey,
    this.found = const Value.absent(),
    this.plainLyrics = const Value.absent(),
    this.syncedLyrics = const Value.absent(),
    this.instrumental = const Value.absent(),
    this.source = const Value.absent(),
    required DateTime fetchedAt,
    this.rowid = const Value.absent(),
  }) : trackKey = Value(trackKey),
       fetchedAt = Value(fetchedAt);
  static Insertable<LyricsCacheData> custom({
    Expression<String>? trackKey,
    Expression<bool>? found,
    Expression<String>? plainLyrics,
    Expression<String>? syncedLyrics,
    Expression<bool>? instrumental,
    Expression<String>? source,
    Expression<DateTime>? fetchedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (trackKey != null) 'track_key': trackKey,
      if (found != null) 'found': found,
      if (plainLyrics != null) 'plain_lyrics': plainLyrics,
      if (syncedLyrics != null) 'synced_lyrics': syncedLyrics,
      if (instrumental != null) 'instrumental': instrumental,
      if (source != null) 'source': source,
      if (fetchedAt != null) 'fetched_at': fetchedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  LyricsCacheCompanion copyWith({
    Value<String>? trackKey,
    Value<bool>? found,
    Value<String?>? plainLyrics,
    Value<String?>? syncedLyrics,
    Value<bool>? instrumental,
    Value<String>? source,
    Value<DateTime>? fetchedAt,
    Value<int>? rowid,
  }) {
    return LyricsCacheCompanion(
      trackKey: trackKey ?? this.trackKey,
      found: found ?? this.found,
      plainLyrics: plainLyrics ?? this.plainLyrics,
      syncedLyrics: syncedLyrics ?? this.syncedLyrics,
      instrumental: instrumental ?? this.instrumental,
      source: source ?? this.source,
      fetchedAt: fetchedAt ?? this.fetchedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (trackKey.present) {
      map['track_key'] = Variable<String>(trackKey.value);
    }
    if (found.present) {
      map['found'] = Variable<bool>(found.value);
    }
    if (plainLyrics.present) {
      map['plain_lyrics'] = Variable<String>(plainLyrics.value);
    }
    if (syncedLyrics.present) {
      map['synced_lyrics'] = Variable<String>(syncedLyrics.value);
    }
    if (instrumental.present) {
      map['instrumental'] = Variable<bool>(instrumental.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(source.value);
    }
    if (fetchedAt.present) {
      map['fetched_at'] = Variable<DateTime>(fetchedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('LyricsCacheCompanion(')
          ..write('trackKey: $trackKey, ')
          ..write('found: $found, ')
          ..write('plainLyrics: $plainLyrics, ')
          ..write('syncedLyrics: $syncedLyrics, ')
          ..write('instrumental: $instrumental, ')
          ..write('source: $source, ')
          ..write('fetchedAt: $fetchedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $SongsTable songs = $SongsTable(this);
  late final $QueueItemsTable queueItems = $QueueItemsTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final $PairedControllersTable pairedControllers =
      $PairedControllersTable(this);
  late final $RecentUrlsTable recentUrls = $RecentUrlsTable(this);
  late final $PlaylistsTable playlists = $PlaylistsTable(this);
  late final $PlaylistSongsTable playlistSongs = $PlaylistSongsTable(this);
  late final $QueueStreamsTable queueStreams = $QueueStreamsTable(this);
  late final $OnlineHistoryTable onlineHistory = $OnlineHistoryTable(this);
  late final $LyricsCacheTable lyricsCache = $LyricsCacheTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    songs,
    queueItems,
    settings,
    pairedControllers,
    recentUrls,
    playlists,
    playlistSongs,
    queueStreams,
    onlineHistory,
    lyricsCache,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'songs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('queue_items', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'playlists',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('playlist_songs', kind: UpdateKind.delete)],
    ),
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'songs',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('playlist_songs', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$SongsTableCreateCompanionBuilder =
    SongsCompanion Function({
      Value<int> id,
      required String title,
      Value<String?> artist,
      Value<String?> album,
      Value<int?> durationSeconds,
      Value<int?> trackNumber,
      Value<String?> filePath,
      Value<String?> url,
      Value<String?> albumArtPath,
      Value<int?> fileSizeBytes,
      Value<String?> mimeType,
      required String source,
      Value<DateTime> addedAt,
      Value<bool> favorite,
      Value<DateTime?> lastPlayedAt,
      Value<int> playCount,
    });
typedef $$SongsTableUpdateCompanionBuilder =
    SongsCompanion Function({
      Value<int> id,
      Value<String> title,
      Value<String?> artist,
      Value<String?> album,
      Value<int?> durationSeconds,
      Value<int?> trackNumber,
      Value<String?> filePath,
      Value<String?> url,
      Value<String?> albumArtPath,
      Value<int?> fileSizeBytes,
      Value<String?> mimeType,
      Value<String> source,
      Value<DateTime> addedAt,
      Value<bool> favorite,
      Value<DateTime?> lastPlayedAt,
      Value<int> playCount,
    });

final class $$SongsTableReferences
    extends BaseReferences<_$AppDatabase, $SongsTable, Song> {
  $$SongsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$QueueItemsTable, List<QueueItem>>
  _queueItemsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.queueItems,
    aliasName: $_aliasNameGenerator(db.songs.id, db.queueItems.songId),
  );

  $$QueueItemsTableProcessedTableManager get queueItemsRefs {
    final manager = $$QueueItemsTableTableManager(
      $_db,
      $_db.queueItems,
    ).filter((f) => f.songId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_queueItemsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$PlaylistSongsTable, List<PlaylistSong>>
  _playlistSongsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.playlistSongs,
    aliasName: $_aliasNameGenerator(db.songs.id, db.playlistSongs.songId),
  );

  $$PlaylistSongsTableProcessedTableManager get playlistSongsRefs {
    final manager = $$PlaylistSongsTableTableManager(
      $_db,
      $_db.playlistSongs,
    ).filter((f) => f.songId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_playlistSongsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$SongsTableFilterComposer extends Composer<_$AppDatabase, $SongsTable> {
  $$SongsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get trackNumber => $composableBuilder(
    column: $table.trackNumber,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get albumArtPath => $composableBuilder(
    column: $table.albumArtPath,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get fileSizeBytes => $composableBuilder(
    column: $table.fileSizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get playCount => $composableBuilder(
    column: $table.playCount,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> queueItemsRefs(
    Expression<bool> Function($$QueueItemsTableFilterComposer f) f,
  ) {
    final $$QueueItemsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.queueItems,
      getReferencedColumn: (t) => t.songId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$QueueItemsTableFilterComposer(
            $db: $db,
            $table: $db.queueItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> playlistSongsRefs(
    Expression<bool> Function($$PlaylistSongsTableFilterComposer f) f,
  ) {
    final $$PlaylistSongsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.playlistSongs,
      getReferencedColumn: (t) => t.songId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaylistSongsTableFilterComposer(
            $db: $db,
            $table: $db.playlistSongs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SongsTableOrderingComposer
    extends Composer<_$AppDatabase, $SongsTable> {
  $$SongsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get trackNumber => $composableBuilder(
    column: $table.trackNumber,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filePath => $composableBuilder(
    column: $table.filePath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get albumArtPath => $composableBuilder(
    column: $table.albumArtPath,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get fileSizeBytes => $composableBuilder(
    column: $table.fileSizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get favorite => $composableBuilder(
    column: $table.favorite,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get playCount => $composableBuilder(
    column: $table.playCount,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SongsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SongsTable> {
  $$SongsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<String> get album =>
      $composableBuilder(column: $table.album, builder: (column) => column);

  GeneratedColumn<int> get durationSeconds => $composableBuilder(
    column: $table.durationSeconds,
    builder: (column) => column,
  );

  GeneratedColumn<int> get trackNumber => $composableBuilder(
    column: $table.trackNumber,
    builder: (column) => column,
  );

  GeneratedColumn<String> get filePath =>
      $composableBuilder(column: $table.filePath, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get albumArtPath => $composableBuilder(
    column: $table.albumArtPath,
    builder: (column) => column,
  );

  GeneratedColumn<int> get fileSizeBytes => $composableBuilder(
    column: $table.fileSizeBytes,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<bool> get favorite =>
      $composableBuilder(column: $table.favorite, builder: (column) => column);

  GeneratedColumn<DateTime> get lastPlayedAt => $composableBuilder(
    column: $table.lastPlayedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get playCount =>
      $composableBuilder(column: $table.playCount, builder: (column) => column);

  Expression<T> queueItemsRefs<T extends Object>(
    Expression<T> Function($$QueueItemsTableAnnotationComposer a) f,
  ) {
    final $$QueueItemsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.queueItems,
      getReferencedColumn: (t) => t.songId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$QueueItemsTableAnnotationComposer(
            $db: $db,
            $table: $db.queueItems,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> playlistSongsRefs<T extends Object>(
    Expression<T> Function($$PlaylistSongsTableAnnotationComposer a) f,
  ) {
    final $$PlaylistSongsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.playlistSongs,
      getReferencedColumn: (t) => t.songId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaylistSongsTableAnnotationComposer(
            $db: $db,
            $table: $db.playlistSongs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$SongsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SongsTable,
          Song,
          $$SongsTableFilterComposer,
          $$SongsTableOrderingComposer,
          $$SongsTableAnnotationComposer,
          $$SongsTableCreateCompanionBuilder,
          $$SongsTableUpdateCompanionBuilder,
          (Song, $$SongsTableReferences),
          Song,
          PrefetchHooks Function({bool queueItemsRefs, bool playlistSongsRefs})
        > {
  $$SongsTableTableManager(_$AppDatabase db, $SongsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SongsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SongsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SongsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String?> artist = const Value.absent(),
                Value<String?> album = const Value.absent(),
                Value<int?> durationSeconds = const Value.absent(),
                Value<int?> trackNumber = const Value.absent(),
                Value<String?> filePath = const Value.absent(),
                Value<String?> url = const Value.absent(),
                Value<String?> albumArtPath = const Value.absent(),
                Value<int?> fileSizeBytes = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<DateTime?> lastPlayedAt = const Value.absent(),
                Value<int> playCount = const Value.absent(),
              }) => SongsCompanion(
                id: id,
                title: title,
                artist: artist,
                album: album,
                durationSeconds: durationSeconds,
                trackNumber: trackNumber,
                filePath: filePath,
                url: url,
                albumArtPath: albumArtPath,
                fileSizeBytes: fileSizeBytes,
                mimeType: mimeType,
                source: source,
                addedAt: addedAt,
                favorite: favorite,
                lastPlayedAt: lastPlayedAt,
                playCount: playCount,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String title,
                Value<String?> artist = const Value.absent(),
                Value<String?> album = const Value.absent(),
                Value<int?> durationSeconds = const Value.absent(),
                Value<int?> trackNumber = const Value.absent(),
                Value<String?> filePath = const Value.absent(),
                Value<String?> url = const Value.absent(),
                Value<String?> albumArtPath = const Value.absent(),
                Value<int?> fileSizeBytes = const Value.absent(),
                Value<String?> mimeType = const Value.absent(),
                required String source,
                Value<DateTime> addedAt = const Value.absent(),
                Value<bool> favorite = const Value.absent(),
                Value<DateTime?> lastPlayedAt = const Value.absent(),
                Value<int> playCount = const Value.absent(),
              }) => SongsCompanion.insert(
                id: id,
                title: title,
                artist: artist,
                album: album,
                durationSeconds: durationSeconds,
                trackNumber: trackNumber,
                filePath: filePath,
                url: url,
                albumArtPath: albumArtPath,
                fileSizeBytes: fileSizeBytes,
                mimeType: mimeType,
                source: source,
                addedAt: addedAt,
                favorite: favorite,
                lastPlayedAt: lastPlayedAt,
                playCount: playCount,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) =>
                    (e.readTable(table), $$SongsTableReferences(db, table, e)),
              )
              .toList(),
          prefetchHooksCallback:
              ({queueItemsRefs = false, playlistSongsRefs = false}) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (queueItemsRefs) db.queueItems,
                    if (playlistSongsRefs) db.playlistSongs,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (queueItemsRefs)
                        await $_getPrefetchedData<Song, $SongsTable, QueueItem>(
                          currentTable: table,
                          referencedTable: $$SongsTableReferences
                              ._queueItemsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SongsTableReferences(
                                db,
                                table,
                                p0,
                              ).queueItemsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.songId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (playlistSongsRefs)
                        await $_getPrefetchedData<
                          Song,
                          $SongsTable,
                          PlaylistSong
                        >(
                          currentTable: table,
                          referencedTable: $$SongsTableReferences
                              ._playlistSongsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$SongsTableReferences(
                                db,
                                table,
                                p0,
                              ).playlistSongsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.songId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$SongsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SongsTable,
      Song,
      $$SongsTableFilterComposer,
      $$SongsTableOrderingComposer,
      $$SongsTableAnnotationComposer,
      $$SongsTableCreateCompanionBuilder,
      $$SongsTableUpdateCompanionBuilder,
      (Song, $$SongsTableReferences),
      Song,
      PrefetchHooks Function({bool queueItemsRefs, bool playlistSongsRefs})
    >;
typedef $$QueueItemsTableCreateCompanionBuilder =
    QueueItemsCompanion Function({
      Value<int> id,
      required int songId,
      required int position,
      required String source,
      Value<DateTime> addedAt,
      Value<String> addedBy,
    });
typedef $$QueueItemsTableUpdateCompanionBuilder =
    QueueItemsCompanion Function({
      Value<int> id,
      Value<int> songId,
      Value<int> position,
      Value<String> source,
      Value<DateTime> addedAt,
      Value<String> addedBy,
    });

final class $$QueueItemsTableReferences
    extends BaseReferences<_$AppDatabase, $QueueItemsTable, QueueItem> {
  $$QueueItemsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $SongsTable _songIdTable(_$AppDatabase db) => db.songs.createAlias(
    $_aliasNameGenerator(db.queueItems.songId, db.songs.id),
  );

  $$SongsTableProcessedTableManager get songId {
    final $_column = $_itemColumn<int>('song_id')!;

    final manager = $$SongsTableTableManager(
      $_db,
      $_db.songs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_songIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$QueueItemsTableFilterComposer
    extends Composer<_$AppDatabase, $QueueItemsTable> {
  $$QueueItemsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get addedBy => $composableBuilder(
    column: $table.addedBy,
    builder: (column) => ColumnFilters(column),
  );

  $$SongsTableFilterComposer get songId {
    final $$SongsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.songId,
      referencedTable: $db.songs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SongsTableFilterComposer(
            $db: $db,
            $table: $db.songs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$QueueItemsTableOrderingComposer
    extends Composer<_$AppDatabase, $QueueItemsTable> {
  $$QueueItemsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get addedAt => $composableBuilder(
    column: $table.addedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get addedBy => $composableBuilder(
    column: $table.addedBy,
    builder: (column) => ColumnOrderings(column),
  );

  $$SongsTableOrderingComposer get songId {
    final $$SongsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.songId,
      referencedTable: $db.songs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SongsTableOrderingComposer(
            $db: $db,
            $table: $db.songs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$QueueItemsTableAnnotationComposer
    extends Composer<_$AppDatabase, $QueueItemsTable> {
  $$QueueItemsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<DateTime> get addedAt =>
      $composableBuilder(column: $table.addedAt, builder: (column) => column);

  GeneratedColumn<String> get addedBy =>
      $composableBuilder(column: $table.addedBy, builder: (column) => column);

  $$SongsTableAnnotationComposer get songId {
    final $$SongsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.songId,
      referencedTable: $db.songs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SongsTableAnnotationComposer(
            $db: $db,
            $table: $db.songs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$QueueItemsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $QueueItemsTable,
          QueueItem,
          $$QueueItemsTableFilterComposer,
          $$QueueItemsTableOrderingComposer,
          $$QueueItemsTableAnnotationComposer,
          $$QueueItemsTableCreateCompanionBuilder,
          $$QueueItemsTableUpdateCompanionBuilder,
          (QueueItem, $$QueueItemsTableReferences),
          QueueItem,
          PrefetchHooks Function({bool songId})
        > {
  $$QueueItemsTableTableManager(_$AppDatabase db, $QueueItemsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QueueItemsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$QueueItemsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QueueItemsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> songId = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<DateTime> addedAt = const Value.absent(),
                Value<String> addedBy = const Value.absent(),
              }) => QueueItemsCompanion(
                id: id,
                songId: songId,
                position: position,
                source: source,
                addedAt: addedAt,
                addedBy: addedBy,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int songId,
                required int position,
                required String source,
                Value<DateTime> addedAt = const Value.absent(),
                Value<String> addedBy = const Value.absent(),
              }) => QueueItemsCompanion.insert(
                id: id,
                songId: songId,
                position: position,
                source: source,
                addedAt: addedAt,
                addedBy: addedBy,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$QueueItemsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({songId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (songId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.songId,
                                referencedTable: $$QueueItemsTableReferences
                                    ._songIdTable(db),
                                referencedColumn: $$QueueItemsTableReferences
                                    ._songIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$QueueItemsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $QueueItemsTable,
      QueueItem,
      $$QueueItemsTableFilterComposer,
      $$QueueItemsTableOrderingComposer,
      $$QueueItemsTableAnnotationComposer,
      $$QueueItemsTableCreateCompanionBuilder,
      $$QueueItemsTableUpdateCompanionBuilder,
      (QueueItem, $$QueueItemsTableReferences),
      QueueItem,
      PrefetchHooks Function({bool songId})
    >;
typedef $$SettingsTableCreateCompanionBuilder =
    SettingsCompanion Function({
      required String key,
      required String value,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });
typedef $$SettingsTableUpdateCompanionBuilder =
    SettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<DateTime> updatedAt,
      Value<int> rowid,
    });

class $$SettingsTableFilterComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SettingsTable,
          Setting,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
          Setting,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$AppDatabase db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<DateTime> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                key: key,
                value: value,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SettingsTable,
      Setting,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (Setting, BaseReferences<_$AppDatabase, $SettingsTable, Setting>),
      Setting,
      PrefetchHooks Function()
    >;
typedef $$PairedControllersTableCreateCompanionBuilder =
    PairedControllersCompanion Function({
      required String sessionId,
      required String controllerName,
      Value<String?> controllerAddress,
      required String connectionType,
      Value<DateTime> pairedAt,
      Value<DateTime> lastSeenAt,
      Value<bool> active,
      Value<String?> tokenHash,
      Value<bool> trusted,
      Value<int> rowid,
    });
typedef $$PairedControllersTableUpdateCompanionBuilder =
    PairedControllersCompanion Function({
      Value<String> sessionId,
      Value<String> controllerName,
      Value<String?> controllerAddress,
      Value<String> connectionType,
      Value<DateTime> pairedAt,
      Value<DateTime> lastSeenAt,
      Value<bool> active,
      Value<String?> tokenHash,
      Value<bool> trusted,
      Value<int> rowid,
    });

class $$PairedControllersTableFilterComposer
    extends Composer<_$AppDatabase, $PairedControllersTable> {
  $$PairedControllersTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get controllerName => $composableBuilder(
    column: $table.controllerName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get controllerAddress => $composableBuilder(
    column: $table.controllerAddress,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get connectionType => $composableBuilder(
    column: $table.connectionType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get pairedAt => $composableBuilder(
    column: $table.pairedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tokenHash => $composableBuilder(
    column: $table.tokenHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get trusted => $composableBuilder(
    column: $table.trusted,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PairedControllersTableOrderingComposer
    extends Composer<_$AppDatabase, $PairedControllersTable> {
  $$PairedControllersTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get controllerName => $composableBuilder(
    column: $table.controllerName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get controllerAddress => $composableBuilder(
    column: $table.controllerAddress,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get connectionType => $composableBuilder(
    column: $table.connectionType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get pairedAt => $composableBuilder(
    column: $table.pairedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get active => $composableBuilder(
    column: $table.active,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tokenHash => $composableBuilder(
    column: $table.tokenHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get trusted => $composableBuilder(
    column: $table.trusted,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PairedControllersTableAnnotationComposer
    extends Composer<_$AppDatabase, $PairedControllersTable> {
  $$PairedControllersTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get controllerName => $composableBuilder(
    column: $table.controllerName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get controllerAddress => $composableBuilder(
    column: $table.controllerAddress,
    builder: (column) => column,
  );

  GeneratedColumn<String> get connectionType => $composableBuilder(
    column: $table.connectionType,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get pairedAt =>
      $composableBuilder(column: $table.pairedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSeenAt => $composableBuilder(
    column: $table.lastSeenAt,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get active =>
      $composableBuilder(column: $table.active, builder: (column) => column);

  GeneratedColumn<String> get tokenHash =>
      $composableBuilder(column: $table.tokenHash, builder: (column) => column);

  GeneratedColumn<bool> get trusted =>
      $composableBuilder(column: $table.trusted, builder: (column) => column);
}

class $$PairedControllersTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PairedControllersTable,
          PairedController,
          $$PairedControllersTableFilterComposer,
          $$PairedControllersTableOrderingComposer,
          $$PairedControllersTableAnnotationComposer,
          $$PairedControllersTableCreateCompanionBuilder,
          $$PairedControllersTableUpdateCompanionBuilder,
          (
            PairedController,
            BaseReferences<
              _$AppDatabase,
              $PairedControllersTable,
              PairedController
            >,
          ),
          PairedController,
          PrefetchHooks Function()
        > {
  $$PairedControllersTableTableManager(
    _$AppDatabase db,
    $PairedControllersTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PairedControllersTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PairedControllersTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PairedControllersTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> sessionId = const Value.absent(),
                Value<String> controllerName = const Value.absent(),
                Value<String?> controllerAddress = const Value.absent(),
                Value<String> connectionType = const Value.absent(),
                Value<DateTime> pairedAt = const Value.absent(),
                Value<DateTime> lastSeenAt = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<String?> tokenHash = const Value.absent(),
                Value<bool> trusted = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PairedControllersCompanion(
                sessionId: sessionId,
                controllerName: controllerName,
                controllerAddress: controllerAddress,
                connectionType: connectionType,
                pairedAt: pairedAt,
                lastSeenAt: lastSeenAt,
                active: active,
                tokenHash: tokenHash,
                trusted: trusted,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String sessionId,
                required String controllerName,
                Value<String?> controllerAddress = const Value.absent(),
                required String connectionType,
                Value<DateTime> pairedAt = const Value.absent(),
                Value<DateTime> lastSeenAt = const Value.absent(),
                Value<bool> active = const Value.absent(),
                Value<String?> tokenHash = const Value.absent(),
                Value<bool> trusted = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PairedControllersCompanion.insert(
                sessionId: sessionId,
                controllerName: controllerName,
                controllerAddress: controllerAddress,
                connectionType: connectionType,
                pairedAt: pairedAt,
                lastSeenAt: lastSeenAt,
                active: active,
                tokenHash: tokenHash,
                trusted: trusted,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PairedControllersTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PairedControllersTable,
      PairedController,
      $$PairedControllersTableFilterComposer,
      $$PairedControllersTableOrderingComposer,
      $$PairedControllersTableAnnotationComposer,
      $$PairedControllersTableCreateCompanionBuilder,
      $$PairedControllersTableUpdateCompanionBuilder,
      (
        PairedController,
        BaseReferences<
          _$AppDatabase,
          $PairedControllersTable,
          PairedController
        >,
      ),
      PairedController,
      PrefetchHooks Function()
    >;
typedef $$RecentUrlsTableCreateCompanionBuilder =
    RecentUrlsCompanion Function({
      Value<int> id,
      required String url,
      Value<String?> title,
      Value<DateTime> lastUsedAt,
    });
typedef $$RecentUrlsTableUpdateCompanionBuilder =
    RecentUrlsCompanion Function({
      Value<int> id,
      Value<String> url,
      Value<String?> title,
      Value<DateTime> lastUsedAt,
    });

class $$RecentUrlsTableFilterComposer
    extends Composer<_$AppDatabase, $RecentUrlsTable> {
  $$RecentUrlsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RecentUrlsTableOrderingComposer
    extends Composer<_$AppDatabase, $RecentUrlsTable> {
  $$RecentUrlsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RecentUrlsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RecentUrlsTable> {
  $$RecentUrlsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<DateTime> get lastUsedAt => $composableBuilder(
    column: $table.lastUsedAt,
    builder: (column) => column,
  );
}

class $$RecentUrlsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RecentUrlsTable,
          RecentUrl,
          $$RecentUrlsTableFilterComposer,
          $$RecentUrlsTableOrderingComposer,
          $$RecentUrlsTableAnnotationComposer,
          $$RecentUrlsTableCreateCompanionBuilder,
          $$RecentUrlsTableUpdateCompanionBuilder,
          (
            RecentUrl,
            BaseReferences<_$AppDatabase, $RecentUrlsTable, RecentUrl>,
          ),
          RecentUrl,
          PrefetchHooks Function()
        > {
  $$RecentUrlsTableTableManager(_$AppDatabase db, $RecentUrlsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RecentUrlsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RecentUrlsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RecentUrlsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<String?> title = const Value.absent(),
                Value<DateTime> lastUsedAt = const Value.absent(),
              }) => RecentUrlsCompanion(
                id: id,
                url: url,
                title: title,
                lastUsedAt: lastUsedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String url,
                Value<String?> title = const Value.absent(),
                Value<DateTime> lastUsedAt = const Value.absent(),
              }) => RecentUrlsCompanion.insert(
                id: id,
                url: url,
                title: title,
                lastUsedAt: lastUsedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RecentUrlsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RecentUrlsTable,
      RecentUrl,
      $$RecentUrlsTableFilterComposer,
      $$RecentUrlsTableOrderingComposer,
      $$RecentUrlsTableAnnotationComposer,
      $$RecentUrlsTableCreateCompanionBuilder,
      $$RecentUrlsTableUpdateCompanionBuilder,
      (RecentUrl, BaseReferences<_$AppDatabase, $RecentUrlsTable, RecentUrl>),
      RecentUrl,
      PrefetchHooks Function()
    >;
typedef $$PlaylistsTableCreateCompanionBuilder =
    PlaylistsCompanion Function({
      Value<int> id,
      required String name,
      Value<DateTime> createdAt,
    });
typedef $$PlaylistsTableUpdateCompanionBuilder =
    PlaylistsCompanion Function({
      Value<int> id,
      Value<String> name,
      Value<DateTime> createdAt,
    });

final class $$PlaylistsTableReferences
    extends BaseReferences<_$AppDatabase, $PlaylistsTable, Playlist> {
  $$PlaylistsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$PlaylistSongsTable, List<PlaylistSong>>
  _playlistSongsRefsTable(_$AppDatabase db) => MultiTypedResultKey.fromTable(
    db.playlistSongs,
    aliasName: $_aliasNameGenerator(
      db.playlists.id,
      db.playlistSongs.playlistId,
    ),
  );

  $$PlaylistSongsTableProcessedTableManager get playlistSongsRefs {
    final manager = $$PlaylistSongsTableTableManager(
      $_db,
      $_db.playlistSongs,
    ).filter((f) => f.playlistId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_playlistSongsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$PlaylistsTableFilterComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> playlistSongsRefs(
    Expression<bool> Function($$PlaylistSongsTableFilterComposer f) f,
  ) {
    final $$PlaylistSongsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.playlistSongs,
      getReferencedColumn: (t) => t.playlistId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaylistSongsTableFilterComposer(
            $db: $db,
            $table: $db.playlistSongs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PlaylistsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PlaylistsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaylistsTable> {
  $$PlaylistsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  Expression<T> playlistSongsRefs<T extends Object>(
    Expression<T> Function($$PlaylistSongsTableAnnotationComposer a) f,
  ) {
    final $$PlaylistSongsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.playlistSongs,
      getReferencedColumn: (t) => t.playlistId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaylistSongsTableAnnotationComposer(
            $db: $db,
            $table: $db.playlistSongs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$PlaylistsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaylistsTable,
          Playlist,
          $$PlaylistsTableFilterComposer,
          $$PlaylistsTableOrderingComposer,
          $$PlaylistsTableAnnotationComposer,
          $$PlaylistsTableCreateCompanionBuilder,
          $$PlaylistsTableUpdateCompanionBuilder,
          (Playlist, $$PlaylistsTableReferences),
          Playlist,
          PrefetchHooks Function({bool playlistSongsRefs})
        > {
  $$PlaylistsTableTableManager(_$AppDatabase db, $PlaylistsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaylistsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
              }) =>
                  PlaylistsCompanion(id: id, name: name, createdAt: createdAt),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String name,
                Value<DateTime> createdAt = const Value.absent(),
              }) => PlaylistsCompanion.insert(
                id: id,
                name: name,
                createdAt: createdAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PlaylistsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({playlistSongsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [
                if (playlistSongsRefs) db.playlistSongs,
              ],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (playlistSongsRefs)
                    await $_getPrefetchedData<
                      Playlist,
                      $PlaylistsTable,
                      PlaylistSong
                    >(
                      currentTable: table,
                      referencedTable: $$PlaylistsTableReferences
                          ._playlistSongsRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$PlaylistsTableReferences(
                            db,
                            table,
                            p0,
                          ).playlistSongsRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.playlistId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$PlaylistsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaylistsTable,
      Playlist,
      $$PlaylistsTableFilterComposer,
      $$PlaylistsTableOrderingComposer,
      $$PlaylistsTableAnnotationComposer,
      $$PlaylistsTableCreateCompanionBuilder,
      $$PlaylistsTableUpdateCompanionBuilder,
      (Playlist, $$PlaylistsTableReferences),
      Playlist,
      PrefetchHooks Function({bool playlistSongsRefs})
    >;
typedef $$PlaylistSongsTableCreateCompanionBuilder =
    PlaylistSongsCompanion Function({
      Value<int> id,
      required int playlistId,
      required int songId,
      required int position,
    });
typedef $$PlaylistSongsTableUpdateCompanionBuilder =
    PlaylistSongsCompanion Function({
      Value<int> id,
      Value<int> playlistId,
      Value<int> songId,
      Value<int> position,
    });

final class $$PlaylistSongsTableReferences
    extends BaseReferences<_$AppDatabase, $PlaylistSongsTable, PlaylistSong> {
  $$PlaylistSongsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $PlaylistsTable _playlistIdTable(_$AppDatabase db) =>
      db.playlists.createAlias(
        $_aliasNameGenerator(db.playlistSongs.playlistId, db.playlists.id),
      );

  $$PlaylistsTableProcessedTableManager get playlistId {
    final $_column = $_itemColumn<int>('playlist_id')!;

    final manager = $$PlaylistsTableTableManager(
      $_db,
      $_db.playlists,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_playlistIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }

  static $SongsTable _songIdTable(_$AppDatabase db) => db.songs.createAlias(
    $_aliasNameGenerator(db.playlistSongs.songId, db.songs.id),
  );

  $$SongsTableProcessedTableManager get songId {
    final $_column = $_itemColumn<int>('song_id')!;

    final manager = $$SongsTableTableManager(
      $_db,
      $_db.songs,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_songIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$PlaylistSongsTableFilterComposer
    extends Composer<_$AppDatabase, $PlaylistSongsTable> {
  $$PlaylistSongsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  $$PlaylistsTableFilterComposer get playlistId {
    final $$PlaylistsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.playlistId,
      referencedTable: $db.playlists,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaylistsTableFilterComposer(
            $db: $db,
            $table: $db.playlists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SongsTableFilterComposer get songId {
    final $$SongsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.songId,
      referencedTable: $db.songs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SongsTableFilterComposer(
            $db: $db,
            $table: $db.songs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlaylistSongsTableOrderingComposer
    extends Composer<_$AppDatabase, $PlaylistSongsTable> {
  $$PlaylistSongsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  $$PlaylistsTableOrderingComposer get playlistId {
    final $$PlaylistsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.playlistId,
      referencedTable: $db.playlists,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaylistsTableOrderingComposer(
            $db: $db,
            $table: $db.playlists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SongsTableOrderingComposer get songId {
    final $$SongsTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.songId,
      referencedTable: $db.songs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SongsTableOrderingComposer(
            $db: $db,
            $table: $db.songs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlaylistSongsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PlaylistSongsTable> {
  $$PlaylistSongsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  $$PlaylistsTableAnnotationComposer get playlistId {
    final $$PlaylistsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.playlistId,
      referencedTable: $db.playlists,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$PlaylistsTableAnnotationComposer(
            $db: $db,
            $table: $db.playlists,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }

  $$SongsTableAnnotationComposer get songId {
    final $$SongsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.songId,
      referencedTable: $db.songs,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SongsTableAnnotationComposer(
            $db: $db,
            $table: $db.songs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$PlaylistSongsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PlaylistSongsTable,
          PlaylistSong,
          $$PlaylistSongsTableFilterComposer,
          $$PlaylistSongsTableOrderingComposer,
          $$PlaylistSongsTableAnnotationComposer,
          $$PlaylistSongsTableCreateCompanionBuilder,
          $$PlaylistSongsTableUpdateCompanionBuilder,
          (PlaylistSong, $$PlaylistSongsTableReferences),
          PlaylistSong,
          PrefetchHooks Function({bool playlistId, bool songId})
        > {
  $$PlaylistSongsTableTableManager(_$AppDatabase db, $PlaylistSongsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PlaylistSongsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PlaylistSongsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PlaylistSongsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> playlistId = const Value.absent(),
                Value<int> songId = const Value.absent(),
                Value<int> position = const Value.absent(),
              }) => PlaylistSongsCompanion(
                id: id,
                playlistId: playlistId,
                songId: songId,
                position: position,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int playlistId,
                required int songId,
                required int position,
              }) => PlaylistSongsCompanion.insert(
                id: id,
                playlistId: playlistId,
                songId: songId,
                position: position,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$PlaylistSongsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({playlistId = false, songId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (playlistId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.playlistId,
                                referencedTable: $$PlaylistSongsTableReferences
                                    ._playlistIdTable(db),
                                referencedColumn: $$PlaylistSongsTableReferences
                                    ._playlistIdTable(db)
                                    .id,
                              )
                              as T;
                    }
                    if (songId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.songId,
                                referencedTable: $$PlaylistSongsTableReferences
                                    ._songIdTable(db),
                                referencedColumn: $$PlaylistSongsTableReferences
                                    ._songIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$PlaylistSongsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PlaylistSongsTable,
      PlaylistSong,
      $$PlaylistSongsTableFilterComposer,
      $$PlaylistSongsTableOrderingComposer,
      $$PlaylistSongsTableAnnotationComposer,
      $$PlaylistSongsTableCreateCompanionBuilder,
      $$PlaylistSongsTableUpdateCompanionBuilder,
      (PlaylistSong, $$PlaylistSongsTableReferences),
      PlaylistSong,
      PrefetchHooks Function({bool playlistId, bool songId})
    >;
typedef $$QueueStreamsTableCreateCompanionBuilder =
    QueueStreamsCompanion Function({
      Value<int> id,
      required int position,
      required String url,
      required String title,
      required String artist,
      required String album,
      Value<String?> licenseUrl,
      Value<String?> imageUrl,
    });
typedef $$QueueStreamsTableUpdateCompanionBuilder =
    QueueStreamsCompanion Function({
      Value<int> id,
      Value<int> position,
      Value<String> url,
      Value<String> title,
      Value<String> artist,
      Value<String> album,
      Value<String?> licenseUrl,
      Value<String?> imageUrl,
    });

class $$QueueStreamsTableFilterComposer
    extends Composer<_$AppDatabase, $QueueStreamsTable> {
  $$QueueStreamsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get licenseUrl => $composableBuilder(
    column: $table.licenseUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnFilters(column),
  );
}

class $$QueueStreamsTableOrderingComposer
    extends Composer<_$AppDatabase, $QueueStreamsTable> {
  $$QueueStreamsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get position => $composableBuilder(
    column: $table.position,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get licenseUrl => $composableBuilder(
    column: $table.licenseUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$QueueStreamsTableAnnotationComposer
    extends Composer<_$AppDatabase, $QueueStreamsTable> {
  $$QueueStreamsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get position =>
      $composableBuilder(column: $table.position, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<String> get album =>
      $composableBuilder(column: $table.album, builder: (column) => column);

  GeneratedColumn<String> get licenseUrl => $composableBuilder(
    column: $table.licenseUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get imageUrl =>
      $composableBuilder(column: $table.imageUrl, builder: (column) => column);
}

class $$QueueStreamsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $QueueStreamsTable,
          QueueStream,
          $$QueueStreamsTableFilterComposer,
          $$QueueStreamsTableOrderingComposer,
          $$QueueStreamsTableAnnotationComposer,
          $$QueueStreamsTableCreateCompanionBuilder,
          $$QueueStreamsTableUpdateCompanionBuilder,
          (
            QueueStream,
            BaseReferences<_$AppDatabase, $QueueStreamsTable, QueueStream>,
          ),
          QueueStream,
          PrefetchHooks Function()
        > {
  $$QueueStreamsTableTableManager(_$AppDatabase db, $QueueStreamsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$QueueStreamsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$QueueStreamsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$QueueStreamsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<int> position = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> artist = const Value.absent(),
                Value<String> album = const Value.absent(),
                Value<String?> licenseUrl = const Value.absent(),
                Value<String?> imageUrl = const Value.absent(),
              }) => QueueStreamsCompanion(
                id: id,
                position: position,
                url: url,
                title: title,
                artist: artist,
                album: album,
                licenseUrl: licenseUrl,
                imageUrl: imageUrl,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required int position,
                required String url,
                required String title,
                required String artist,
                required String album,
                Value<String?> licenseUrl = const Value.absent(),
                Value<String?> imageUrl = const Value.absent(),
              }) => QueueStreamsCompanion.insert(
                id: id,
                position: position,
                url: url,
                title: title,
                artist: artist,
                album: album,
                licenseUrl: licenseUrl,
                imageUrl: imageUrl,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$QueueStreamsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $QueueStreamsTable,
      QueueStream,
      $$QueueStreamsTableFilterComposer,
      $$QueueStreamsTableOrderingComposer,
      $$QueueStreamsTableAnnotationComposer,
      $$QueueStreamsTableCreateCompanionBuilder,
      $$QueueStreamsTableUpdateCompanionBuilder,
      (
        QueueStream,
        BaseReferences<_$AppDatabase, $QueueStreamsTable, QueueStream>,
      ),
      QueueStream,
      PrefetchHooks Function()
    >;
typedef $$OnlineHistoryTableCreateCompanionBuilder =
    OnlineHistoryCompanion Function({
      Value<int> id,
      required String url,
      required String title,
      required String artist,
      required String album,
      Value<String?> licenseUrl,
      Value<String?> imageUrl,
      Value<DateTime> playedAt,
    });
typedef $$OnlineHistoryTableUpdateCompanionBuilder =
    OnlineHistoryCompanion Function({
      Value<int> id,
      Value<String> url,
      Value<String> title,
      Value<String> artist,
      Value<String> album,
      Value<String?> licenseUrl,
      Value<String?> imageUrl,
      Value<DateTime> playedAt,
    });

class $$OnlineHistoryTableFilterComposer
    extends Composer<_$AppDatabase, $OnlineHistoryTable> {
  $$OnlineHistoryTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get licenseUrl => $composableBuilder(
    column: $table.licenseUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get playedAt => $composableBuilder(
    column: $table.playedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$OnlineHistoryTableOrderingComposer
    extends Composer<_$AppDatabase, $OnlineHistoryTable> {
  $$OnlineHistoryTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get url => $composableBuilder(
    column: $table.url,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get artist => $composableBuilder(
    column: $table.artist,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get album => $composableBuilder(
    column: $table.album,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get licenseUrl => $composableBuilder(
    column: $table.licenseUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get imageUrl => $composableBuilder(
    column: $table.imageUrl,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get playedAt => $composableBuilder(
    column: $table.playedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$OnlineHistoryTableAnnotationComposer
    extends Composer<_$AppDatabase, $OnlineHistoryTable> {
  $$OnlineHistoryTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get url =>
      $composableBuilder(column: $table.url, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);

  GeneratedColumn<String> get artist =>
      $composableBuilder(column: $table.artist, builder: (column) => column);

  GeneratedColumn<String> get album =>
      $composableBuilder(column: $table.album, builder: (column) => column);

  GeneratedColumn<String> get licenseUrl => $composableBuilder(
    column: $table.licenseUrl,
    builder: (column) => column,
  );

  GeneratedColumn<String> get imageUrl =>
      $composableBuilder(column: $table.imageUrl, builder: (column) => column);

  GeneratedColumn<DateTime> get playedAt =>
      $composableBuilder(column: $table.playedAt, builder: (column) => column);
}

class $$OnlineHistoryTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $OnlineHistoryTable,
          OnlineHistoryData,
          $$OnlineHistoryTableFilterComposer,
          $$OnlineHistoryTableOrderingComposer,
          $$OnlineHistoryTableAnnotationComposer,
          $$OnlineHistoryTableCreateCompanionBuilder,
          $$OnlineHistoryTableUpdateCompanionBuilder,
          (
            OnlineHistoryData,
            BaseReferences<
              _$AppDatabase,
              $OnlineHistoryTable,
              OnlineHistoryData
            >,
          ),
          OnlineHistoryData,
          PrefetchHooks Function()
        > {
  $$OnlineHistoryTableTableManager(_$AppDatabase db, $OnlineHistoryTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$OnlineHistoryTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$OnlineHistoryTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$OnlineHistoryTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> url = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<String> artist = const Value.absent(),
                Value<String> album = const Value.absent(),
                Value<String?> licenseUrl = const Value.absent(),
                Value<String?> imageUrl = const Value.absent(),
                Value<DateTime> playedAt = const Value.absent(),
              }) => OnlineHistoryCompanion(
                id: id,
                url: url,
                title: title,
                artist: artist,
                album: album,
                licenseUrl: licenseUrl,
                imageUrl: imageUrl,
                playedAt: playedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String url,
                required String title,
                required String artist,
                required String album,
                Value<String?> licenseUrl = const Value.absent(),
                Value<String?> imageUrl = const Value.absent(),
                Value<DateTime> playedAt = const Value.absent(),
              }) => OnlineHistoryCompanion.insert(
                id: id,
                url: url,
                title: title,
                artist: artist,
                album: album,
                licenseUrl: licenseUrl,
                imageUrl: imageUrl,
                playedAt: playedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$OnlineHistoryTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $OnlineHistoryTable,
      OnlineHistoryData,
      $$OnlineHistoryTableFilterComposer,
      $$OnlineHistoryTableOrderingComposer,
      $$OnlineHistoryTableAnnotationComposer,
      $$OnlineHistoryTableCreateCompanionBuilder,
      $$OnlineHistoryTableUpdateCompanionBuilder,
      (
        OnlineHistoryData,
        BaseReferences<_$AppDatabase, $OnlineHistoryTable, OnlineHistoryData>,
      ),
      OnlineHistoryData,
      PrefetchHooks Function()
    >;
typedef $$LyricsCacheTableCreateCompanionBuilder =
    LyricsCacheCompanion Function({
      required String trackKey,
      Value<bool> found,
      Value<String?> plainLyrics,
      Value<String?> syncedLyrics,
      Value<bool> instrumental,
      Value<String> source,
      required DateTime fetchedAt,
      Value<int> rowid,
    });
typedef $$LyricsCacheTableUpdateCompanionBuilder =
    LyricsCacheCompanion Function({
      Value<String> trackKey,
      Value<bool> found,
      Value<String?> plainLyrics,
      Value<String?> syncedLyrics,
      Value<bool> instrumental,
      Value<String> source,
      Value<DateTime> fetchedAt,
      Value<int> rowid,
    });

class $$LyricsCacheTableFilterComposer
    extends Composer<_$AppDatabase, $LyricsCacheTable> {
  $$LyricsCacheTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get trackKey => $composableBuilder(
    column: $table.trackKey,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get found => $composableBuilder(
    column: $table.found,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get plainLyrics => $composableBuilder(
    column: $table.plainLyrics,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get syncedLyrics => $composableBuilder(
    column: $table.syncedLyrics,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get instrumental => $composableBuilder(
    column: $table.instrumental,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$LyricsCacheTableOrderingComposer
    extends Composer<_$AppDatabase, $LyricsCacheTable> {
  $$LyricsCacheTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get trackKey => $composableBuilder(
    column: $table.trackKey,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get found => $composableBuilder(
    column: $table.found,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get plainLyrics => $composableBuilder(
    column: $table.plainLyrics,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get syncedLyrics => $composableBuilder(
    column: $table.syncedLyrics,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get instrumental => $composableBuilder(
    column: $table.instrumental,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get fetchedAt => $composableBuilder(
    column: $table.fetchedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$LyricsCacheTableAnnotationComposer
    extends Composer<_$AppDatabase, $LyricsCacheTable> {
  $$LyricsCacheTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get trackKey =>
      $composableBuilder(column: $table.trackKey, builder: (column) => column);

  GeneratedColumn<bool> get found =>
      $composableBuilder(column: $table.found, builder: (column) => column);

  GeneratedColumn<String> get plainLyrics => $composableBuilder(
    column: $table.plainLyrics,
    builder: (column) => column,
  );

  GeneratedColumn<String> get syncedLyrics => $composableBuilder(
    column: $table.syncedLyrics,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get instrumental => $composableBuilder(
    column: $table.instrumental,
    builder: (column) => column,
  );

  GeneratedColumn<String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<DateTime> get fetchedAt =>
      $composableBuilder(column: $table.fetchedAt, builder: (column) => column);
}

class $$LyricsCacheTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $LyricsCacheTable,
          LyricsCacheData,
          $$LyricsCacheTableFilterComposer,
          $$LyricsCacheTableOrderingComposer,
          $$LyricsCacheTableAnnotationComposer,
          $$LyricsCacheTableCreateCompanionBuilder,
          $$LyricsCacheTableUpdateCompanionBuilder,
          (
            LyricsCacheData,
            BaseReferences<_$AppDatabase, $LyricsCacheTable, LyricsCacheData>,
          ),
          LyricsCacheData,
          PrefetchHooks Function()
        > {
  $$LyricsCacheTableTableManager(_$AppDatabase db, $LyricsCacheTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$LyricsCacheTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$LyricsCacheTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$LyricsCacheTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> trackKey = const Value.absent(),
                Value<bool> found = const Value.absent(),
                Value<String?> plainLyrics = const Value.absent(),
                Value<String?> syncedLyrics = const Value.absent(),
                Value<bool> instrumental = const Value.absent(),
                Value<String> source = const Value.absent(),
                Value<DateTime> fetchedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => LyricsCacheCompanion(
                trackKey: trackKey,
                found: found,
                plainLyrics: plainLyrics,
                syncedLyrics: syncedLyrics,
                instrumental: instrumental,
                source: source,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String trackKey,
                Value<bool> found = const Value.absent(),
                Value<String?> plainLyrics = const Value.absent(),
                Value<String?> syncedLyrics = const Value.absent(),
                Value<bool> instrumental = const Value.absent(),
                Value<String> source = const Value.absent(),
                required DateTime fetchedAt,
                Value<int> rowid = const Value.absent(),
              }) => LyricsCacheCompanion.insert(
                trackKey: trackKey,
                found: found,
                plainLyrics: plainLyrics,
                syncedLyrics: syncedLyrics,
                instrumental: instrumental,
                source: source,
                fetchedAt: fetchedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$LyricsCacheTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $LyricsCacheTable,
      LyricsCacheData,
      $$LyricsCacheTableFilterComposer,
      $$LyricsCacheTableOrderingComposer,
      $$LyricsCacheTableAnnotationComposer,
      $$LyricsCacheTableCreateCompanionBuilder,
      $$LyricsCacheTableUpdateCompanionBuilder,
      (
        LyricsCacheData,
        BaseReferences<_$AppDatabase, $LyricsCacheTable, LyricsCacheData>,
      ),
      LyricsCacheData,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$SongsTableTableManager get songs =>
      $$SongsTableTableManager(_db, _db.songs);
  $$QueueItemsTableTableManager get queueItems =>
      $$QueueItemsTableTableManager(_db, _db.queueItems);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
  $$PairedControllersTableTableManager get pairedControllers =>
      $$PairedControllersTableTableManager(_db, _db.pairedControllers);
  $$RecentUrlsTableTableManager get recentUrls =>
      $$RecentUrlsTableTableManager(_db, _db.recentUrls);
  $$PlaylistsTableTableManager get playlists =>
      $$PlaylistsTableTableManager(_db, _db.playlists);
  $$PlaylistSongsTableTableManager get playlistSongs =>
      $$PlaylistSongsTableTableManager(_db, _db.playlistSongs);
  $$QueueStreamsTableTableManager get queueStreams =>
      $$QueueStreamsTableTableManager(_db, _db.queueStreams);
  $$OnlineHistoryTableTableManager get onlineHistory =>
      $$OnlineHistoryTableTableManager(_db, _db.onlineHistory);
  $$LyricsCacheTableTableManager get lyricsCache =>
      $$LyricsCacheTableTableManager(_db, _db.lyricsCache);
}
