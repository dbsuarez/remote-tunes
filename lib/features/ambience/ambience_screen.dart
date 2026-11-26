import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/permissions.dart';
import '../../data/repositories/settings_repository.dart' show AppSettings;
import '../../providers/providers.dart' show settingsProvider;
import '../../providers/connection_providers.dart';
import '../../providers/library_providers.dart' show permissionsProvider;
import '../library/folder_browser.dart';
import 'ambience_controller.dart' show AmbienceException, ambienceExtensions;
import 'ambience_remote.dart';
import 'ambience_style.dart';
import 'ambience_view.dart';

/// Ambience: this phone's own, or the other phone's while controlling it.
class AmbienceScreen extends ConsumerStatefulWidget {
  const AmbienceScreen({super.key, this.remote = false});

  final bool remote;

  @override
  ConsumerState<AmbienceScreen> createState() => _AmbienceScreenState();
}

class _AmbienceScreenState extends ConsumerState<AmbienceScreen> {
  RemoteAmbience? _remote;
  Color _color = ambienceColor(null);

  void _tint(Color color) => setState(() => _color = color);

  @override
  void initState() {
    super.initState();
    if (widget.remote) {
      final remote = _remote = RemoteAmbience(ref.read(controllerClientProvider));
      remote.refresh().catchError((Object _) {});
    }
  }

  @override
  void dispose() {
    _remote?.dispose();
    super.dispose();
  }

  /// Our browser reads the storage itself, so it needs the music permission.
  Future<bool> _mayBrowse() async {
    final permissions = ref.read(permissionsProvider);
    if (await permissions.ensureMusicAccess() != PermissionOutcome.granted) {
      throw const AmbienceException('To add sounds, allow RemoteTunes to read music and audio in the phone\'s settings.');
    }
    return mounted;
  }

  /// One sound file, chosen in our own browser.
  Future<String?> _pickSoundFile() async {
    if (!await _mayBrowse() || !mounted) return null;
    return showFileBrowser(
      context,
      title: 'Choose a sound',
      extensions: ambienceExtensions,
      systemPicker: () async => (await FilePicker.platform.pickFiles(type: FileType.audio))?.files.singleOrNull?.path,
    );
  }

  /// One picture, chosen in our own browser. Android shows pictures only with All files access.
  Future<String?> _pickPicture() => showFileBrowser(
        context,
        title: 'Choose a picture',
        extensions: const {'jpg', 'jpeg', 'png', 'webp'},
        needsAllFiles: true,
        systemPicker: () async => (await FilePicker.platform.pickFiles(type: FileType.image))?.files.singleOrNull?.path,
      );

  /// A folder chosen in our own browser: the files in it (not those in folders inside it).
  Future<List<String>?> _pickFolder() async {
    if (!await _mayBrowse() || !mounted) return null;
    final folder = await showFolderBrowser(context, title: 'Import sounds', action: 'Import from this folder');
    if (folder == null) return null;
    return (await ref.read(folderSourceProvider).list(folder)).files;
  }

  /// What the owner calls this screen (Settings).
  String get _name => ref.watch(settingsProvider).valueOrNull?.ambienceName ?? AppSettings.defaultAmbienceName;

  Widget _body() {
    final remote = _remote;
    if (remote != null) return AmbienceView(controls: remote, onColor: _tint);
    final core = ref.watch(playerCoreProvider);
    final ambience = core.valueOrNull?.ambience;
    if (ambience == null) {
      return core.hasError || core.hasValue
          ? Center(child: Text("$_name isn't available on this phone."))
          : const Center(child: CircularProgressIndicator());
    }
    ambience.load();
    return AmbienceView(
      controls: ambience,
      onColor: _tint,
      owner: AmbienceOwner(
        pickFile: _pickSoundFile,
        addFile: ambience.addFile,
        addOwnSound: ambience.addOwnSound,
        removeFile: ambience.removeFile,
        setMaxVolume: ambience.setMaxVolume,
        pickFolder: _pickFolder,
        setIcon: ambience.setIcon,
        setBoost: ambience.setBoost,
        banners: AmbienceBanners(
          of: (group) {
            final b = ambience.banner(group);
            return b == null ? null : (image: FileImage(File(b.imagePath)), sourcePath: b.sourcePath, framing: b.framing);
          },
          pick: _pickPicture,
          read: (path) => File(path).readAsBytes(),
          set: ambience.setBanner,
          remove: ambience.removeBanner,
        ),
        watchedFolder: () => ambience.watchedFolder,
        watchFolder: ambience.setWatchedFolder,
        checkFolder: () async {
          await ambience.load();
          final folder = ambience.watchedFolder;
          if (folder == null) return const [];
          return ambience.connectNew((await ref.read(folderSourceProvider).list(folder)).files);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: Text(widget.remote ? '$_name on the other phone' : _name),
          backgroundColor: _color,
          foregroundColor: Colors.white,
        ),
        body: _body(),
      );
}
