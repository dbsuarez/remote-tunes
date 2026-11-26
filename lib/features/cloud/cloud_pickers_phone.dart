import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/widgets.dart' show BuildContext;

import '../library/folder_browser.dart';

Future<String?> _pick(BuildContext context, String title, Set<String> extensions, FileType system) => showFileBrowser(
      context,
      title: title,
      extensions: extensions,
      needsAllFiles: true,
      systemPicker: () async => (await FilePicker.platform.pickFiles(type: system))?.files.singleOrNull?.path,
    );

/// Picks a small text file (the Cloudflare details) and gives its text; null if nothing was picked or
/// the file is not a small one.
Future<String?> pickNotesFile(BuildContext context) async {
  final path = await _pick(context, 'Choose the notes file', const {'txt', 'md'}, FileType.any);
  if (path == null) return null;
  final file = File(path);
  if (await file.length() > 64 * 1024) return null;
  return utf8.decode(await file.readAsBytes(), allowMalformed: true);
}

/// Picks a picture for a cover and gives its bytes; null if nothing was picked.
Future<Uint8List?> pickCoverFile(BuildContext context) async {
  final path = await _pick(context, 'Choose a cover', const {'jpg', 'jpeg', 'png'}, FileType.image);
  return path == null ? null : File(path).readAsBytes();
}
