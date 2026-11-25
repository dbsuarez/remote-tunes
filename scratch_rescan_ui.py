def edit(p, pairs):
    s = open(p, encoding='utf-8').read()
    for a, b in pairs:
        assert a in s, (p, a[:80])
        s = s.replace(a, b, 1)
    open(p, 'w', encoding='utf-8').write(s)

# ------------------------------------------------------------ dialogs
F = 'lib/features/library/folder_choice.dart'
edit(F, [
("/// The result of adding music: what was added and what was not, and why.", '''/// Asks about the folders that appeared since the last scan: all ticked; unticked ones are left
/// out (and can be let back in from Settings). Returns the folders to leave out, or null if
/// cancelled.
Future<Set<String>?> showNewFolders(BuildContext context, List<NewFolder> folders) {
  return showDialog<Set<String>>(
    context: context,
    builder: (_) => NewFoldersDialog(folders: folders),
  );
}

class NewFoldersDialog extends StatefulWidget {
  const NewFoldersDialog({super.key, required this.folders});

  final List<NewFolder> folders;

  @override
  State<NewFoldersDialog> createState() => _NewFoldersDialogState();
}

class _NewFoldersDialogState extends State<NewFoldersDialog> {
  late final Set<String> _add = {for (final f in widget.folders) f.path};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final songs = widget.folders.where((f) => _add.contains(f.path)).fold<int>(0, (a, f) => a + f.songCount);
    return AlertDialog(
      title: Text(widget.folders.length == 1 ? 'A new folder' : 'New folders'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'These folders were not there the last time. Untick the ones you do not want in the '
              'library: they are left out (you can let them back in from Settings).',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final f in widget.folders)
                    CheckboxListTile(
                      key: ValueKey(f.path),
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      controlAffinity: ListTileControlAffinity.leading,
                      value: _add.contains(f.path),
                      onChanged: (v) => setState(() => v == true ? _add.add(f.path) : _add.remove(f.path)),
                      title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${f.songCount} song${f.songCount == 1 ? '' : 's'}'),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(context, {
            for (final f in widget.folders)
              if (!_add.contains(f.path)) f.path,
          }),
          child: Text(songs == 0 ? 'Leave them out' : 'Add $songs song${songs == 1 ? '' : 's'}'),
        ),
      ],
    );
  }
}

/// Songs whose file is gone. Returns true to take them out of the library; false to keep them
/// (they show as unavailable until the file comes back).
Future<bool?> showMissingSongs(BuildContext context, ImportResult result) {
  return showDialog<bool>(
    context: context,
    builder: (ctx) {
      final theme = Theme.of(ctx);
      final n = result.missing.length;
      return AlertDialog(
        title: Text('$n song${n == 1 ? '' : 's'} not found'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.mostMissing)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text(
                      'Most of the songs in these folders are missing. Is the storage (an SD card, '
                      'a drive) connected? Keep them, and rescan when it is.',
                      style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.error),
                    ),
                  )
                else
                  Text(
                    'Their files are no longer in the folders. A moved song is followed by itself; '
                    'these were deleted, renamed with new tags, or are somewhere else.',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                const SizedBox(height: 8),
                for (final m in result.missing.take(12))
                  Text(m.artist.isEmpty ? m.title : '${m.title} · ${m.artist}',
                      maxLines: 1, overflow: TextOverflow.ellipsis),
                if (n > 12) Text('…and ${n - 12} more.'),
                const SizedBox(height: 8),
                Text(
                  'Removing takes them out of the library and their playlists. Keeping leaves them '
                  'as they are.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            key: const Key('missing-remove'),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(result.mostMissing ? 'Remove anyway' : 'Remove $n from the library'),
          ),
          FilledButton(
            key: const Key('missing-keep'),
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep them'),
          ),
        ],
      );
    },
  );
}

/// The result of adding music: what was added and what was not, and why.'''),
("              if (r.relinked > 0)", "              if (r.foldersScanned > 0) row(Icons.folder_open_rounded, 'Folders scanned', r.foldersScanned),\n              if (r.relinked > 0)"),
("              if (r.removed > 0) row(Icons.remove_circle_outline_rounded, 'Removed from the library', r.removed),",
 "              if (r.removed > 0) row(Icons.remove_circle_outline_rounded, 'Removed from the library', r.removed),\n              if (r.missing.isNotEmpty)\n                row(Icons.link_off_rounded, 'Missing (file not found)', r.missing.length,\n                    color: theme.colorScheme.error),"),
("              if (r.found == 0 && r.added == 0 && r.failed == 0)",
 "              if (r.unreachable.isNotEmpty)\n                Padding(\n                  padding: const EdgeInsets.only(top: 6),\n                  child: Text(\n                    'Could not be reached (is the storage connected?): '\n                    '${r.unreachable.join(', ')}',\n                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),\n                  ),\n                ),\n              if (r.found == 0 && r.added == 0 && r.failed == 0 && r.foldersScanned == 0)"),
])

# ------------------------------------------------------------ the action
A = 'lib/features/library/import_actions.dart'
s = open(A, encoding='utf-8').read()
a = s.index("Future<bool> _runImport(")
b = s.index("class _ProgressDialog extends StatelessWidget {")
s = s[:a] + '''Future<bool> _runImport(
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

''' + s[b:]
open(A, 'w', encoding='utf-8').write(s)

# ------------------------------------------------------------ the screen: Music folders
open('lib/features/library/music_folders_screen.dart', 'w', encoding='utf-8').write('''import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../providers/library_providers.dart';
import 'import_actions.dart';
import 'import_service.dart';

/// The folders that were added, with a button that rescans them all.
class MusicFoldersScreen extends ConsumerStatefulWidget {
  const MusicFoldersScreen({super.key});

  @override
  ConsumerState<MusicFoldersScreen> createState() => _MusicFoldersScreenState();
}

class _MusicFoldersScreenState extends ConsumerState<MusicFoldersScreen> {
  List<MusicFolder>? _folders;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = await ref.read(importServiceProvider.future);
    final list = await service.musicFolders();
    if (mounted) setState(() => _folders = list);
  }

  static String _when(DateTime? d) {
    if (d == null) return 'never scanned';
    final diff = DateTime.now().difference(d);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes} min ago';
    if (diff.inDays < 1) return '${diff.inHours} h ago';
    if (diff.inDays < 30) return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final folders = _folders;
    return Scaffold(
      appBar: AppBar(title: const Text('Music folders')),
      body: SafeArea(
        child: folders == null
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'The folders you added. One tap checks all of them for new songs, follows songs '
                    'you moved, and tells you about songs whose file is gone.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    key: const Key('rescan-now'),
                    onPressed: () async {
                      await rescanMusicFolders(context, ref);
                      await _load();
                    },
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Rescan music folders'),
                  ),
                  const SizedBox(height: 16),
                  if (folders.isEmpty)
                    Text(
                      'No folders yet. Add your music folder once (Library > + > Add folder); it is '
                      'remembered here.',
                      style: theme.textTheme.bodyMedium,
                    )
                  else
                    for (final f in folders)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.folder_rounded),
                        title: Text(p.basename(f.path), maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          '${f.path}\\n${f.songCount} song${f.songCount == 1 ? '' : 's'} · scanned ${_when(f.lastScan)}',
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: true,
                        trailing: IconButton(
                          tooltip: 'Forget ${p.basename(f.path)}',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () async {
                            final service = await ref.read(importServiceProvider.future);
                            await service.forgetFolder(f.path);
                            await _load();
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context)
                              ..hideCurrentSnackBar()
                              ..showSnackBar(const SnackBar(
                                  content: Text('Forgotten. The songs already added stay in the library.')));
                          },
                        ),
                      ),
                ],
              ),
      ),
    );
  }
}
''')

# ------------------------------------------------------------ entry points
edit('lib/features/shell/app_shell.dart', [
("                if (v == 'folder') pickAndImportFolder(context, ref);", "                if (v == 'folder') pickAndImportFolder(context, ref);\n                if (v == 'rescan') rescanMusicFolders(context, ref);"),
("                PopupMenuItem(value: 'files', child: Text('Add songs')),\n                PopupMenuItem(value: 'folder', child: Text('Add folder')),", "                PopupMenuItem(value: 'rescan', child: Text('Rescan music folders')),\n                PopupMenuItem(value: 'folder', child: Text('Add folder')),\n                PopupMenuItem(value: 'files', child: Text('Add songs')),"),
])
S = 'lib/features/settings/settings_screen.dart'
s = open(S, encoding='utf-8').read()
a = s.index("    entry('artfinder'") if "entry('artfinder'" in s else -1
print('found' if a >= 0 else 'no entry() in generated file')
