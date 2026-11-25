import 'package:file_picker/file_picker.dart';
import '../../core/screen_awake.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../core/permissions.dart';
import '../../providers/library_providers.dart';
import '../music/music_source.dart';
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

  final String? folder;
  try {
    folder = await FilePicker.platform.getDirectoryPath();
  } catch (_) {
    if (context.mounted) _snack(context, "Couldn't open the folder picker.");
    return false;
  }
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
        .where((s) => p.isWithin(folder!, s.path))
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
      (onProgress) => service.importFolder(folder!,
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

/// One tap: goes through every folder that was added before, adds what is new, follows what
/// was moved, and says what is missing. Returns true if anything was added.
Future<bool> rescanMusicFolders(BuildContext context, WidgetRef ref) async {
  final service = await ref.read(importServiceProvider.future);
  final folders = await service.musicFolders();
  if (!context.mounted) return false;
  if (folders.isEmpty) {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('No music folders yet'),
        content: const Text(
          'Add your music folder once (Library > + > Add folder). From then on, one tap on '
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
    plan = await service.planRescan();
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
    title: 'Rescanning',
  );
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
