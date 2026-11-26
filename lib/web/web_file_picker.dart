import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import '../features/cloud/cloud_pickers.dart';

/// Opens the browser's file chooser for songs. A song is read only when it is uploaded (one at a
/// time), so picking hundreds does not fill the page's memory. Gives an empty list if nothing was chosen.
Future<List<PickedFile>> pickSongsFromComputer() {
  final done = Completer<List<PickedFile>>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = true
    ..accept = 'audio/*,.mp3,.m4a,.aac,.flac,.ogg,.opus,.wav';

  void finish() {
    if (done.isCompleted) return;
    final out = <PickedFile>[];
    final files = input.files;
    if (files != null) {
      for (var i = 0; i < files.length; i++) {
        final f = files.item(i);
        if (f == null) continue;
        out.add(PickedFile(name: f.name, size: f.size, open: () => Stream.fromFuture(_read(f))));
      }
    }
    done.complete(out);
  }

  input.addEventListener('change', ((web.Event _) => finish()).toJS);
  // Closing the chooser without picking (supported by current browsers).
  input.addEventListener('cancel', ((web.Event _) => finish()).toJS);
  input.click();
  return done.future;
}

Future<Uint8List> _read(web.File f) async {
  final buffer = await f.arrayBuffer().toDart;
  return buffer.toDart.asUint8List();
}

/// Opens the browser's file chooser for one picture. Gives null if nothing was chosen.
Future<Uint8List?> pickCoverFromComputer() {
  final done = Completer<Uint8List?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = 'image/jpeg,image/png,.jpg,.jpeg,.png';

  void finish() {
    if (done.isCompleted) return;
    final f = input.files?.item(0);
    done.complete(f == null ? null : _read(f));
  }

  input.addEventListener('change', ((web.Event _) => finish()).toJS);
  input.addEventListener('cancel', ((web.Event _) => finish()).toJS);
  input.click();
  return done.future;
}
