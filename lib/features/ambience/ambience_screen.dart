import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/permissions.dart';
import '../../providers/connection_providers.dart';
import '../../providers/library_providers.dart' show permissionsProvider;
import '../library/folder_browser.dart';
import 'ambience_controller.dart' show AmbienceException;
import 'ambience_remote.dart';
import 'ambience_view.dart';

/// Picks one sound file and gives its path.
Future<String?> _pickSoundFile() async {
  final r = await FilePicker.platform.pickFiles(type: FileType.audio);
  return r?.files.singleOrNull?.path;
}

/// Ambience: this phone's own, or the other phone's while controlling it.
class AmbienceScreen extends ConsumerStatefulWidget {
  const AmbienceScreen({super.key, this.remote = false});

  final bool remote;

  @override
  ConsumerState<AmbienceScreen> createState() => _AmbienceScreenState();
}

class _AmbienceScreenState extends ConsumerState<AmbienceScreen> {
  RemoteAmbience? _remote;

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

  /// A folder chosen in our own browser: the files in it (not those in folders inside it).
  Future<List<String>?> _pickFolder() async {
    final permissions = ref.read(permissionsProvider);
    if (await permissions.ensureMusicAccess() != PermissionOutcome.granted) {
      throw const AmbienceException('To import a folder, allow RemoteTunes to read music and audio in the phone\'s settings.');
    }
    if (!mounted) return null;
    final folder = await showFolderBrowser(context, title: 'Import sounds', action: 'Import from this folder');
    if (folder == null) return null;
    return (await ref.read(folderSourceProvider).list(folder)).songs;
  }

  Widget _body() {
    final remote = _remote;
    if (remote != null) return AmbienceView(controls: remote);
    final core = ref.watch(playerCoreProvider);
    final ambience = core.valueOrNull?.ambience;
    if (ambience == null) {
      return core.hasError || core.hasValue
          ? const Center(child: Text("Ambience isn't available on this phone."))
          : const Center(child: CircularProgressIndicator());
    }
    ambience.load();
    return AmbienceView(
      controls: ambience,
      owner: AmbienceOwner(
        pickFile: _pickSoundFile,
        addFile: ambience.addFile,
        addOwnSound: ambience.addOwnSound,
        removeFile: ambience.removeFile,
        setMaxVolume: ambience.setMaxVolume,
        pickFolder: _pickFolder,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(widget.remote ? 'Ambience on the other phone' : 'Ambience')),
        body: _body(),
      );
}
