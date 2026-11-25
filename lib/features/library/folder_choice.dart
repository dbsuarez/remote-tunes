import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../providers/library_providers.dart';
import 'import_service.dart';

/// What the user decided in the "choose what to add" step.
class FolderChoice {
  const FolderChoice({required this.excluded, required this.removeExisting});

  /// Folders left out (a folder's own subfolders are left out with it) and single
  /// songs left out of folders that stay.
  final Set<String> excluded;

  /// Also take out songs of those folders that are already in the library.
  final bool removeExisting;
}

/// Lists the folders inside the one being added, all ticked; unticking a folder
/// leaves it (and what is inside it) out. Returns null if cancelled.
Future<FolderChoice?> showFolderChoice(
  BuildContext context, {
  required FolderScan scan,
  required Set<String> alreadyExcluded,
  required int alreadyInLibrary,
}) {
  return showDialog<FolderChoice>(
    context: context,
    builder: (_) => FolderChoiceDialog(
      scan: scan,
      alreadyExcluded: alreadyExcluded,
      alreadyInLibrary: alreadyInLibrary,
    ),
  );
}

class FolderChoiceDialog extends StatefulWidget {
  const FolderChoiceDialog({
    super.key,
    required this.scan,
    required this.alreadyExcluded,
    this.alreadyInLibrary = 0,
  });

  final FolderScan scan;

  /// Left out before (from an earlier time): they start unticked.
  final Set<String> alreadyExcluded;

  /// Songs of this folder that are in the library now.
  final int alreadyInLibrary;

  @override
  State<FolderChoiceDialog> createState() => _FolderChoiceDialogState();
}

class _FolderChoiceDialogState extends State<FolderChoiceDialog> {
  /// Always closed downwards: a folder that is out has everything below it out.
  late final Set<String> _out;

  /// Single songs unticked (inside folders that are still in).
  late final Set<String> _outFiles;

  /// Folders whose songs are listed.
  final Set<String> _open = {};

  /// A folder's own songs (not those of the folders inside it).
  late final Map<String, List<String>> _filesIn;
  bool _removeExisting = false;

  @override
  void initState() {
    super.initState();
    _out = {
      for (final f in widget.scan.folders)
        if (widget.alreadyExcluded.any((e) => f.path == e || p.isWithin(e, f.path))) f.path,
    };
    _outFiles = {
      for (final f in widget.scan.files)
        if (widget.alreadyExcluded.contains(f)) f,
    };
    _filesIn = {};
    for (final f in widget.scan.files) {
      _filesIn.putIfAbsent(p.dirname(f), () => []).add(f);
    }
  }

  bool _isOut(String path) => _out.contains(path);

  void _toggle(FolderNode node) {
    setState(() {
      if (_isOut(node.path)) {
        // Ticking a folder brings back the folders it sits in, and what is inside it.
        _out.removeWhere((x) => x == node.path || p.isWithin(node.path, x) || p.isWithin(x, node.path));
      } else {
        _out.addAll([
          for (final f in widget.scan.folders)
            if (f.path == node.path || p.isWithin(node.path, f.path)) f.path,
        ]);
      }
    });
  }

  bool _fileOut(String file) => _outFiles.contains(file) || _out.any((o) => p.isWithin(o, file));

  void _toggleFile(String file) => setState(() {
        if (!_outFiles.remove(file)) _outFiles.add(file);
      });

  int get _willAdd => widget.scan.files.where((f) => !_fileOut(f)).length;

  /// The smallest list that says the same: a folder whose parent is out is
  /// covered by the parent.
  Set<String> get _minimalOut => {
        for (final o in _out)
          if (!_out.contains(p.dirname(o))) o,
        // Single songs, unless their folder is out anyway.
        for (final f in _outFiles)
          if (!_out.any((o) => p.isWithin(o, f))) f,
      };

  /// Rows of songs under a folder (or the top folder when [dir] is the root).
  List<Widget> _songRows(String dir, int depth, {required bool folderOut}) {
    final files = [...?_filesIn[dir]]..sort();
    return [
      for (final f in files)
        CheckboxListTile(
          key: ValueKey(f),
          dense: true,
          contentPadding: EdgeInsets.only(left: 4.0 + 16.0 * depth),
          controlAffinity: ListTileControlAffinity.leading,
          // A song in a folder that is out is ticked by ticking the folder.
          value: !_fileOut(f),
          onChanged: folderOut ? null : (_) => _toggleFile(f),
          secondary: const Icon(Icons.music_note_rounded, size: 18),
          title: Text(p.basename(f), maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
    ];
  }

  Widget _expander(String dir, int count) {
    final open = _open.contains(dir);
    return IconButton(
      tooltip: open ? 'Hide the songs' : 'Show the $count song${count == 1 ? '' : 's'} in this folder',
      icon: Icon(open ? Icons.expand_less_rounded : Icons.expand_more_rounded),
      onPressed: () => setState(() => open ? _open.remove(dir) : _open.add(dir)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final left = widget.scan.files.length - _willAdd;
    return AlertDialog(
      title: const Text('Choose what to add'),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Untick the folders (or, with the arrow, single songs) you do not want in the library. '
              'They are remembered, so adding this folder again leaves them out too.',
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  // The songs directly in the chosen folder.
                  if ((_filesIn[widget.scan.root] ?? const []).isNotEmpty) ...[
                    ListTile(
                      dense: true,
                      contentPadding: const EdgeInsets.only(left: 16),
                      leading: const Icon(Icons.folder_open_rounded),
                      title: Text('${p.basename(widget.scan.root)} (its own songs)',
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: _expander(widget.scan.root, _filesIn[widget.scan.root]!.length),
                    ),
                    if (_open.contains(widget.scan.root))
                      ..._songRows(widget.scan.root, 1, folderOut: false),
                  ],
                  for (final f in widget.scan.folders) ...[
                    CheckboxListTile(
                      key: ValueKey(f.path),
                      dense: true,
                      contentPadding: EdgeInsets.only(left: 4.0 + 16.0 * (f.depth - 1)),
                      controlAffinity: ListTileControlAffinity.leading,
                      value: !_isOut(f.path),
                      onChanged: (_) => _toggle(f),
                      title: Text(f.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      secondary: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('${f.songCount}', style: theme.textTheme.bodySmall),
                          if ((_filesIn[f.path] ?? const []).isNotEmpty)
                            _expander(f.path, _filesIn[f.path]!.length),
                        ],
                      ),
                    ),
                    if (_open.contains(f.path))
                      ..._songRows(f.path, f.depth, folderOut: _isOut(f.path)),
                  ],
                ],
              ),
            ),
            if (widget.alreadyInLibrary > 0 && (_out.isNotEmpty || _outFiles.isNotEmpty))
              CheckboxListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _removeExisting,
                onChanged: (v) => setState(() => _removeExisting = v ?? false),
                title: const Text('Also remove their songs that are already in the library'),
              ),
            if (left > 0)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text('$left song${left == 1 ? '' : 's'} left out',
                    style: theme.textTheme.bodySmall),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            FolderChoice(excluded: _minimalOut, removeExisting: _removeExisting && (_out.isNotEmpty || _outFiles.isNotEmpty)),
          ),
          child: Text(_willAdd == 0 ? 'Nothing to add' : 'Add $_willAdd song${_willAdd == 1 ? '' : 's'}'),
        ),
      ],
    );
  }
}

/// Asks about the folders that appeared since the last scan: all ticked; unticked ones are left
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

/// The result of adding music: what was added and what was not, and why.
class ImportReportDialog extends StatelessWidget {
  const ImportReportDialog({super.key, required this.result, this.title = 'Finished'});

  final ImportResult result;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget row(IconData icon, String label, int n, {Color? color}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color ?? theme.colorScheme.onSurfaceVariant),
              const SizedBox(width: 12),
              Expanded(child: Text(label)),
              Text('$n', style: theme.textTheme.titleSmall),
            ],
          ),
        );
    final r = result;
    return AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: double.maxFinite,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (r.found > 0) row(Icons.search_rounded, 'Songs found', r.found),
              row(Icons.add_circle_outline_rounded, 'Added', r.added, color: theme.colorScheme.primary),
              if (r.duplicates > 0)
                row(Icons.library_music_outlined, 'Already in your library', r.duplicates),
              if (r.foldersScanned > 0) row(Icons.folder_open_rounded, 'Folders scanned', r.foldersScanned),
              if (r.relinked > 0)
                row(Icons.drive_file_move_outline, 'Moved (found again at the new place)', r.relinked,
                    color: theme.colorScheme.primary),
              if (r.excluded > 0) row(Icons.block_rounded, 'Left out (excluded)', r.excluded),
              if (r.removed > 0) row(Icons.remove_circle_outline_rounded, 'Removed from the library', r.removed),
              if (r.missing.isNotEmpty)
                row(Icons.link_off_rounded, 'Missing (file not found)', r.missing.length,
                    color: theme.colorScheme.error),
              if (r.failed > 0)
                row(Icons.error_outline_rounded, 'Skipped (problems)', r.failed,
                    color: theme.colorScheme.error),
              if (r.unreachable.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Could not be reached (is the storage connected?): '
                    '${r.unreachable.join(', ')}',
                    style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
                  ),
                ),
              if (r.found == 0 && r.added == 0 && r.failed == 0 && r.foldersScanned == 0)
                const Padding(padding: EdgeInsets.only(top: 8), child: Text('No songs found.')),
              if (r.failures.isNotEmpty) ...[
                const Divider(),
                for (final f in r.failures.take(15))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(f.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(f.reason),
                  ),
                if (r.failures.length > 15) Text('…and ${r.failures.length - 15} more.'),
              ],
            ],
          ),
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
    );
  }
}

/// The folders and files that are left out of the library, to let back in.
class LeftOutScreen extends ConsumerStatefulWidget {
  const LeftOutScreen({super.key});

  @override
  ConsumerState<LeftOutScreen> createState() => _LeftOutScreenState();
}

class _LeftOutScreenState extends ConsumerState<LeftOutScreen> {
  List<String>? _paths;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final service = await ref.read(importServiceProvider.future);
    final all = (await service.excludedPaths()).toList()..sort();
    if (mounted) setState(() => _paths = all);
  }

  @override
  Widget build(BuildContext context) {
    final paths = _paths;
    return Scaffold(
      appBar: AppBar(title: const Text('Left out of the library')),
      body: SafeArea(
        child: paths == null
            ? const Center(child: CircularProgressIndicator())
            : paths.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'Nothing is left out. Untick a folder when you add one, or remove a song '
                        'from the library, and it shows up here.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView(
                    children: [
                      for (final path in paths)
                        ListTile(
                          leading: Icon(p.extension(path).isEmpty
                              ? Icons.folder_off_outlined
                              : Icons.music_off_outlined),
                          title: Text(p.basename(path), maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(p.dirname(path), maxLines: 1, overflow: TextOverflow.ellipsis),
                          trailing: IconButton(
                            tooltip: 'Let back in',
                            icon: const Icon(Icons.undo_rounded),
                            onPressed: () async {
                              final service = await ref.read(importServiceProvider.future);
                              await service.includeAgain(path);
                              await _load();
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context)
                                ..hideCurrentSnackBar()
                                ..showSnackBar(const SnackBar(
                                    content: Text('It is added the next time its folder is added.')));
                            },
                          ),
                        ),
                    ],
                  ),
      ),
    );
  }
}
