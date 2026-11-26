/// One file holding a phone's whole Ambience set-up: mixes, volumes and pictures as `ambience.json`, and
/// every sound and banner file. Written and read file by file, so large recordings do not fill the memory.
/// Phone only.
library;

import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../../providers/connection_providers.dart' show playerCoreProvider;
import '../library/folder_browser.dart';
import 'ambience_controller.dart';

const ambienceBackupExtension = 'rtambience';

/// Writes [ambience] into a new file in [folder] (nothing is replaced). Gives the file.
Future<File> writeAmbienceBackup(AmbienceController ambience, String folder, {DateTime? now}) async {
  final content = await ambience.exportData();
  final d = now ?? DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  final base = 'RemoteTunes-Ambience-${d.year}-${two(d.month)}-${two(d.day)}';
  var file = File(p.join(folder, '$base.$ambienceBackupExtension'));
  for (var n = 2; await file.exists(); n++) {
    file = File(p.join(folder, '$base ($n).$ambienceBackupExtension'));
  }
  final scratch = await Directory.systemTemp.createTemp('rt_amb_out_');
  final encoder = ZipFileEncoder();
  var open = false;
  try {
    final json = File(p.join(scratch.path, 'ambience.json'));
    await json.writeAsString(jsonEncode({
      'app': 'RemoteTunes',
      'kind': 'ambience',
      'format': 1,
      'created': d.toUtc().toIso8601String(),
      'data': content.data,
    }));
    // Stored as they are: sound files hardly shrink, and packing them would take long.
    encoder.create(file.path, level: 0);
    open = true;
    await encoder.addFile(json, 'ambience.json', 0);
    for (final e in content.files.entries) {
      await encoder.addFile(File(e.value), 'files/${e.key}', 0);
    }
    await encoder.close();
    open = false;
    return file;
  } catch (_) {
    if (open) {
      try {
        await encoder.close();
      } catch (_) {}
    }
    // Half a backup is worse than none.
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {}
    rethrow;
  } finally {
    await scratch.delete(recursive: true);
  }
}

/// Reads the backup at [path] and adds what this phone lacks. Throws [AmbienceException] with a plain
/// reason if it is not an Ambience backup.
Future<AmbienceRestore> restoreAmbienceBackup(AmbienceController ambience, String path) async {
  const wrong = AmbienceException('That is not an Ambience backup.');
  final scratch = await Directory.systemTemp.createTemp('rt_amb_in_');
  InputFileStream? input;
  try {
    final Map<String, dynamic> data;
    final files = <String, String>{};
    try {
      input = InputFileStream(path);
      final archive = ZipDecoder().decodeStream(input);
      final head = archive.findFile('ambience.json');
      if (head == null) throw wrong;
      final j = jsonDecode(utf8.decode(head.content));
      if (j is! Map || j['kind'] != 'ambience' || j['data'] is! Map) throw wrong;
      final format = j['format'];
      if (format is! num || format > 1) {
        throw const AmbienceException('That backup was made by a newer version of RemoteTunes. Update the app first.');
      }
      data = Map<String, dynamic>.from(j['data'] as Map);
      var n = 0;
      for (final entry in archive) {
        if (!entry.isFile || !entry.name.startsWith('files/')) continue;
        final name = entry.name.substring('files/'.length);
        // Our own names only: nothing in the file can choose where it is written.
        if (name.isEmpty || name.contains('/') || name.contains('\\')) continue;
        final ext = p.extension(name).toLowerCase();
        if (!RegExp(r'^\.[a-z0-9]{2,5}$').hasMatch(ext)) continue;
        final out = p.join(scratch.path, '${n++}$ext');
        final stream = OutputFileStream(out);
        entry.writeContent(stream);
        await stream.close();
        files[name] = out;
      }
    } on AmbienceException {
      rethrow;
    } catch (_) {
      throw wrong;
    }
    return await ambience.importData(data, files);
  } finally {
    await input?.close();
    await scratch.delete(recursive: true);
  }
}

/// This phone's ambience, for the Backup screen (replaced in tests).
final ambienceForBackupProvider = Provider<Future<AmbienceController?> Function()>(
    (ref) => () async => (await ref.read(playerCoreProvider.future)).ambience);

/// Chooses an Ambience backup file (replaced in tests). Android shows such files only with All files
/// access.
final ambienceBackupPickerProvider = Provider<Future<String?> Function(BuildContext context)>(
  (ref) => (context) => showFileBrowser(
        context,
        title: 'Choose an Ambience backup',
        extensions: const {ambienceBackupExtension},
        needsAllFiles: true,
        systemPicker: () async => (await FilePicker.platform.pickFiles(type: FileType.any))?.files.singleOrNull?.path,
      ),
);
