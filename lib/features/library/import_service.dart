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
  final List<ImportFailure> failures = [];

  int get failed => failures.length;

  /// One-line summary for a snackbar.
  String get summary {
    final parts = <String>[
      if (added > 0) 'Added $added song${added == 1 ? '' : 's'}',
      if (duplicates > 0) '$duplicates already in your library',
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
  })  : _library = library,
        _extractor = extractor,
        _libraryDir = libraryDir,
        _artDir = artDir;

  final LibraryRepository _library;
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

  Future<ImportResult> importFolder(
    String folderPath, {
    ProgressCallback? onProgress,
  }) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) {
      throw ImportException("That folder couldn't be found.");
    }
    final files = await _scan(dir);
    final result = ImportResult();
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

  /// Removes a song from the library, and deletes its copied file and its art
  /// if nothing else uses them. Files the user referenced in place are never
  /// deleted.
  Future<void> removeSong(int id) async {
    final song = await _library.removeSong(id);
    if (song == null) return;

    final path = song.filePath;
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
