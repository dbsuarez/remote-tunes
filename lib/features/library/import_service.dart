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

  /// Songs whose file was moved: found again at the new place, so they are the same
  /// song as before (playlists, hearts and counts kept).
  int relinked = 0;

  /// Songs left out because their folder (or file) is on the excluded list.
  int excluded = 0;

  /// Songs that were already in the library and were taken out because their
  /// folder was excluded.
  int removed = 0;

  /// Files and folders looked at (every supported song found).
  int found = 0;

  /// How many remembered folders a rescan went through.
  int foldersScanned = 0;

  /// Remembered folders that could not be read (storage not connected?): their songs are
  /// not called missing.
  final List<String> unreachable = [];

  /// Songs of the library whose file is not there (after moved files were followed).
  final List<MissingSong> missing = [];

  /// How many songs of the scanned folders were checked for a missing file.
  int checked = 0;

  /// More than half of the checked songs are missing: probably the storage is not there, not
  /// the songs deleted.
  bool get mostMissing => checked >= 10 && missing.length * 2 > checked;

  final List<ImportFailure> failures = [];

  int get failed => failures.length;

  /// One-line summary for a snackbar.
  String get summary {
    final parts = <String>[
      if (added > 0) 'Added $added song${added == 1 ? '' : 's'}',
      if (relinked > 0) '$relinked moved',
      if (duplicates > 0) '$duplicates already in your library',
      if (excluded > 0) '$excluded excluded',
      if (removed > 0) '$removed removed',
      if (failed > 0) '$failed skipped',
    ];
    return parts.isEmpty ? 'No songs found' : parts.join(' · ');
  }
}

/// A song of the library whose file is gone.
class MissingSong {
  const MissingSong({required this.id, required this.title, required this.artist, required this.path});

  final int id;
  final String title;
  final String artist;
  final String path;
}

/// A folder that was added to the library, remembered so it can be rescanned in one tap.
class MusicFolder {
  const MusicFolder({
    required this.path,
    this.lastScan,
    this.knownDirs = const {},
    this.songCount = 0,
    this.audiobooks = false,
  });

  final String path;
  final DateTime? lastScan;

  /// An audiobook folder: every song in it is an audiobook, and it is scanned apart from the music.
  final bool audiobooks;

  /// The folders (relative to [path], '' for the folder itself) that were seen holding songs the
  /// last time, so a folder that appears later can be asked about.
  final Set<String> knownDirs;
  final int songCount;

  Map<String, dynamic> toJson() => {
        'path': path,
        if (lastScan != null) 'last': lastScan!.millisecondsSinceEpoch ~/ 1000,
        'dirs': knownDirs.toList()..sort(),
        'count': songCount,
        if (audiobooks) 'books': true,
      };

  static MusicFolder? fromJson(Object? j) {
    if (j is! Map || j['path'] is! String || (j['path'] as String).isEmpty) return null;
    final last = j['last'];
    return MusicFolder(
      path: j['path'] as String,
      lastScan: last is num ? DateTime.fromMillisecondsSinceEpoch(last.toInt() * 1000) : null,
      knownDirs: j['dirs'] is List ? {for (final d in j['dirs'] as List) if (d is String) d} : {},
      songCount: j['count'] is num ? (j['count'] as num).toInt() : 0,
      audiobooks: j['books'] == true,
    );
  }
}

/// Where the remembered folders are kept between runs.
abstract class MusicFoldersStore {
  Future<List<MusicFolder>> load();
  Future<void> save(List<MusicFolder> folders);
}

/// Keeps them in memory only (tests).
class MemoryMusicFoldersStore implements MusicFoldersStore {
  List<MusicFolder> folders = [];

  @override
  Future<List<MusicFolder>> load() async => [...folders];

  @override
  Future<void> save(List<MusicFolder> value) async => folders = [...value];
}

/// A folder that is new since the last scan (and not left out).
class NewFolder {
  const NewFolder(this.path, this.name, this.songCount);

  final String path;
  final String name;
  final int songCount;
}

/// What a rescan is about to do: which folders it will go through, which it cannot reach, and
/// which new folders it would like to ask about first.
class RescanPlan {
  const RescanPlan({required this.folders, required this.unreachable, required this.newFolders});

  final List<MusicFolder> folders;
  final List<String> unreachable;
  final List<NewFolder> newFolders;
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
    MusicFoldersStore? folders,
  })  : _library = library,
        _exclusions = exclusions ?? MemoryExclusionStore(),
        _folders = folders ?? MemoryMusicFoldersStore(),
        _extractor = extractor,
        _libraryDir = libraryDir,
        _artDir = artDir;

  final LibraryRepository _library;
  final ExclusionStore _exclusions;
  final MusicFoldersStore _folders;

  /// Where the remembered folders are kept (the backup reads and writes the audiobook ones).
  MusicFoldersStore get foldersStore => _folders;

  /// The left-out list (for the backup).
  ExclusionStore get exclusions => _exclusions;

  /// Where songs added with "Add songs" are copied to.
  String get libraryDirPath => _libraryDir.path;

  /// Where cover pictures are kept.
  String get artDirPath => _artDir.path;
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

  /// A rule that leaves out files by name is kept in the same list, as `glob:<pattern>`.
  static const rulePrefix = 'glob:';

  /// Does [fileName] (with its extension) match the rule [pattern]? `*` is any text and `?` one
  /// character; a pattern with neither matches any name that contains it. Capitals do not matter.
  static bool matchesRule(String pattern, String fileName) {
    final rule = pattern.trim().toLowerCase();
    if (rule.isEmpty) return false;
    final name = fileName.toLowerCase();
    if (!rule.contains('*') && !rule.contains('?')) return name.contains(rule);
    final body = rule.split('').map((c) => c == '*' ? '.*' : c == '?' ? '.' : RegExp.escape(c)).join();
    return RegExp('^$body\$').hasMatch(name);
  }

  static bool _isExcluded(String path, Set<String> excluded) => excluded.any((e) => e.startsWith(rulePrefix)
      ? matchesRule(e.substring(rulePrefix.length), p.basename(path))
      : path == e || p.isWithin(e, path));

  /// The rules that leave files out by name (see [matchesRule]).
  Future<List<String>> nameRules() async => [
        for (final e in await _exclusions.load())
          if (e.startsWith(rulePrefix)) e.substring(rulePrefix.length),
      ]..sort();

  /// Adds a rule. False if it is empty or already there.
  Future<bool> addNameRule(String pattern) async {
    var rule = pattern.trim();
    if (rule.length > 80) rule = rule.substring(0, 80);
    if (rule.isEmpty) return false;
    final all = await _exclusions.load();
    if (!all.add('$rulePrefix$rule')) return false;
    await _exclusions.save(all);
    return true;
  }

  Future<void> removeNameRule(String pattern) => includeAgain('$rulePrefix$pattern');

  /// The songs in the library whose file name matches the rule.
  Future<List<({int id, String path})>> songsMatchingRule(String pattern) async => [
        for (final s in await _library.localSongFiles())
          if (matchesRule(pattern, p.basename(s.path))) s,
      ];

  /// Takes the songs that match the rule out of the library (their files stay; the rule keeps them
  /// from coming back). Returns how many.
  Future<int> removeSongsMatchingRule(String pattern) async {
    final songs = await songsMatchingRule(pattern);
    for (final s in songs) {
      await removeSong(s.id, remember: false);
    }
    return songs.length;
  }

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
    bool audiobooks = false,
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
    // Music never takes in what lives in an audiobook folder (even one inside the music folder).
    final bookRoots = audiobooks
        ? const <String>[]
        : [for (final f in await _folders.load()) if (f.audiobooks && f.path != dir.path) f.path];
    final result = ImportResult()..found = all.length;
    final files = <String>[];
    for (final f in all) {
      if (bookRoots.any((r) => p.isWithin(r, f))) {
        result.found--;
      } else if (_isExcluded(f, excluded)) {
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
    // Everything in an audiobook folder is an audiobook, also what was already in the library.
    if (audiobooks) {
      final ids = [
        for (final s in await _library.localSongFiles())
          if (p.isWithin(dir.path, s.path)) s.id,
      ];
      await _library.setAudiobook(ids, true);
    }
    await _remember(dir.path, all, audiobooks: audiobooks);
    return result;
  }

  // ------------------------------------------------------------- music folders

  /// The folders that were added, for the one-tap rescan.
  Future<List<MusicFolder>> musicFolders() async =>
      (await _folders.load())..sort((a, b) => a.path.compareTo(b.path));

  /// Stops remembering a folder (the songs already in the library stay).
  Future<void> forgetFolder(String path) async {
    final all = await _folders.load();
    all.removeWhere((f) => f.path == path);
    await _folders.save(all);
  }

  /// The folders (relative to [root], '' for the root itself) that hold [files].
  static Set<String> _dirsOf(String root, Iterable<String> files) {
    final dirs = <String>{''};
    for (final f in files) {
      var parent = p.dirname(f);
      while (parent != root && p.isWithin(root, parent)) {
        dirs.add(p.relative(parent, from: root));
        parent = p.dirname(parent);
      }
    }
    return dirs;
  }

  /// Remembers [root] (and what it held), so it can be rescanned later.
  Future<void> _remember(String root, List<String> files, {bool audiobooks = false}) async {
    final all = await _folders.load();
    // Already inside a remembered folder of the same kind: that one covers it.
    if (all.any((f) => f.audiobooks == audiobooks && f.path != root && p.isWithin(f.path, root))) return;
    // It holds folders of the same kind that were remembered on their own: it covers them now.
    all.removeWhere((f) => f.audiobooks == audiobooks && f.path != root && p.isWithin(root, f.path));
    all.removeWhere((f) => f.path == root);
    all.add(MusicFolder(
      path: root,
      lastScan: DateTime.now(),
      knownDirs: _dirsOf(root, files),
      songCount: files.length,
      audiobooks: audiobooks,
    ));
    await _folders.save(all);
  }

  /// Looks through the remembered folders without changing anything: which can be reached, and
  /// which folders are new since the last scan (so they can be asked about).
  Future<RescanPlan> planRescan({bool audiobooks = false}) async {
    final stored = await _exclusions.load();
    final reachable = <MusicFolder>[];
    final unreachable = <String>[];
    final fresh = <NewFolder>[];
    for (final f in await musicFolders()) {
      // Music folders and audiobook folders are scanned apart.
      if (f.audiobooks != audiobooks) continue;
      final dir = Directory(f.path);
      if (!await dir.exists()) {
        unreachable.add(f.path);
        continue;
      }
      reachable.add(f);
      final List<String> files;
      try {
        files = await _scan(dir);
      } on ImportException {
        unreachable.add(f.path);
        reachable.remove(f);
        continue;
      }
      // Folders seen before were asked about already; the rest are new (unless left out).
      if (f.knownDirs.isEmpty) continue;
      final counts = <String, int>{};
      for (final file in files) {
        if (_isExcluded(file, stored)) continue;
        final rel = p.relative(p.dirname(file), from: f.path);
        counts[rel == '.' ? '' : rel] = (counts[rel == '.' ? '' : rel] ?? 0) + 1;
      }
      for (final e in counts.entries) {
        if (e.key.isEmpty || f.knownDirs.contains(e.key)) continue;
        // A new folder inside another new folder is asked about as the outer one.
        final parent = p.dirname(e.key);
        if (parent != '.' && counts.containsKey(parent) && !f.knownDirs.contains(parent)) continue;
        fresh.add(NewFolder(p.join(f.path, e.key), p.basename(e.key), e.value));
      }
    }
    fresh.sort((a, b) => a.path.compareTo(b.path));
    return RescanPlan(folders: reachable, unreachable: unreachable, newFolders: fresh);
  }

  /// Rescans every folder of [plan]: new songs are added, moved songs followed, the left-out list
  /// respected. [leaveOut] are new folders the user did not want: they are left out (and
  /// remembered as such). The result lists the songs whose file is gone.
  Future<ImportResult> rescan(
    RescanPlan plan, {
    Set<String> leaveOut = const {},
    ProgressCallback? onProgress,
  }) async {
    if (leaveOut.isNotEmpty) {
      final all = await _exclusions.load();
      all.addAll(leaveOut);
      await _exclusions.save(all);
    }
    final total = ImportResult();
    total.unreachable.addAll(plan.unreachable);
    for (final f in plan.folders) {
      final r = await importFolder(f.path, audiobooks: f.audiobooks, onProgress: onProgress);
      total
        ..added += r.added
        ..duplicates += r.duplicates
        ..relinked += r.relinked
        ..excluded += r.excluded
        ..removed += r.removed
        ..found += r.found
        ..foldersScanned += 1;
      total.failures.addAll(r.failures);
    }
    // Songs of these folders whose file is not there (moved ones were followed above).
    final roots = [for (final f in plan.folders) f.path];
    for (final s in await _library.localSongsDetail()) {
      if (!roots.any((r) => p.isWithin(r, s.path))) continue;
      total.checked++;
      if (!await File(s.path).exists()) {
        total.missing.add(MissingSong(id: s.id, title: s.title, artist: s.artist, path: s.path));
      }
    }
    return total;
  }

  /// Takes songs out of the library (their files were gone). They are not put on the left-out list.
  Future<void> removeSongs(Iterable<int> ids) async {
    for (final id in ids) {
      await removeSong(id, remember: false);
    }
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

    final same = await _library.duplicatesOf(
      title: title,
      artist: artist,
      album: album,
      durationSeconds: meta.durationSeconds,
      fileSizeBytes: size,
    );
    if (same.isNotEmpty) {
      if (!copy) {
        // A song we know whose file is no longer where it was, and this file is the
        // same song: it was moved. Follow it instead of calling it a duplicate.
        for (final d in same) {
          final old = d.path;
          if (old != null && !File(old).existsSync()) {
            await _library.relinkSong(d.id, path);
            result.relinked++;
            return;
          }
        }
      }
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

  /// Finds songs whose title, artist, album or track number were changed in the library only
  /// (before changes were flagged, `v1.0.7`): they differ from the tags still in their file. They are
  /// flagged as edited, so the next backup carries them. Songs whose file has no such tag, or
  /// cannot be read, are left alone. Returns how many songs were flagged.
  Future<int> findEditedSongs({ProgressCallback? onProgress}) async {
    String norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    bool known(String? s) {
      final t = (s ?? '').trim().toLowerCase();
      return t.isNotEmpty && !t.startsWith('unknown');
    }

    // The library says something the file does not (a different value, or none in the file).
    bool differs(String? inLibrary, String? inFile) {
      if (!known(inLibrary)) return false;
      if (inFile == null || inFile.trim().isEmpty) return true;
      return norm(inLibrary!) != norm(inFile);
    }

    final rows = await _library.songsToCheckForEdits();
    final edited = <int>[];
    for (var i = 0; i < rows.length; i++) {
      final r = rows[i];
      onProgress?.call(ImportProgress(i, rows.length, p.basename(r.path)));
      try {
        if (!await File(r.path).exists()) continue;
        final meta = await _extractor.extract(r.path);
        // A title the file does not have is the file name (the import's fallback): not an edit.
        final titleEdited = meta.title != null && norm(meta.title!) != norm(r.title) ||
            meta.title == null && norm(r.title) != norm(p.basenameWithoutExtension(r.path));
        final trackEdited = r.track != null && meta.trackNumber != r.track;
        if (titleEdited || differs(r.artist, meta.artist) || differs(r.album, meta.album) || trackEdited) {
          edited.add(r.id);
        }
      } catch (_) {
        // One unreadable file does not stop the rest.
      }
    }
    await _library.markInfoEdited(edited);
    onProgress?.call(ImportProgress(rows.length, rows.length, null));
    return edited.length;
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
