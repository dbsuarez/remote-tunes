import 'package:flutter/material.dart';

import '../../core/file_access.dart';

/// Shows whether the app may change music files, and opens the phone's page to
/// allow it. Checked again when the user comes back from that page.
class FileAccessTile extends StatefulWidget {
  const FileAccessTile({super.key, this.access = const FileAccess()});

  final FileAccess access;

  @override
  State<FileAccessTile> createState() => _FileAccessTileState();
}

class _FileAccessTileState extends State<FileAccessTile> with WidgetsBindingObserver {
  bool? _allowed;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  Future<void> _check() async {
    final ok = await widget.access.canWriteAll();
    if (mounted) setState(() => _allowed = ok);
  }

  @override
  Widget build(BuildContext context) {
    final allowed = _allowed ?? true;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(allowed ? Icons.folder_special_rounded : Icons.folder_off_outlined),
      title: const Text('All files access'),
      subtitle: Text(allowed
          ? 'Allowed: "Also write into the music file" can change files in any folder.'
          : 'Not allowed. Needed to write tags into music files in shared folders. '
              'Opens Android\'s page for this app; switch it on there.'),
      trailing: allowed ? const Icon(Icons.check_circle_rounded) : const Icon(Icons.open_in_new_rounded),
      onTap: allowed ? null : () => widget.access.openSettings(),
    );
  }
}
