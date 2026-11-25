import 'package:flutter/material.dart';

import 'cloud_service.dart';

/// Uploads [uploads] behind a progress window with a Stop button, then shows what happened. Shared by
/// the phone (songs picked in the Library) and the web page (songs picked from the computer). [note]
/// is shown in the result (for example "duplicates were not checked").
Future<void> runCloudUpload(
  BuildContext context,
  CloudLibraryService service,
  List<CloudUpload> uploads, {
  String? note,
}) async {
  final progress = ValueNotifier<({int done, int total, String? name})>((done: 0, total: uploads.length, name: null));
  var stop = false;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: const Text('Uploading'),
        content: ValueListenableBuilder(
          valueListenable: progress,
          builder: (context, p, _) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LinearProgressIndicator(value: p.total == 0 ? null : p.done / p.total),
              const SizedBox(height: 8),
              Text('${p.done} of ${p.total}', key: const Key('upload-progress')),
              if (p.name != null) Text(p.name!, maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        actions: [TextButton(key: const Key('upload-stop'), onPressed: () => stop = true, child: const Text('Stop'))],
      ),
    ),
  );
  CloudUploadResult? result;
  try {
    result = await service.upload(
      uploads,
      cancelled: () => stop,
      onProgress: (d, t, n) => progress.value = (done: d, total: t, name: n),
    );
  } catch (_) {
    result = null;
  }
  if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
  progress.dispose();
  if (!context.mounted) return;
  final r = result;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(r == null ? 'The upload failed' : 'Uploaded ${r.uploaded.length} song${r.uploaded.length == 1 ? '' : 's'}'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (r == null) const Text('Something went wrong. What went up is kept; try again.'),
            if (r != null) Text('${(r.bytes / (1024 * 1024)).toStringAsFixed(1)} MB sent.'),
            if (r?.stoppedBecause != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(r!.stoppedBecause!, key: const Key('upload-stopped'))),
            if (r != null && r.failed.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text('${r.failed.length} failed:', style: Theme.of(ctx).textTheme.labelLarge),
              for (final f in r.failed.take(8)) Text(f, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
            if (note != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(note)),
          ],
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
    ),
  );
}
