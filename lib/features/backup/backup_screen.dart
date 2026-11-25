import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/library_providers.dart';
import '../../providers/providers.dart';
import 'backup_models.dart';
import 'backup_service.dart';
import 'match_by_hand.dart';

/// Where backup files are saved to and read from (replaced in tests).
abstract class BackupPicker {
  /// Saves [bytes] as [fileName] where the user chooses; false if they cancelled.
  Future<bool> save(String fileName, Uint8List bytes);

  /// Lets the user choose a backup file; null if they cancelled.
  Future<Uint8List?> pickFile();

  /// Lets the user choose a folder; null if they cancelled.
  Future<String?> pickFolder();
}

class FilePickerBackupPicker implements BackupPicker {
  @override
  Future<bool> save(String fileName, Uint8List bytes) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Save the backup',
      fileName: fileName,
      bytes: bytes,
    );
    return path != null;
  }

  @override
  Future<Uint8List?> pickFile() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    if (r == null || r.files.isEmpty) return null;
    final f = r.files.single;
    if (f.bytes != null) return f.bytes;
    final path = f.path;
    return path == null ? null : File(path).readAsBytes();
  }

  @override
  Future<String?> pickFolder() => FilePicker.platform.getDirectoryPath();
}

final backupPickerProvider = Provider<BackupPicker>((ref) => FilePickerBackupPicker());

final backupServiceProvider = FutureProvider<BackupService>((ref) async {
  final import = await ref.watch(importServiceProvider.future);
  return BackupService(
    db: ref.watch(databaseProvider),
    settings: ref.watch(settingsRepositoryProvider),
    exclusions: import.exclusions,
    copiedSongsDir: import.libraryDirPath,
    artDir: import.artDirPath,
  );
});

/// How many covers there are and how big (for the switch's subtitle).
final backupArtSummaryProvider = FutureProvider.autoDispose<({int count, int bytes})>((ref) async {
  return (await ref.watch(backupServiceProvider.future)).artSummary();
});

/// Settings > Backup and restore: a file with the playlists, hearts, counts, lyrics and
/// settings (not the music), and putting one back, possibly on another phone.
class BackupScreen extends ConsumerStatefulWidget {
  const BackupScreen({super.key});

  @override
  ConsumerState<BackupScreen> createState() => _BackupScreenState();
}

class _BackupScreenState extends ConsumerState<BackupScreen> {
  bool _lyrics = true;
  bool _settings = true;
  bool _art = true;
  bool _activity = true;
  bool _history = true;
  bool _restoreHistory = true;
  bool _restoreArt = true;
  bool _busy = false;
  int _copies = 0;

  BackupData? _loaded;
  String? _root;
  bool _restoreLyrics = true;
  bool _restoreSettings = true;
  int _songsInLibrary = -1;

  @override
  void initState() {
    super.initState();
    _countCopies();
  }

  Future<void> _countCopies() async {
    try {
      final n = (await (await ref.read(backupServiceProvider.future)).copiedSongs()).length;
      if (mounted) setState(() => _copies = n);
    } catch (_) {}
  }

  /// Puts the songs added with "Add songs" in a folder the user picks, so they exist outside the app.
  Future<void> _exportCopies() async {
    final dir = await ref.read(backupPickerProvider).pickFolder();
    if (dir == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await (await ref.read(backupServiceProvider.future)).exportCopies(dir);
      _say(r.failed == 0
          ? 'Copied ${r.copied} song${r.copied == 1 ? '' : 's'} to the folder.'
          : 'Copied ${r.copied}; ${r.failed} could not be copied.');
    } catch (_) {
      _say("The songs couldn't be copied. Try another folder.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _say(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _makeBackup() async {
    setState(() => _busy = true);
    try {
      final service = await ref.read(backupServiceProvider.future);
      final data = await service.create(
          lyrics: _lyrics, settings: _settings, art: _art, activity: _activity, history: _history);
      final bytes = data.encode();
      final d = data.created;
      String two(int n) => n.toString().padLeft(2, '0');
      final name = 'RemoteTunes-${d.year}-${two(d.month)}-${two(d.day)}.rtbackup';
      final saved = await ref.read(backupPickerProvider).save(name, bytes);
      if (!mounted) return;
      if (!saved) {
        _say('Nothing was saved.');
      } else {
        await showDialog<void>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Backup saved'),
            content: Text(
              '$name\n\n${_describe(data)}\n\nSize: ${_size(bytes.length)}. '
              'Copy it to the other phone, then use "Restore from a backup" there.',
            ),
            actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
          ),
        );
      }
    } catch (_) {
      _say("The backup couldn't be saved. Try another folder.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseFile() async {
    setState(() => _busy = true);
    try {
      final bytes = await ref.read(backupPickerProvider).pickFile();
      if (bytes == null) return;
      final data = BackupData.decode(bytes);
      final songs = await (await ref.read(backupServiceProvider.future)).db.customSelect(
        'SELECT COUNT(*) AS c FROM songs',
      ).getSingle();
      var root = data.root.isNotEmpty && Directory(data.root).existsSync() ? data.root : null;
      if (!mounted) return;
      setState(() {
        _loaded = data;
        _root = root;
        _songsInLibrary = songs.read<int>('c');
      });
    } on BackupException catch (e) {
      _say(e.message);
    } catch (_) {
      _say("That file couldn't be opened.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseRoot() async {
    final dir = await ref.read(backupPickerProvider).pickFolder();
    if (dir != null && mounted) setState(() => _root = dir);
  }

  Future<void> _restore() async {
    final data = _loaded;
    if (data == null) return;
    setState(() => _busy = true);
    try {
      final service = await ref.read(backupServiceProvider.future);
      final picks = <int, int>{};
      while (true) {
        final report = await service.restore(
          data,
          newRoot: _root,
          includeLyrics: _restoreLyrics,
          includeSettings: _restoreSettings,
          includeArt: _restoreArt,
          includeHistory: _restoreHistory,
          picks: picks,
        );
        // The lists and the look may have changed.
        ref.invalidate(settingsProvider);
        if (!mounted) return;
        final again = await showDialog<bool>(
          context: context,
          builder: (_) => RestoreReportDialog(report: report),
        );
        if (again != true || !mounted) break;
        // Match the ones that were not found by hand, then restore again (nothing is done twice).
        final chosen = await showMatchByHand(
          context,
          library: ref.read(libraryRepositoryProvider),
          data: data,
          indexes: report.notFoundIndexes,
        );
        if (chosen == null || chosen.isEmpty) break;
        picks.addAll(chosen);
      }
      if (mounted) setState(() => _loaded = null);
    } catch (_) {
      _say("The backup couldn't be put back.");
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _size(int bytes) => bytes < 1024 * 1024
      ? '${(bytes / 1024).toStringAsFixed(0)} KB'
      : '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';

  static String _describe(BackupData d) {
    String n(int c, String one, [String? many]) => '$c ${c == 1 ? one : (many ?? '${one}s')}';
    return [
      n(d.playlists.length, 'playlist'),
      n(d.favorites, 'favorite'),
      n(d.withCounts, 'song with play counts', 'songs with play counts'),
      if (d.lyrics.isNotEmpty) n(d.lyrics.length, 'lyric'),
      if (d.leftOut > 0) n(d.leftOut, 'left-out folder or file', 'left-out folders and files'),
      if (d.settings.isNotEmpty) n(d.settings.length, 'setting'),
      if (d.art.isNotEmpty) n(d.art.length, 'cover'),
      if (d.edited > 0) n(d.edited, 'edited song info', 'edited song infos'),
      if (d.playLog.isNotEmpty) n(d.playLog.length, 'play in the history', 'plays in the history'),
    ].join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final loaded = _loaded;
    return Scaffold(
      appBar: AppBar(title: const Text('Backup and restore')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'A backup is a file with your playlists, favorites, play and skip counts, song info you '
              'edited, the folders you left out, lyrics, album art and settings. It does not hold your music. '
              'Use it to move to another phone that has the same music.',
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            Text('Back up', style: theme.textTheme.titleMedium),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Playlists, favorites and counts'),
              subtitle: const Text(
                  'Also play and skip counts, edited song info and the left-out list'),
              value: _activity,
              onChanged: (v) => setState(() => _activity = v),
            ),
            SwitchListTile(
              key: const Key('backup-history'),
              contentPadding: EdgeInsets.zero,
              title: const Text('Include play history'),
              subtitle: const Text('Each song played, when and for how long (for Insights)'),
              value: _history,
              onChanged: (v) => setState(() => _history = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Include lyrics'),
              value: _lyrics,
              onChanged: (v) => setState(() => _lyrics = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Include album art'),
              subtitle: Text(ref.watch(backupArtSummaryProvider).maybeWhen(
                  data: (a) => a.count == 0
                      ? 'No covers found'
                      : '${a.count} cover${a.count == 1 ? '' : 's'}, about ${_size(a.bytes)}',
                  orElse: () => 'Covers from the files and the art finder')),
              value: _art,
              onChanged: (v) => setState(() => _art = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Include settings'),
              subtitle: const Text('Look, equalizer, crossfade... (never keys or pairing)'),
              value: _settings,
              onChanged: (v) => setState(() => _settings = v),
            ),
            FilledButton.icon(
              onPressed: _busy ? null : _makeBackup,
              icon: const Icon(Icons.save_alt_rounded),
              label: const Text('Back up to a file'),
            ),
            TextButton(
              key: const Key('lyrics-art-only'),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                        _activity = false;
                        _history = false;
                        _settings = false;
                        _lyrics = true;
                        _art = true;
                      }),
              child: const Text('Choose lyrics and album art only'),
            ),
            const SizedBox(height: 4),
            Text(
              'Songs you added with "Add songs" are copies kept inside the app, so a backup cannot '
              'bring those songs back (only what you did with them).',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (_copies > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const Key('export-copies'),
                  onPressed: _busy ? null : _exportCopies,
                  icon: const Icon(Icons.drive_file_move_outline),
                  label: Text('Export $_copies copied song${_copies == 1 ? '' : 's'} to a folder'),
                ),
              ),
            const Divider(height: 40),
            Text('Restore from a backup', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text(
              'First add your music folder on this phone (Library > Add folder), so there are songs '
              'to match. Restoring only adds: nothing on this phone is deleted.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _busy ? null : _chooseFile,
              icon: const Icon(Icons.folder_open_rounded),
              label: const Text('Choose a backup file'),
            ),
            if (loaded != null) ...[
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loaded.created.millisecondsSinceEpoch == 0
                            ? 'Backup'
                            : 'Backup of ${loaded.created.year}-${loaded.created.month.toString().padLeft(2, '0')}-${loaded.created.day.toString().padLeft(2, '0')}',
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 4),
                      Text('${loaded.songs.length} songs · ${_describe(loaded)}'),
                      const SizedBox(height: 12),
                      Text('Where is your music on this phone?', style: theme.textTheme.labelLarge),
                      const SizedBox(height: 2),
                      Text(
                        loaded.root.isEmpty ? '' : 'On the old phone it was in ${loaded.root}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      Row(
                        children: [
                          Expanded(
                            child: Text(_root ?? 'Not chosen (songs are matched by their tags)',
                                key: const Key('restore-root'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis),
                          ),
                          TextButton(onPressed: _busy ? null : _chooseRoot, child: const Text('Choose')),
                        ],
                      ),
                      if (loaded.lyrics.isNotEmpty)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('Lyrics'),
                          value: _restoreLyrics,
                          onChanged: (v) => setState(() => _restoreLyrics = v ?? true),
                        ),
                      if (loaded.art.isNotEmpty)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text('Album art (${loaded.art.length} covers)'),
                          subtitle: const Text('Only for albums that have no picture here yet'),
                          value: _restoreArt,
                          onChanged: (v) => setState(() => _restoreArt = v ?? true),
                        ),
                      if (loaded.playLog.isNotEmpty)
                        CheckboxListTile(
                          key: const Key('restore-history'),
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text('Play history (${loaded.playLog.length} plays)'),
                          subtitle: const Text('Plays already in the history here are not added again'),
                          value: _restoreHistory,
                          onChanged: (v) => setState(() => _restoreHistory = v ?? true),
                        ),
                      if (loaded.settings.isNotEmpty)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: const Text('Settings'),
                          value: _restoreSettings,
                          onChanged: (v) => setState(() => _restoreSettings = v ?? true),
                        ),
                      if (_songsInLibrary == 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            'This phone has no songs yet. Add your music folder first, or nothing can '
                            'be matched.',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                          ),
                        ),
                      const SizedBox(height: 8),
                      FilledButton(
                        key: const Key('restore-button'),
                        onPressed: _busy ? null : _restore,
                        child: const Text('Restore'),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            if (_busy)
              const Padding(
                padding: EdgeInsets.only(top: 16),
                child: Center(child: CircularProgressIndicator()),
              ),
          ],
        ),
      ),
    );
  }
}

/// What a restore did, and which songs could not be found.
class RestoreReportDialog extends StatelessWidget {
  const RestoreReportDialog({super.key, required this.report});

  final RestoreReport report;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(String label, int n, {Color? color}) => n == 0
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Row(
              children: [
                Expanded(child: Text(label)),
                Text('$n', style: theme.textTheme.titleSmall?.copyWith(color: color)),
              ],
            ),
          );
    final r = report;
    return AlertDialog(
      title: const Text('Restored'),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row('Songs in the backup', r.songsInBackup),
              row('Found by their place', r.byPath, color: theme.colorScheme.primary),
              row('Found by their tags', r.byTags, color: theme.colorScheme.primary),
              row('Found by title and artist only', r.looseMatches),
              row('Matched by hand', r.picked, color: theme.colorScheme.primary),
              row('Not found on this phone', r.notFound.length, color: theme.colorScheme.error),
              const Divider(),
              row('Playlists made', r.playlistsCreated),
              row('Playlists merged into yours', r.playlistsMerged),
              row('Songs added to playlists', r.playlistSongsAdded),
              row('Favorites set', r.favoritesSet),
              row('Songs with play or skip counts', r.countsRestored),
              row('Left-out folders and files', r.leftOutAdded),
              row('Lyrics added', r.lyricsAdded),
              row('Plays added to the history', r.historyAdded),
              row('Album covers added', r.artRestored),
              row('Song info changed (edited by hand)', r.infoRestored),
              row('Settings applied', r.settingsApplied),
              if (r.notFound.isNotEmpty) ...[
                const Divider(),
                Text('Not found:', style: theme.textTheme.labelLarge),
                for (final n in r.notFound.take(15))
                  Text(n, maxLines: 1, overflow: TextOverflow.ellipsis),
                if (r.notFound.length > 15) Text('…and ${r.notFound.length - 15} more.'),
                const SizedBox(height: 6),
                Text(
                  'Add them to this phone (or tell me where the music is) and restore again: '
                  'what is already done is not repeated.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (r.notFoundIndexes.isNotEmpty)
          TextButton(
            key: const Key('match-by-hand'),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Match by hand'),
          ),
        FilledButton(onPressed: () => Navigator.pop(context, false), child: const Text('OK')),
      ],
    );
  }
}
