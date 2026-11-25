import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';

/// Picks a small text file (the Cloudflare details) and gives its text; null if nothing was picked or
/// the file is not a small one.
Future<String?> pickNotesFile() async {
  final r = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
  final f = r?.files.singleOrNull;
  if (f == null) return null;
  final bytes = f.bytes ?? (f.path == null ? null : await File(f.path!).readAsBytes());
  if (bytes == null || bytes.length > 64 * 1024) return null;
  return utf8.decode(bytes, allowMalformed: true);
}
