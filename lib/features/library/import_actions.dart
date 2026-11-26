import 'package:file_picker/file_picker.dart';
import '../../core/screen_awake.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/permissions.dart';
import '../../providers/connection_providers.dart' show playerCoreProvider;
import '../../providers/library_providers.dart';
import '../music/music_source.dart';
import 'folder_browser.dart';
import 'folder_choice.dart';
import 'import_service.dart';

/// Picks audio files with the system picker and imports (copies) them.
/// Returns true if anything was added.
Future<bool> pickAndImportFiles(BuildContext context, WidgetRef ref) async {
  final FilePickerResult? picked;
  try {
    picked = await FilePicker.platform.pickFiles(
      type: FileType.audio,
      allowMultiple: true,
    );
  } catch (_) {
    if (context.mounted) _snack(context, "Couldn't open the file picker.");
    return false;
  }
  if (picked == null) return false; // cancelled
  final paths = [for (final f in picked.files) if (f.path != null) f.path!];
  if (paths.isEmpty) return false;
  if (!context.mounted) return false;

  final service = await ref.read(importServiceProvider.future);
  if (!context.mounted) return false;
  return _runImport(
      context, (onProgress) => service.importFiles(paths, onProgress: onProgress));
}

/// Picks a folder and imports every audio file inside it (referenced in
/// place, so it needs access to the user's music).
Future<bool> pickAndImportFolder(BuildContext context, WidgetRef ref) async {
  final permissions = ref.read(permissionsProvider);
  final access = await permissions.ensureMusicAccess();
  if (!context.mounted) return false;
  if (access != PermissionOutcome.granted) {
    await _explainPermission(
      context,
      permissions,
      permanent: access == PermissionOutcome.permanentlyDenied,
    );
    return false;
  }

  final folder = await showFolderBrowser(context,
      title: 'Add a music folder', systemPicker: () => FilePicker.platform.getDirectoryPath());
  if (folder == null || !context.mounted) return false;

  final service = await ref.read(importServiceProvider.future);
  if (!context.mounted) return false;

  // Look inside first, so folders can be left out.
  final FolderScan scan;
  try {
    scan = await service.scanFolder(folder);
  } catch (e) {
    if (context.mounted) _snack(context, friendlyError(e));
    return false;
  }
  if (!context.mounted) return false;
  final stored = await service.excludedPaths();
  Set<String>? exclude;
  var removeExisting = false;
  if (scan.folders.isNotEmpty || stored.isNotEmpty || scan.files.length > 1) {
    final existing = (await ref.read(libraryRepositoryProvider).localSongFiles())
        .where((s) => p.isWithin(folder, s.path))
        .length;
    if (!context.mounted) return false;
    final choice = await showFolderChoice(context,
        scan: scan, alreadyExcluded: stored, alreadyInLibrary: existing);
    if (choice == null || !context.mounted) return false;
    exclude = choice.excluded;
    removeExisting = choice.removeExisting;
  }
  if (!context.mounted) return false;
  return _runImport(
      context,
      (onProgress) => service.importFolder(folder,
          exclude: exclude, removeExcluded: removeExisting, onProgress: onProgress));
}

void _snack(BuildContext context, String message) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}

Future<void> _explainPermission(
  BuildContext context,
  AppPermissions permissions, {
  required bool permanent,
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Allow access to music'),
      content: Text(
        permanent
            ? 'To add a whole folder, RemoteTunes needs permission to read '
                'music on this phone. Open Settings, choose Permissions, and '
                'allow music and audio.\n\nYou can still add individual songs '
                'without this permission.'
            : 'To add a whole folder, RemoteTunes needs permission to read '
                'music on this phone.\n\nYou can still add individual songs '
                'without this permission.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Not now'),
        ),
        if (permanent)
          FilledButton(
            onPressed: () {
              permissions.openSettings();
              Navigator.pop(ctx);
            },
            child: const Text('Open Settings'),
          ),
      ],
    ),
  );
}

/// Looks for songs whose info was edited in the library before edits were flagged (it differs from the
/// tags in the file) and flags them, so the next backup carries them. Shows the progress card.
Future<void> findEditedSongsAction(BuildContext context, WidgetRef ref) async {
  final service = await ref.read(importServiceProvider.future);
  if (!context.mounted) return;
  final progress = ValueNotifier<ImportProgress?>(null);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: _ProgressDialog(progress: progress, title: 'Looking for edited songs'),
    ),
  );
  int? found;
  Object? error;
  try {
    found = await ScreenAwake.during(() => service.findEditedSongs(onProgress: (p) => progress.value = p));
  } catch (e) {
    error = e;
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  progress.dispose();
  if (!context.mounted) return;
  _snack(
    context,
    error != null
        ? friendlyError(error)
        : found == 0
            ? 'No songs found whose info differs from their file.'
            : 'Flagged $found song${found == 1 ? '' : 's'} as edited: the next backup carries them.',
  );
}

/// Reads the tags of every song again to fill in genres, years and album
/// artists (songs added before those were kept have none). Shows the same
/// fixed-size progress card as adding music.
Future<void> refreshLibraryTags(BuildContext context, WidgetRef ref) async {
  final service = await ref.read(importServiceProvider.future);
  if (!context.mounted) return;
  final progress = ValueNotifier<ImportProgress?>(null);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: _ProgressDialog(progress: progress, title: 'Updating tags'),
    ),
  );
  int? filled;
  Object? error;
  try {
    filled = await ScreenAwake
        .during(() => service.refreshTags(onProgress: (p) => progress.value = p));
  } catch (e) {
    error = e;
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  progress.dispose();
  if (!context.mounted) return;
  _snack(
    context,
    error != null
        ? friendlyError(error)
        : filled == 0
            ? 'No new tags found in the files.'
            : 'Updated the tags of $filled song${filled == 1 ? '' : 's'}.',
  );
}

Future<bool> _runImport(
  BuildContext context,
  Future<ImportResult> Function(ProgressCallback onProgress) job,
) async {
  final result = await _runJob(context, job);
  return result != null && result.added > 0;
}

/// Runs an adding job behind the progress card and shows its report. Null if it failed.
Future<ImportResult?> _runJob(
  BuildContext context,
  Future<ImportResult> Function(ProgressCallback onProgress) job, {
  String title = 'Adding music',
}) async {
  final progress = ValueNotifier<ImportProgress?>(null);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: _ProgressDialog(progress: progress, title: title),
    ),
  );

  ImportResult? result;
  Object? error;
  try {
    // The screen stays on, so the phone does not lock and stall the import.
    result = await ScreenAwake.during(() => job((step) => progress.value = step));
  } catch (e) {
    error = e;
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  progress.dispose();
  if (!context.mounted) return result;

  if (error != null || result == null) {
    _snack(context, friendlyError(error ?? 'error'));
    return null;
  }
  // A report of what happened (instead of a one-line note).
  await showDialog<void>(context: context, builder: (_) => ImportReportDialog(result: result!));
  return result;
}

/// Tells the player which songs are audiobooks now (after folders were added or scanned).
Future<void> _refreshAudiobooks(WidgetRef ref) async {
  // Only if the player is already running (it reads the list itself when it starts).
  if (!ref.exists(playerCoreProvider)) return;
  try {
    await (await ref.read(playerCoreProvider.future)).audiobooks?.load();
  } catch (_) {}
}

/// Picks a folder of audiobooks and adds it: every song in it is an audiobook. Add as many
/// folders as you like (they can be anywhere on the phone). Returns true if anything was added.
Future<bool> pickAndImportAudiobookFolder(BuildContext context, WidgetRef ref) async {
  final permissions = ref.read(permissionsProvider);
  final access = await permissions.ensureMusicAccess();
  if (!context.mounted) return false;
  if (access != PermissionOutcome.granted) {
    await _explainPermission(context, permissions, permanent: access == PermissionOutcome.permanentlyDenied);
    return false;
  }
  final folder = await showFolderBrowser(context,
      title: 'Add an audiobook folder', systemPicker: () => FilePicker.platform.getDirectoryPath());
  if (folder == null || !context.mounted) return false;
  final service = await ref.read(importServiceProvider.future);
  if (!context.mounted) return false;
  final result = await _runJob(
    context,
    (onProgress) => service.importFolder(folder, audiobooks: true, onProgress: onProgress),
    title: 'Adding audiobooks',
  );
  await _refreshAudiobooks(ref);
  return result != null && result.added > 0;
}

/// One tap: goes through every folder that was added before, adds what is new, follows what
/// was moved, and says what is missing. Returns true if anything was added.
Future<bool> rescanMusicFolders(BuildContext context, WidgetRef ref, {bool audiobooks = false}) async {
  final service = await ref.read(importServiceProvider.future);
  final folders = [for (final f in await service.musicFolders()) if (f.audiobooks == audiobooks) f];
  if (!context.mounted) return false;
  if (folders.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(audiobooks ? 'No audiobook folders yet' : 'No music folders yet'),
        content: Text(
          audiobooks
              ? 'Add an audiobook folder once (Library > + > Add audiobook folder). You can add as many '
                  'places as you like. From then on, one tap on "Rescan audiobook folders" checks them.'
              : 'Add your music folder once (Library > + > Add folder). From then on, one tap on '
                  '"Rescan music folders" checks it for new songs.',
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
      ),
    );
    return false;
  }
  final permissions = ref.read(permissionsProvider);
  final access = await permissions.ensureMusicAccess();
  if (!context.mounted) return false;
  if (access != PermissionOutcome.granted) {
    await _explainPermission(context, permissions,
        permanent: access == PermissionOutcome.permanentlyDenied);
    return false;
  }

  final RescanPlan plan;
  try {
    plan = await service.planRescan(audiobooks: audiobooks);
  } catch (e) {
    if (context.mounted) _snack(context, friendlyError(e));
    return false;
  }
  if (!context.mounted) return false;

  // A folder that was not there before is worth a question; everything else just happens.
  var leaveOut = <String>{};
  if (plan.newFolders.isNotEmpty) {
    final answer = await showNewFolders(context, plan.newFolders);
    if (answer == null || !context.mounted) return false;
    leaveOut = answer;
  }

  final result = await _runJob(
    context,
    (onProgress) => service.rescan(plan, leaveOut: leaveOut, onProgress: onProgress),
    title: audiobooks ? 'Rescanning audiobooks' : 'Rescanning',
  );
  await _refreshAudiobooks(ref);
  if (result == null || !context.mounted) return false;

  if (result.missing.isNotEmpty) {
    final remove = await showMissingSongs(context, result);
    if (remove == true) {
      await service.removeSongs(result.missing.map((m) => m.id));
      if (context.mounted) {
        _snack(context,
            'Removed ${result.missing.length} song${result.missing.length == 1 ? '' : 's'} from the library');
      }
    }
  }
  return result.added > 0 || result.relinked > 0;
}

/// The rescan done quietly when the app opens (Settings > Library > Rescan when the app opens):
/// no windows, no permission question. It adds new songs and follows moved ones; it never removes
/// anything, and it leaves a folder that is new since the last scan for the user to decide about
/// (the one-tap rescan asks). Returns a sentence to show, or null when there is nothing to say.
Future<String?> quietRescan(WidgetRef ref) async {
  try {
    return await quietRescanWith(await ref.read(importServiceProvider.future));
  } catch (_) {
    return null;
  }
}

/// [quietRescan] on a given import service (so it can be tested).
Future<String?> quietRescanWith(LibraryImportService service) async {
  try {
    if ((await service.musicFolders()).isEmpty) return null;
    final plan = await service.planRescan();
    if (plan.folders.isEmpty) return null;
    if (plan.newFolders.isNotEmpty) {
      return 'A new folder was found in your music. Use Rescan music folders to choose what to add.';
    }
    final result = await service.rescan(plan);
    final n = result.added;
    if (n > 0) return 'Rescan: $n new song${n == 1 ? '' : 's'} added';
    if (result.relinked > 0) {
      return 'Rescan: ${result.relinked} moved song${result.relinked == 1 ? '' : 's'} followed';
    }
  } catch (_) {
    // A quiet rescan that fails says nothing; the one-tap rescan explains problems.
  }
  return null;
}

class _ProgressDialog extends StatelessWidget {
  const _ProgressDialog({required this.progress, this.title = 'Adding music'});

  final ValueNotifier<ImportProgress?> progress;
  final String title;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(title),
      content: ValueListenableBuilder<ImportProgress?>(
        valueListenable: progress,
        builder: (context, p, _) {
          final total = p?.total ?? 0;
          // A fixed size, so the card does not jump as file names change length.
          return SizedBox(
            width: 280,
            height: 76,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                LinearProgressIndicator(
                  value: (p == null || total == 0) ? null : p.done / total,
                ),
                const SizedBox(height: 12),
                Text(
                  p == null ? 'Looking for songs\u2026' : '${p.done} of ${p.total}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                // The file being read: one line, cut with ... when long.
                SizedBox(
                  height: 20,
                  child: Text(
                    p?.currentName ?? '',
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
