import 'dart:io';
import 'dart:typed_data';

import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/features/music/song_info_dialog.dart';
import 'package:remote_tunes/features/library/tag_writer.dart';

/// A tiny silent WAV (one tenth of a second).
Uint8List wav() {
  const dataLen = 1600;
  final b = BytesBuilder();
  void str(String s) => b.add(s.codeUnits);
  void u32(int v) => b.add((ByteData(4)..setUint32(0, v, Endian.little)).buffer.asUint8List());
  void u16(int v) => b.add((ByteData(2)..setUint16(0, v, Endian.little)).buffer.asUint8List());
  str('RIFF');
  u32(36 + dataLen);
  str('WAVE');
  str('fmt ');
  u32(16);
  u16(1);
  u16(1);
  u32(8000);
  u32(16000);
  u16(2);
  u16(16);
  str('data');
  u32(dataLen);
  b.add(Uint8List(dataLen));
  return b.toBytes();
}

/// A tiny MP3: an empty ID3v2.4 tag, then a few silent MPEG frames.
Uint8List mp3() {
  final b = BytesBuilder();
  b.add([0x49, 0x44, 0x33, 4, 0, 0, 0, 0, 0, 0]);
  // MPEG1 Layer III, 128 kbps, 44.1 kHz: frames of 417 bytes.
  for (var i = 0; i < 6; i++) {
    b.add([0xFF, 0xFB, 0x90, 0x00]);
    b.add(Uint8List(413));
  }
  return b.toBytes();
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('tagw'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('a missing file is reported, nothing is created', () {
    final r = const TagWriter().write('${dir.path}/none.mp3', title: 't', artist: 'a', album: 'b');
    expect(r, TagWriteResult.missing);
    expect(File('${dir.path}/none.mp3').existsSync(), isFalse);
  });

  test('a file that is not music is left alone, not damaged', () {
    final f = File('${dir.path}/notes.mp3')..writeAsStringSync('just some text, no tags');
    final r = const TagWriter().write(f.path, title: 't', artist: 'a', album: 'b');
    expect(r, isNot(TagWriteResult.written));
    expect(f.readAsStringSync(), 'just some text, no tags');
  });

  test('a file the library does not recognise is not reported as written', () {
    final f = File('${dir.path}/odd.wav')..writeAsBytesSync(wav());
    final r = const TagWriter().write(f.path, title: 'T', artist: 'A', album: 'B');
    // Whatever it says, it must not claim a write that did not happen.
    final back = readMetadata(f, getImage: false);
    expect(r == TagWriteResult.written, back.title == 'T');
  });

  test('tags are written into a file and read back', () {
    final f = File('${dir.path}/x.mp3')..writeAsBytesSync(mp3());
    final r = const TagWriter()
        .write(f.path, title: 'New Title', artist: 'New Artist', album: 'New Album', trackNumber: 7);
    expect(r, TagWriteResult.written);
    final m = readMetadata(f, getImage: false);
    expect(m.title, 'New Title');
    expect(m.artist, 'New Artist');
    expect(m.album, 'New Album');
  });

  test('every outcome has a plain sentence', () {
    for (final r in TagWriteResult.values) {
      expect(TagWriter.message(r), isNotEmpty);
    }
    expect(TagWriter.message(TagWriteResult.written), contains('written into the music file'));
    expect(TagWriter.message(TagWriteResult.notAllowed), contains('RemoteTunes only'));
  });

  group('the Edit info dialog', () {
    Future<SongInfoEdit?> open(WidgetTester tester, {required bool canWrite, bool tick = false}) async {
      SongInfoEdit? result;
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showSongInfoDialog(
                context, const RemoteSong(id: 1, title: 'T', artist: 'A', album: 'B'),
                canWriteFile: canWrite),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      if (tick) await tester.tap(find.text('Also write into the music file'));
      if (tick) await tester.pump();
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('offers writing into the file only for this phones library', (tester) async {
      await open(tester, canWrite: false);
      expect(find.text('Also write into the music file'), findsNothing);
    });

    testWidgets('is ticked from the start', (tester) async {
      final r = await open(tester, canWrite: true);
      expect(r!.writeToFile, isTrue);
    });

    testWidgets('unticking it keeps the change in the library only', (tester) async {
      final r = await open(tester, canWrite: true, tick: true);
      expect(r!.writeToFile, isFalse);
    });

    testWidgets('the box is shown ticked', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => showSongInfoDialog(
                context, const RemoteSong(id: 1, title: 'T', artist: 'A', album: 'B'),
                canWriteFile: true),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      final box = tester.widget<CheckboxListTile>(find.byType(CheckboxListTile));
      expect(box.value, isTrue);
    });
  });
}
