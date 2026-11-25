import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../data/repositories/library_repository.dart';
import 'import_exception.dart';
import 'metadata_extractor.dart';

export 'import_exception.dart';

class ImportFailure {
  const ImportFailure(this.fileName, this.reason);

  final String fileName;

  /// Plain-language reason, safe to show to the user.
  final String reason;
}

class ImportResult {
  int added = 0;
  int duplicates = 0;

  /// Songs left out because their folder (or file) is on the excluded list.
  int excluded = 0;

  /// Songs that were already in the library and were taken out because their
  /// folder was excluded.
  int removed = 0;

  /// Files and folders looked at (every supported song found).
  int found = 0;

  final List<ImportFailure> failures = [];

  int get failed => failures.length;

  /// One-line summary for a snackbar.
  String get summary {
    final parts = <String>[
      if (added > 0) 'Added $added song${added == 1 ? '' : 's'}',
      if (duplicates > 0) '$duplicates already in your library',
      if (excluded > 0) '$excluded excluded',
      if (removed > 0) '$removed removed',
      if (failed > 0) '$failed skipped',
    ];
    return parts.isEmpty ? 'No songs found' : parts.join(' · ');
  }
}

class ImportProgress {
  const ImportProgress(this.done, this.total, this.currentName);

  final int done;
  final int total;
  final String? currentName;
}

typedef ProgressCallback = void Function(ImportProgress progress);

/// A folder found under the one being added, with how many songs it holds
/// (counting the folders inside it).
class FolderNode {
  const FolderNode(this.path, this.name, this.depth, this.songCount);

  final String path;
  final String name;

  /// 1 for a folder directly inside the one chosen.
  final int depth;
  final int songCount;
}

/// What is inside a folder about to be added.
class FolderScan {
  const FolderScan(this.root, this.files, this.folders);

  final String root;
  final List<String> files;

  /// Every folder below [root], parents before their children.
  final List<FolderNode> folders;
}

/// Where the list of left-out folders and files is kept between runs.
abstract class ExclusionStore {
  Future<Set<String>> load();
  Future<void> save(Set<String> paths);
}

/// Keeps the list in memory only (tests).
class MemoryExclusionStore implements ExclusionStore {
  Set<String> paths = {};

  @override
  Future<Set<String>> load() async => {...paths};

  @override
  Future<void> save(Set<String> value) async => paths = {...value};
}

/// Imports audio into the library.
///
///  * [importFiles]: files chosen with the file picker are **copied** into
///    app-private storage. The picker only gives temporary cache copies, which
///    Android may delete, so the library keeps its own permanent copy.
///  * [importFolder]: files are **referenced in place** (needs the music
///    permission). If a file later disappears it is shown as unavailable.
class LibraryImportService {
  LibraryImportService({
    required LibraryRepository library,
    required MetadataExtractor extractor,
    required Directory libraryDir,
    required Directory artDir,
    ExclusionStore? exclusions,
  })  : _library = library,
        _exclusions = exclusions ?? MemoryExclusionStore(),
        _extractor = extractor,
        _libraryDir = libraryDir,
        _artDir = artDir;

  final LibraryRepository _library;
  final ExclusionStore _exclusions;

  /// The left-out list (for the backup).
  ExclusionStore get exclusions => _exclusions;

  /// Where songs added with "Add songs" are copied to.
  String get libraryDirPath => _libraryDir.path;
  final MetadataExtractor _extractor;
  final Directory _libraryDir;
  final Directory _artDir;
  static const _uuid = Uuid();

  Future<ImportResult> importFiles(
    List<String> sourcePaths, {
    ProgressCallback? onProgress,
  }) async {
    final result = ImportResult();
    await _libraryDir.create(recursive: true);
    for (var i = 0; i < sourcePaths.length; i++) {
      final path = sourcePaths[i];
      onProgress?.call(ImportProgress(i, sourcePaths.length, p.basename(path)));
      if (!isSupportedAudio(path)) {
        result.failures.add(ImportFailure(
            p.basename(path), 'This is not a supported audio format.'));
        continue;
      }
      await _importOne(path, copy: true, result: result);
    }
    onProgress?.call(ImportProgress(sourcePaths.length, sourcePaths.length, null));
    return result;
  }

  /// What is inside [folderPath]: its songs and the folders below it (for the
  /// "choose what to add" step). Reads no tags, so it is quick.
  Future<FolderScan> scanFolder(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) {
      throw ImportException("That folder couldn't be found.");
    }
    final files = await _scan(dir);
    final counts = <String, int>{};
    for (final f in files) {
      var parent = p.dirname(f);
      while (parent != dir.path && p.isWithin(dir.path, parent)) {
        counts[parent] = (counts[parent] ?? 0) + 1;
        parent = p.dirname(parent);
      }
    }
    final paths = counts.keys.toList()..sort();
    return FolderScan(dir.path, files, [
      for (final path in paths)
        FolderNode(path, p.basename(path), p.split(p.relative(path, from: dir.path)).length,
            counts[path]!),
    ]);
  }

  /// The folders and files that are left out of the library.
  Future<Set<String>> excludedPaths() => _exclusions.load();

  /// Takes a folder or file off the left-out list (it is added the next time
  /// its folder is added).
  Future<void> includeAgain(String path) async {
    final all = await _exclusions.load();
    if (all.remove(path)) await _exclusions.save(all);
  }

  static bool _isExcluded(String path, Set<String> excluded) =>
      excluded.any((e) => path == e || p.isWithin(e, path));

  /// Adds the songs in [folderPath] (referenced in place).
  ///
  /// [exclude] is the folders the user unticked under [folderPath]; it replaces
  /// what was left out under that folder before, and is remembered, so adding
  /// the folder again skips them too. With [removeExcluded], songs already in
  /// the library that sit in a left-out folder are taken out.
  Future<ImportResult> importFolder(
    String folderPath, {
    Set<String>? exclude,
    bool removeExcluded = false,
    ProgressCallback? onProgress,
  }) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) {
      throw ImportException("That folder couldn't be found.");
    }
    final stored = await _exclusions.load();
    var excluded = stored;
    if (exclude != null) {
      excluded = {
        for (final e in stored)
          if (e != dir.path && !p.isWithin(dir.path, e)) e,
        ...exclude,
      };
      if (excluded.length != stored.length || !excluded.containsAll(stored)) {
        await _exclusions.save(excluded);
      }
    }
    final all = await _scan(dir);
    final result = ImportResult()..found = all.length;
    final files = <String>[];
    for (final f in all) {
      if (_isExcluded(f, excluded)) {
        result.excluded++;
      } else {
        files.add(f);
      }
    }
    if (removeExcluded && excluded.isNotEmpty) {
      for (final song in await _library.localSongFiles()) {
        if (p.isWithin(dir.path, song.path) && _isExcluded(song.path, excluded)) {
          await removeSong(song.id, remember: false);
          result.removed++;
        }
      }
    }
    for (var i = 0; i < files.length; i++) {
      onProgress?.call(ImportProgress(i, files.length, p.basename(files[i])));
      await _importOne(files[i], copy: false, result: result);
    }
    onProgress?.call(ImportProgress(files.length, files.length, null));
    return result;
  }

  /// Audio files under [dir], skipping hidden folders and unreadable subfolders.
  Future<List<String>> _scan(Directory dir) async {
    final found = <String>[];
    var sawError = false;
    final stream = dir.list(recursive: true, followLinks: false);
    final done = Completer<void>();
    stream.listen(
      (entity) {
        if (entity is! File) return;
        final rel = p.relative(entity.path, from: dir.path);
        final hidden = p.split(rel).any((part) => part.startsWith('.'));
        if (!hidden && isSupportedAudio(entity.path)) found.add(entity.path);
      },
      onError: (Object _) => sawError = true,
      onDone: done.complete,
      cancelOnError: false,
    );
    await done.future;
    if (found.isEmpty && sawError) {
      throw ImportException(
        "RemoteTunes isn't allowed to read that folder. Allow access to "
        'music and audio, then try again.',
      );
    }
    found.sort();
    return found;
  }

  Future<void> _importOne(
    String path, {
    required bool copy,
    required ImportResult result,
  }) async {
    final name = p.basename(path);
    final file = File(path);

    final int size;
    try {
      size = await file.length();
    } on FileSystemException {
      result.failures.add(ImportFailure(name, "Couldn't open this file."));
      return;
    }
    if (size == 0) {
      result.failures.add(ImportFailure(name, 'This file is empty.'));
      return;
    }

    if (!copy && await _library.findByPath(path) != null) {
      result.duplicates++;
      return;
    }

    ExtractedMetadata meta;
    try {
      meta = await _extractor.extract(path);
    } catch (_) {
      // Unreadable tags: still import using the file name. A file that cannot
      // actually play is skipped at playback time.
      meta = const ExtractedMetadata();
    }

    final title = meta.title ?? p.basenameWithoutExtension(path);
    final artist = meta.artist ?? unknownArtist;
    final album = meta.album ?? unknownAlbum;

    if (await _library.hasDuplicate(
      title: title,
      artist: artist,
      album: album,
      durationSeconds: meta.durationSeconds,
      fileSizeBytes: size,
    )) {
      result.duplicates++;
      return;
    }

    var storedPath = path;
    String? copiedTo;
    if (copy) {
      copiedTo = p.join(_libraryDir.path, '${_uuid.v4()}_${_safeName(name)}');
      try {
        await file.copy(copiedTo);
      } on FileSystemException {
        result.failures.add(ImportFailure(
          name,
          "Couldn't copy this file. The phone may be out of storage.",
        ));
        return;
      }
      storedPath = copiedTo;
    }

    String? artPath;
    try {
      artPath = await _storeArt(meta, artist, album);
    } catch (_) {
      artPath = null; // Missing art is never a reason to skip a song.
    }

    try {
      await _library.addSong(
        title: title,
        artist: artist,
        album: album,
        filePath: storedPath,
        durationSeconds: meta.durationSeconds,
        trackNumber: meta.trackNumber,
        albumArtPath: artPath,
        fileSizeBytes: size,
        mimeType: _mimeFor(path),
        albumArtist: meta.albumArtist,
        genre: meta.genre,
        year: meta.year,
        replayGainDb: meta.replayGainDb,
        albumGainDb: meta.albumGainDb,
        composer: meta.composer,
      );
      result.added++;
    } catch (_) {
      if (copiedTo != null) {
        try {
          await File(copiedTo).delete();
        } catch (_) {}
      }
      result.failures.add(ImportFailure(name, "Couldn't save this song."));
    }
  }

  /// Album art is stored once per artist+album and shared by its songs.
  Future<String?> _storeArt(
      ExtractedMetadata meta, String artist, String album) async {
    final bytes = meta.artBytes;
    if (bytes == null) return null;
    final existing = await _library.albumArtFor(artist, album);
    if (existing != null && await File(existing).exists()) return existing;

    await _artDir.create(recursive: true);
    final ext = (meta.artMimeType ?? '').contains('png') ? 'png' : 'jpg';
    final path = p.join(_artDir.path, '${_uuid.v4()}.$ext');
    await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  /// Reads the tags again for every song in the library and fills in the album
  /// artist, genre and year (songs added before those were kept have none).
  /// Titles, artists, albums and covers are not changed. Returns how many songs
  /// got at least one of them.
  Future<int> refreshTags({ProgressCallback? onProgress}) async {
    final files = await _library.localSongFiles();
    var filled = 0;
    for (var i = 0; i < files.length; i++) {
      final f = files[i];
      onProgress?.call(ImportProgress(i, files.length, p.basename(f.path)));
      try {
        if (!await File(f.path).exists()) continue;
        final meta = await _extractor.extract(f.path);
        if (meta.albumArtist != null ||
            meta.genre != null ||
            meta.year != null ||
            meta.replayGainDb != null ||
            meta.albumGainDb != null ||
            meta.composer != null) {
          await _library.updateSongTags(f.id,
              albumArtist: meta.albumArtist,
              genre: meta.genre,
              year: meta.year,
              replayGainDb: meta.replayGainDb,
              albumGainDb: meta.albumGainDb,
              composer: meta.composer);
          filled++;
        }
      } catch (_) {
        // One unreadable file does not stop the rest.
      }
    }
    onProgress?.call(ImportProgress(files.length, files.length, null));
    return filled;
  }

  /// Removes a song from the library, and deletes its copied file and its art
  /// if nothing else uses them. Files the user referenced in place are never
  /// deleted.
  ///
  /// A file referenced in place is also put on the left-out list, so adding its
  /// folder again does not bring it back ([remember] false: not now).
  Future<void> removeSong(int id, {bool remember = true}) async {
    final song = await _library.removeSong(id);
    if (song == null) return;

    final path = song.filePath;
    if (remember && path != null && !p.isWithin(_libraryDir.path, path)) {
      final all = await _exclusions.load();
      if (all.add(path)) await _exclusions.save(all);
    }
    if (path != null && p.isWithin(_libraryDir.path, path)) {
      await _tryDelete(path);
    }
    final art = song.albumArtPath;
    if (art != null && await _library.songsUsingArt(art) == 0) {
      await _tryDelete(art);
    }
  }

  Future<void> _tryDelete(String path) async {
    try {
      await File(path).delete();
    } catch (_) {}
  }

  static String _safeName(String name) =>
      name.replaceAll(RegExp(r'[^\w.\- ]'), '_');

  static String? _mimeFor(String path) => switch (extensionOf(path)) {
        'mp3' => 'audio/mpeg',
        'm4a' => 'audio/mp4',
        'aac' => 'audio/aac',
        'flac' => 'audio/flac',
        'wav' => 'audio/wav',
        'ogg' || 'opus' => 'audio/ogg',
        _ => null,
      };
}
