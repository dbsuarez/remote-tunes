import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/file_access.dart';
import 'metadata_extractor.dart' show extensionOf, supportedAudioExtensions;

/// A place to start browsing: the phone's own storage, or an SD card.
class StorageRoot {
  const StorageRoot(this.name, this.path);
  final String name;
  final String path;
}

/// What one folder holds: its folders and its files (full paths, by name).
class FolderContents {
  const FolderContents(this.folders, this.files);
  final List<String> folders;
  final List<String> files;
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
    final files = <String>[];
    await for (final e in Directory(path).list(followLinks: false)) {
      final name = p.basename(e.path);
      if (name.startsWith('.')) continue;
      if (e is Directory) {
        // Other apps' private files: nothing to add there.
        if (name == 'Android' && path.startsWith('/storage/') && path.split('/').length <= 4) continue;
        folders.add(e.path);
      } else if (e is File) {
        files.add(e.path);
      }
    }
    int byName(String a, String b) => p.basename(a).toLowerCase().compareTo(p.basename(b).toLowerCase());
    return FolderContents(folders..sort(byName), files..sort(byName));
  }
}

final folderSourceProvider = Provider<FolderSource>((ref) => PhoneFolderSource());

/// Android's "All files access" (replaced in tests).
final fileAccessProvider = Provider<FileAccess>((ref) => const FileAccess());

/// Where the browser was last, so the next time starts there.
final lastBrowsedFolderProvider = StateProvider<String?>((ref) => null);

enum _Mode { folder, file, files }

Future<T?> _push<T>(BuildContext context, FolderBrowser browser) =>
    Navigator.of(context, rootNavigator: true).push<T>(MaterialPageRoute(builder: (_) => browser));

/// Opens the app's own browser to choose a folder, and gives it (or null). Files of [showTypes]
/// (audio, unless said otherwise) show inside. [systemPicker] is offered in the menu for the rare place
/// the browser cannot reach.
Future<String?> showFolderBrowser(
  BuildContext context, {
  required String title,
  String action = 'Add this folder',
  Set<String>? showTypes,
  Future<String?> Function()? systemPicker,
}) =>
    _push<String>(context,
        FolderBrowser._(title: title, mode: _Mode.folder, action: action, types: showTypes, systemPicker: systemPicker));

/// The same browser, to choose one file: a tap on a file of one of [extensions] gives its path.
/// [needsAllFiles]: Android hides these files without "All files access" (anything that is not audio).
Future<String?> showFileBrowser(
  BuildContext context, {
  required String title,
  required Set<String> extensions,
  bool needsAllFiles = false,
  Future<String?> Function()? systemPicker,
}) =>
    _push<String>(context,
        FolderBrowser._(title: title, mode: _Mode.file, types: extensions, needsAllFiles: needsAllFiles, systemPicker: systemPicker));

/// The same browser, to choose several files, from one folder or more.
Future<List<String>?> showFilesBrowser(
  BuildContext context, {
  required String title,
  required Set<String> extensions,
  Future<List<String>?> Function()? systemPicker,
}) =>
    _push<List<String>>(
        context, FolderBrowser._(title: title, mode: _Mode.files, types: extensions, systemPicker: systemPicker));

class FolderBrowser extends ConsumerStatefulWidget {
  const FolderBrowser._({
    required this.title,
    required _Mode mode,
    this.action = 'Add this folder',
    this.types,
    this.needsAllFiles = false,
    this.systemPicker,
  }) : _mode = mode;

  final String title;
  final _Mode _mode;
  final String action;

  /// The file types (extensions, lower case) listed; null: audio.
  final Set<String>? types;
  final bool needsAllFiles;

  /// Android's own screen, giving what this one would: a path, or (choosing several) a list of paths.
  final Future<Object?> Function()? systemPicker;

  @override
  ConsumerState<FolderBrowser> createState() => _FolderBrowserState();
}

class _FolderBrowserState extends ConsumerState<FolderBrowser> with WidgetsBindingObserver {
  List<StorageRoot> _roots = const [];

  /// The folder shown; null while the list of storages shows.
  String? _path;
  FolderContents? _contents;
  String? _error;
  int _request = 0;

  /// Whether Android may be hiding files from the list.
  bool _hidden = false;

  /// The files picked, when choosing several (kept while moving between folders).
  final Set<String> _picked = {};

  /// What each folder in the list holds, once looked at.
  final Map<String, Future<FolderContents?>> _inside = {};

  FolderSource get _source => ref.read(folderSourceProvider);
  Set<String> get _types => widget.types ?? supportedAudioExtensions;
  List<String> _shown(FolderContents c) => [for (final f in c.files) if (_types.contains(extensionOf(f))) f];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAccess();
      _start();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from the phone's settings: the files may show now.
    if (state == AppLifecycleState.resumed && widget.needsAllFiles) _checkAccess(reload: true);
  }

  Future<void> _checkAccess({bool reload = false}) async {
    if (!widget.needsAllFiles) return;
    final all = await ref.read(fileAccessProvider).canWriteAll();
    if (!mounted) return;
    final changed = _hidden == all;
    setState(() => _hidden = !all);
    if (reload && changed) {
      _inside.clear();
      await _open(_path);
    }
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
    Object? chosen;
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
    final several = widget._mode == _Mode.files;
    final here = contents == null ? const <String>[] : _shown(contents);
    final allHere = here.isNotEmpty && here.every(_picked.contains);
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
            if (_hidden)
              Material(
                color: theme.colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                  child: Row(
                    children: [
                      const Expanded(child: Text('Android hides these files unless All files access is on.')),
                      TextButton(
                        key: const Key('browser-allow'),
                        onPressed: () => ref.read(fileAccessProvider).openSettings(),
                        child: const Text('Allow'),
                      ),
                    ],
                  ),
                ),
              ),
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
                      if (several && here.isNotEmpty)
                        TextButton(
                          key: const Key('browser-select-all'),
                          onPressed: () => setState(() => allHere ? _picked.removeAll(here) : _picked.addAll(here)),
                          child: Text(allHere ? 'None' : 'All'),
                        ),
                      const SizedBox(width: 12),
                    ],
                  ),
                ),
              ),
            Expanded(child: _list(theme, path, contents)),
            if (widget._mode == _Mode.folder && path != null)
              _bottom(
                const Key('browser-choose'),
                widget.action,
                contents == null ? null : () => Navigator.of(context).pop(path),
              ),
            if (several)
              _bottom(
                const Key('browser-add'),
                _picked.isEmpty ? 'Tap the files to add' : 'Add ${_count(_picked.length, 'file')}',
                _picked.isEmpty ? null : () => Navigator.of(context).pop(_picked.toList()),
              ),
          ],
        ),
      ),
    );
  }

  Widget _bottom(Key key, String label, VoidCallback? onPressed) => SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton.icon(key: key, onPressed: onPressed, icon: const Icon(Icons.check_rounded), label: Text(label)),
          ),
        ),
      );

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
    final folders = contents.folders;
    final files = _shown(contents);
    final audio = widget.types == null;
    if (folders.isEmpty && files.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            audio ? 'No folders or songs here.' : 'No folders or ${_types.map((t) => t.toUpperCase()).join(', ')} files here.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    final muted = theme.colorScheme.onSurfaceVariant;
    return ListView.builder(
      key: ValueKey('browser-list-$path'),
      itemCount: folders.length + files.length,
      itemBuilder: (context, i) {
        if (i >= folders.length) return _fileRow(theme, files[i - folders.length], muted);
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
              final n = _shown(c).length;
              return Text([
                if (n > 0) _count(n, audio ? 'song' : 'file'),
                if (c.folders.isNotEmpty) _count(c.folders.length, 'folder'),
                if (n == 0 && c.folders.isEmpty) 'Empty',
              ].join(' · '));
            },
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
          onTap: () => _open(folder),
        );
      },
    );
  }

  Widget _fileRow(ThemeData theme, String file, Color muted) {
    final name = p.basename(file);
    final icon = supportedAudioExtensions.contains(extensionOf(file)) ? Icons.audio_file_rounded : Icons.description_rounded;
    switch (widget._mode) {
      // Choosing a folder: the files only show what is inside.
      case _Mode.folder:
        return ListTile(
          dense: true,
          leading: Icon(Icons.music_note_rounded, color: muted),
          title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: muted)),
        );
      case _Mode.file:
        return ListTile(
          key: ValueKey('browser-file-$name'),
          minTileHeight: 56,
          leading: Icon(icon, color: theme.colorScheme.primary),
          title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
          onTap: () => Navigator.of(context).pop(file),
        );
      case _Mode.files:
        return CheckboxListTile(
          key: ValueKey('browser-file-$name'),
          secondary: Icon(icon, color: theme.colorScheme.primary),
          title: Text(name, maxLines: 2, overflow: TextOverflow.ellipsis),
          value: _picked.contains(file),
          onChanged: (_) => setState(() => _picked.contains(file) ? _picked.remove(file) : _picked.add(file)),
        );
    }
  }
}
