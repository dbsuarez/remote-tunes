/// A picture from the phone as a song's cover: chosen, cut square, and made into a JPEG. Phone only.
library;

import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;

import '../ambience/ambience_banner.dart';
import 'folder_browser.dart';
import 'lookup_models.dart';

/// Covers need no more than this many pixels each way.
const coverSide = 800;

/// The square part of [image] that [framing] shows, as a JPEG no larger than [coverSide].
Future<Uint8List> renderCover(ui.Image image, BannerFraming framing) async {
  final part = framing.partOf(Size(image.width.toDouble(), image.height.toDouble()));
  final side = max(1, min(coverSide, part.width.round()));
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final whole = Rect.fromLTWH(0, 0, side.toDouble(), side.toDouble());
  // A JPEG has no see-through parts: they are shown white.
  canvas.drawRect(whole, Paint()..color = const Color(0xFFFFFFFF));
  canvas.drawImageRect(image, part, whole, Paint()..filterQuality = FilterQuality.high);
  final picture = recorder.endRecording();
  final out = await picture.toImage(side, side);
  final data = await out.toByteData(format: ui.ImageByteFormat.rawRgba);
  out.dispose();
  picture.dispose();
  return compute(_jpeg, (side: side, rgba: data!.buffer.asUint8List()));
}

Uint8List _jpeg(({int side, Uint8List rgba}) raw) => img.encodeJpg(
      img.Image.fromBytes(width: raw.side, height: raw.side, bytes: raw.rgba.buffer, numChannels: 4),
      quality: 90,
    );

/// Lets the user choose a picture and frame it. Null if they changed their mind.
Future<LookupCover?> pickCoverPicture(BuildContext context) async {
  final path = await showFileBrowser(
    context,
    title: 'Choose a cover picture',
    extensions: const {'jpg', 'jpeg', 'png', 'webp'},
    needsAllFiles: true,
    systemPicker: () async => (await FilePicker.platform.pickFiles(type: FileType.image))?.files.singleOrNull?.path,
  );
  if (path == null || !context.mounted) return null;
  final Uint8List bytes;
  try {
    bytes = await File(path).readAsBytes();
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("That picture can't be read.")));
    }
    return null;
  }
  if (!context.mounted) return null;
  final result = await Navigator.of(context, rootNavigator: true).push<BannerResult>(MaterialPageRoute(
    builder: (_) => BannerCropScreen(
      bytes: bytes,
      group: 'cover',
      title: 'Cover picture',
      square: true,
      framing: const BannerFraming(aspect: 1),
      render: renderCover,
    ),
  ));
  return result == null ? null : LookupCover(result.png, 'jpg');
}

/// Replaced in tests.
final coverPickerProvider = Provider<Future<LookupCover?> Function(BuildContext context)>((ref) => pickCoverPicture);
