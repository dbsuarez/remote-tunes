import 'package:flutter/material.dart';
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

  Widget _folderTile(BuildContext context, MusicFolder f) => ListTile(
        contentPadding: EdgeInsets.zero,
        leading: Icon(f.audiobooks ? Icons.menu_book_rounded : Icons.folder_rounded),
        title: Text(p.basename(f.path), maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text(
          '${f.path}\n${f.songCount} ${f.audiobooks ? 'file' : 'song'}${f.songCount == 1 ? '' : 's'} · scanned ${_when(f.lastScan)}',
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
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final folders = _folders;
    final music = [for (final f in folders ?? const <MusicFolder>[]) if (!f.audiobooks) f];
    final books = [for (final f in folders ?? const <MusicFolder>[]) if (f.audiobooks) f];
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
                  if (music.isEmpty)
                    Text(
                      'No folders yet. Add your music folder once (Library > + > Add folder); it is '
                      'remembered here.',
                      style: theme.textTheme.bodyMedium,
                    )
                  else
                    for (final f in music) _folderTile(context, f),
                  const Divider(height: 40),
                  Text('Audiobook folders', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(
                    'Audiobooks can be in any places on the phone: add each folder. Everything in them is an '
                    'audiobook (kept out of your music and shuffle, and each remembers where you stopped). '
                    'They are scanned apart from the music.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        key: const Key('add-audiobook-folder'),
                        onPressed: () async {
                          await pickAndImportAudiobookFolder(context, ref);
                          await _load();
                        },
                        icon: const Icon(Icons.create_new_folder_outlined),
                        label: const Text('Add audiobook folder'),
                      ),
                      if (books.isNotEmpty)
                        FilledButton.icon(
                          key: const Key('rescan-books'),
                          onPressed: () async {
                            await rescanMusicFolders(context, ref, audiobooks: true);
                            await _load();
                          },
                          icon: const Icon(Icons.refresh_rounded),
                          label: const Text('Rescan audiobook folders'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  for (final f in books) _folderTile(context, f),
                ],
              ),
      ),
    );
  }
}
