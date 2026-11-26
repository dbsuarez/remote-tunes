import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'metadata_extractor.dart' show isSupportedAudio;

/// A place to start browsing: the phone's own storage, or an SD card.
class StorageRoot {
  const StorageRoot(this.name, this.path);
  final String name;
  final String path;
}

/// What one folder holds: its folders and its songs (full paths, by name).
class FolderContents {
  const FolderContents(this.folders, this.songs);
  final List<String> folders;
  final List<String> songs;
}

abstract class FolderSource {
  Future<List<StorageRoot>> roots();

  /// Throws if the folder cannot be read.
  Future<FolderContents> list(String path);
}

/// The real storage of the phone.
class PhoneFolderSource implements FolderSource {
  static const _own = '/storage/emulated/0';

  @override
  Future<List<StorageRoot>> roots() async {
    final out = [const StorageRoot('Phone storage', _own)];
    try {
      // Android gives the app its own folder on every storage; the storage is what comes before it.
      var cards = 0;
      for (final d in await getExternalStorageDirectories() ?? const <Directory>[]) {
        final at = d.path.indexOf('/Android/');
        if (at <= 0) continue;
        final root = d.path.substring(0, at);
        if (root == _own || out.any((r) => r.path == root)) continue;
        cards++;
        out.add(StorageRoot(cards == 1 ? 'SD card' : 'SD card $cards', root));
      }
    } catch (_) {
      // The phone's own storage is still offered.
    }
    return out;
  }

  @override
  Future<FolderContents> list(String path) async {
    final folders = <String>[];
    final songs = <String>[];
    await for (final e in Directory(path).list(followLinks: false)) {
      final name = p.basename(e.path);
      if (name.startsWith('.')) continue;
      if (e is Directory) {
        // Other apps' private files: nothing to add there.
        if (name == 'Android' && path.startsWith('/storage/') && path.split('/').length <= 4) continue;
        folders.add(e.path);
      } else if (e is File && isSupportedAudio(e.path)) {
        songs.add(e.path);
      }
    }
    int byName(String a, String b) => p.basename(a).toLowerCase().compareTo(p.basename(b).toLowerCase());
    return FolderContents(folders..sort(byName), songs..sort(byName));
  }
}

final folderSourceProvider = Provider<FolderSource>((ref) => PhoneFolderSource());

/// Where the browser was last, so adding the next folder starts there.
final lastBrowsedFolderProvider = StateProvider<String?>((ref) => null);

/// Opens the app's own folder browser and gives the folder chosen, or null. [systemPicker] is offered in
/// the menu for the rare place the browser cannot reach.
Future<String?> showFolderBrowser(
  BuildContext context, {
  required String title,
  String action = 'Add this folder',
  Future<String?> Function()? systemPicker,
}) =>
    Navigator.of(context, rootNavigator: true).push<String>(
      MaterialPageRoute(builder: (_) => FolderBrowser(title: title, action: action, systemPicker: systemPicker)),
    );

class FolderBrowser extends ConsumerStatefulWidget {
  const FolderBrowser({super.key, required this.title, this.action = 'Add this folder', this.systemPicker});

  final String title;
  final String action;
  final Future<String?> Function()? systemPicker;

  @override
  ConsumerState<FolderBrowser> createState() => _FolderBrowserState();
}

class _FolderBrowserState extends ConsumerState<FolderBrowser> {
  List<StorageRoot> _roots = const [];

  /// The folder shown; null while the list of storages shows.
  String? _path;
  FolderContents? _contents;
  String? _error;
  int _request = 0;

  /// What each folder in the list holds, once looked at.
  final Map<String, Future<FolderContents?>> _inside = {};

  FolderSource get _source => ref.read(folderSourceProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _start() async {
    final roots = await _source.roots();
    if (!mounted) return;
    _roots = roots;
    final last = ref.read(lastBrowsedFolderProvider);
    if (last != null && _rootOf(last) != null) {
      await _open(last);
      if (_error == null || !mounted) return;
    }
    // With one storage there is nothing to choose between.
    await _open(roots.length == 1 ? roots.single.path : null);
  }

  StorageRoot? _rootOf(String path) => _roots.where((r) => r.path == path || p.posix.isWithin(r.path, path)).firstOrNull;

  Future<void> _open(String? path) async {
    final request = ++_request;
    setState(() {
      _path = path;
      _contents = null;
      _error = null;
    });
    if (path == null) return;
    try {
      final contents = await _source.list(path);
      if (!mounted || request != _request) return;
      ref.read(lastBrowsedFolderProvider.notifier).state = path;
      setState(() => _contents = contents);
    } catch (_) {
      if (!mounted || request != _request) return;
      setState(() => _error = "This folder can't be read.");
    }
  }

  /// Where Up goes from here; null if there is nowhere (then Back leaves the browser).
  ({String? path})? get _up {
    final path = _path;
    if (path == null) return null;
    final root = _rootOf(path);
    if (root == null || root.path == path) return _roots.length > 1 ? (path: null) : null;
    return (path: p.posix.dirname(path));
  }

  /// The folder's name as the owner knows it ("Phone storage › Music").
  String _trail(String path) {
    final root = _rootOf(path);
    if (root == null) return path;
    final rest = path == root.path ? const <String>[] : p.posix.split(p.posix.relative(path, from: root.path));
    return [root.name, ...rest].join(' › ');
  }

  Future<void> _useSystemPicker() async {
    String? chosen;
    try {
      chosen = await widget.systemPicker!();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Couldn't open Android's picker.")));
      }
      return;
    }
    if (chosen != null && mounted) Navigator.of(context).pop(chosen);
  }

  static String _count(int n, String word) => '$n $word${n == 1 ? '' : 's'}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final path = _path;
    final up = _up;
    final contents = _contents;
    return PopScope(
      canPop: up == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && up != null) _open(up.path);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title),
          leading: IconButton(
            key: const Key('browser-close'),
            tooltip: 'Close',
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
          actions: [
            if (widget.systemPicker != null)
              PopupMenuButton<String>(
                key: const Key('browser-menu'),
                onSelected: (_) => _useSystemPicker(),
                itemBuilder: (_) => const [PopupMenuItem(value: 'system', child: Text("Use Android's picker"))],
              ),
          ],
        ),
        body: Column(
          children: [
            if (path != null)
              Material(
                color: theme.colorScheme.surfaceContainerHigh,
                child: SizedBox(
                  height: 52,
                  child: Row(
                    children: [
                      IconButton(
                        key: const Key('browser-up'),
                        tooltip: 'Up one folder',
                        icon: const Icon(Icons.arrow_upward_rounded),
                        onPressed: up == null ? null : () => _open(up.path),
                      ),
                      Expanded(
                        // The end of a long trail is what matters: it stays in view.
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          reverse: true,
                          child: Text(_trail(path), key: const Key('browser-trail'), style: theme.textTheme.titleSmall),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                  ),
                ),
              ),
            Expanded(child: _list(theme, path, contents)),
            if (path != null)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: const Key('browser-choose'),
                      onPressed: contents == null ? null : () => Navigator.of(context).pop(path),
                      icon: const Icon(Icons.check_rounded),
                      label: Text(widget.action),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _list(ThemeData theme, String? path, FolderContents? contents) {
    if (path == null) {
      if (_roots.isEmpty) return const Center(child: CircularProgressIndicator());
      return ListView(
        children: [
          for (final r in _roots)
            ListTile(
              key: ValueKey('browser-root-${r.name}'),
              minTileHeight: 64,
              leading: Icon(r.name.startsWith('SD') ? Icons.sd_card_rounded : Icons.smartphone_rounded),
              title: Text(r.name),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => _open(r.path),
            ),
        ],
      );
    }
    if (_error != null) return Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(_error!)));
    if (contents == null) return const Center(child: CircularProgressIndicator());
    if (contents.folders.isEmpty && contents.songs.isEmpty) {
      return const Center(child: Text('No folders or songs here.'));
    }
    final folders = contents.folders;
    final muted = theme.colorScheme.onSurfaceVariant;
    return ListView.builder(
      key: ValueKey('browser-list-$path'),
      itemCount: folders.length + contents.songs.length,
      itemBuilder: (context, i) {
        if (i >= folders.length) {
          final song = contents.songs[i - folders.length];
          return ListTile(
            dense: true,
            leading: Icon(Icons.music_note_rounded, color: muted),
            title: Text(p.basename(song), maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted)),
          );
        }
        final folder = folders[i];
        final inside = _inside[folder] ??= _source.list(folder).then<FolderContents?>((c) => c).catchError((Object _) => null);
        return ListTile(
          key: ValueKey('browser-folder-${p.basename(folder)}'),
          minTileHeight: 60,
          leading: Icon(Icons.folder_rounded, color: theme.colorScheme.primary),
          title: Text(p.basename(folder), maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: FutureBuilder<FolderContents?>(
            future: inside,
            builder: (context, snap) {
              final c = snap.data;
              if (snap.connectionState != ConnectionState.done) return const Text(' ');
              if (c == null) return const Text("Can't be read");
              return Text([
                if (c.songs.isNotEmpty) _count(c.songs.length, 'song'),
                if (c.folders.isNotEmpty) _count(c.folders.length, 'folder'),
                if (c.songs.isEmpty && c.folders.isEmpty) 'Empty',
              ].join(' · '));
            },
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _open(folder),
        );
      },
    );
  }
}
