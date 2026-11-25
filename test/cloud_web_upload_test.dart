import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:remote_tunes/features/cloud/cloud_config_store.dart';
import 'package:remote_tunes/features/cloud/cloud_library_view.dart';
import 'package:remote_tunes/features/cloud/cloud_models.dart';
import 'package:remote_tunes/features/cloud/cloud_pickers.dart';
import 'package:remote_tunes/features/cloud/cloud_service.dart';
import 'package:remote_tunes/features/cloud/cloud_settings_screen.dart';
import 'package:remote_tunes/features/cloud/cloud_web_upload.dart';

import 'cloud_library_view_test.dart' show MemoryCloudStore, entry;
import 'cloud_test.dart' show FakeR2, config;

PickedFile file(String name, {int size = 400}) => PickedFile(name: name, size: size, open: () => Stream.value(List.filled(size, 3)));

void main() {
  group('a picked file', () {
    test('has a base name and an extension', () {
      final f = file('01 - Ann - Hello.MP3');
      expect(f.baseName, '01 - Ann - Hello');
      expect(f.ext, 'mp3');
      expect(file('noext').ext, isEmpty);
      expect(file('.hidden').baseName, '.hidden');
      expect(file('a.b.flac').baseName, 'a.b');
    });

    test('only songs count', () {
      for (final n in ['a.mp3', 'a.M4A', 'a.aac', 'a.flac', 'a.ogg', 'a.opus', 'a.wav']) {
        expect(isAudioName(n), isTrue, reason: n);
      }
      for (final n in ['a.txt', 'a.jpg', 'mp3', 'a.mp3.zip']) {
        expect(isAudioName(n), isFalse, reason: n);
      }
    });
  });

  group('the candidates', () {
    test('start from the file name: track, artist and title', () {
      final c = buildWebCandidates([file('01 - Ann - Hello World.mp3'), file('Plain_Name.flac'), file('Bob - Another.m4a')], const CloudCatalog());
      expect(c, hasLength(3));
      expect((c[0].title, c[0].artist, c[0].track), ('Hello World', 'Ann', 1));
      expect((c[1].title, c[1].artist), ('Plain Name', ''), reason: 'underscores become spaces');
      expect((c[2].title, c[2].artist), ('Another', 'Bob'));
      expect(c[0].titleField.text, 'Hello World');
      expect(c[0].artistField.text, 'Ann');
      for (final x in c) {
        x.dispose();
      }
    });

    test('files that are not songs are left out', () {
      final c = buildWebCandidates([file('a.mp3'), file('cover.jpg'), file('notes.txt')], const CloudCatalog());
      expect(c.map((x) => x.file.name), ['a.mp3']);
      c.single.dispose();
    });

    test('a song that seems to be in the cloud already starts unticked', () {
      final cat = CloudCatalog([const CloudSong(id: 'x', title: 'Hello', artist: 'Ann', audioKey: 'songs/x.mp3')]);
      final c = buildWebCandidates([file('Ann - Hello.mp3'), file('Ann - New.mp3')], cat);
      expect(c[0].duplicate?.id, 'x');
      expect(c[0].ticked, isFalse);
      expect(c[1].ticked, isTrue);
      for (final x in c) {
        x.dispose();
      }
    });

    test('become uploads with what was edited, and the file read as it is', () async {
      final c = buildWebCandidates([file('01 - Ann - Hello.mp3', size: 50)], const CloudCatalog()).single;
      c.titleField.text = '  Hello (Live) ';
      c.albumField.text = 'Concert';
      c.genreField.text = 'Rock';
      final u = c.toUpload();
      expect((u.title, u.artist, u.album, u.genre, u.track, u.ext, u.length), ('Hello (Live)', 'Ann', 'Concert', 'Rock', 1, 'mp3', 50));
      expect(await u.open().expand((x) => x).toList(), hasLength(50));
      c.titleField.text = '   ';
      expect(c.toUpload().title, 'Hello', reason: 'an emptied title falls back to the one from the file name');
      c.dispose();
    });
  });

  group('the review', () {
    Future<List<CloudUpload>?> show(WidgetTester tester, List<PickedFile> files, {CloudCatalog? cat, int cloudBytes = 0}) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      List<CloudUpload>? result = [];
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => result = await showWebUploadReview(context, buildWebCandidates(files, cat ?? const CloudCatalog()), cloudBytes: cloudBytes),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      return result;
    }

    testWidgets('shows each song with its details to edit, and the total', (tester) async {
      await show(tester, [file('01 - Ann - Hello.mp3', size: 2 * 1024 * 1024), file('Bob - Other.mp3', size: 1024 * 1024)]);
      expect(tester.widget<TextField>(find.byKey(const ValueKey('web-title-0'))).controller!.text, 'Hello');
      expect(tester.widget<TextField>(find.byKey(const ValueKey('web-artist-1'))).controller!.text, 'Bob');
      expect(find.text('2 songs · 3.0 MB'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('web-tick-1')));
      await tester.pump();
      expect(find.text('1 song · 2.0 MB'), findsOneWidget);
    });

    testWidgets('"for all" fills the artist, album and genre of the ticked songs, and an empty field changes nothing', (tester) async {
      await show(tester, [file('Ann - One.mp3'), file('Two.mp3'), file('Three.mp3')]);
      await tester.tap(find.byKey(const ValueKey('web-tick-2')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('all-album')), 'The Album');
      await tester.enterText(find.byKey(const Key('all-genre')), 'Jazz');
      await tester.tap(find.byKey(const Key('fill-all')));
      await tester.pump();
      TextField f(String key) => tester.widget<TextField>(find.byKey(ValueKey(key)));
      expect(f('web-album-0').controller!.text, 'The Album');
      expect(f('web-album-1').controller!.text, 'The Album');
      expect(f('web-album-2').controller!.text, isEmpty, reason: 'unticked: left alone');
      expect(f('web-genre-1').controller!.text, 'Jazz');
      expect(f('web-artist-0').controller!.text, 'Ann', reason: 'the artist field was empty: no change');
    });

    testWidgets('Upload gives what is ticked, with the edits', (tester) async {
      List<CloudUpload>? got;
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => got = await showWebUploadReview(context, buildWebCandidates([file('Ann - One.mp3'), file('Two.mp3')], const CloudCatalog())),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('web-tick-1')));
      await tester.enterText(find.byKey(const ValueKey('web-title-0')), 'First');
      await tester.pump();
      await tester.tap(find.byKey(const Key('web-upload-go')));
      await tester.pumpAndSettle();
      expect(got!.map((u) => u.title), ['First']);
      expect(got!.single.artist, 'Ann');
    });

    testWidgets('with nothing ticked Upload waits; Cancel gives nothing', (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      List<CloudUpload>? got = [];
      await tester.pumpWidget(MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async => got = await showWebUploadReview(context, buildWebCandidates([file('One.mp3')], const CloudCatalog())),
            child: const Text('go'),
          ),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('web-tick-0')));
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byKey(const Key('web-upload-go'))).onPressed, isNull);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(got, isNull);
    });

    testWidgets('warns when the free storage would be passed', (tester) async {
      await show(tester, [file('One.mp3', size: 1024 * 1024)], cloudBytes: CloudLibraryView.freeBytes);
      expect(find.byKey(const Key('web-upload-over')), findsOneWidget);
    });

    testWidgets('a song already in the cloud is marked and unticked', (tester) async {
      final cat = CloudCatalog([const CloudSong(id: 'x', title: 'One', artist: 'Ann', audioKey: 'songs/x.mp3')]);
      await show(tester, [file('Ann - One.mp3')], cat: cat);
      expect(find.textContaining('seems to be in the cloud already'), findsOneWidget);
      expect(tester.widget<Checkbox>(find.byKey(const ValueKey('web-tick-0'))).value, isFalse);
    });
  });

  group('the whole flow', () {
    late FakeR2 r2;
    List<PickedFile>? picks;
    setUp(() {
      r2 = FakeR2();
      picks = [file('Ann - One.mp3', size: 300), file('Ann - Two.mp3', size: 500)];
    });

    Future<void> until(WidgetTester tester, Finder finder) async {
      for (var i = 0; i < 60 && finder.evaluate().isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    Future<void> open(WidgetTester tester, {CloudConfig? cfg, bool picker = true}) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      var n = 0;
      await tester.pumpWidget(ProviderScope(
        overrides: [
          cloudConfigStoreProvider.overrideWithValue(MemoryCloudStore(cfg ?? config)),
          if (picker) cloudSongPickerProvider.overrideWithValue(() async => picks!),
          cloudServiceFactoryProvider.overrideWithValue((c) => CloudLibraryService(c, client: MockClient((r) async => r2.handle(r)), newId: () => 'w${++n}', now: () => DateTime.utc(2026))),
        ],
        child: MaterialApp(
          home: Consumer(builder: (context, ref, _) => TextButton(onPressed: () => uploadPickedSongs(context, ref), child: const Text('go'))),
        ),
      ));
      await tester.tap(find.text('go'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(milliseconds: 200));
    }

    Future<void> finish(WidgetTester tester) async {
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(seconds: 1));
    }

    testWidgets('pick, edit, upload: the files and the catalog are in the bucket', (tester) async {
      await open(tester);
      expect(find.text('Upload to the cloud'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('all-album')), 'Live');
      await tester.enterText(find.byKey(const Key('all-genre')), 'Rock');
      await tester.tap(find.byKey(const Key('fill-all')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('web-upload-go')));
      await until(tester, find.text('Uploaded 2 songs'));
      expect(find.text('Uploaded 2 songs'), findsOneWidget);
      expect(r2.files['songs/w1.mp3'], hasLength(300));
      expect(r2.files['songs/w2.mp3'], hasLength(500));
      final cat = CloudCatalog.fromJson(jsonDecode(utf8.decode(r2.files['catalog.json']!)));
      expect(cat.songs.map((s) => '${s.title}/${s.artist}/${s.album}/${s.genre}'), ['One/Ann/Live/Rock', 'Two/Ann/Live/Rock']);
      expect(cat.songs.first.track, isNull);
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();
      await finish(tester);
    });

    testWidgets('without the keys it says to set up first, and nothing is asked of the computer', (tester) async {
      await open(tester, cfg: const CloudConfig(publicUrl: 'https://pub-123.r2.dev'));
      expect(find.text('Set up uploading first'), findsOneWidget);
      expect(r2.log, isEmpty);
      await finish(tester);
    });

    testWidgets('files that are not songs say so', (tester) async {
      picks = [file('notes.txt'), file('cover.jpg')];
      await open(tester);
      expect(find.text('No songs picked'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('picking nothing does nothing', (tester) async {
      picks = [];
      await open(tester);
      expect(find.byType(AlertDialog), findsNothing);
      expect(r2.log, isEmpty);
      await finish(tester);
    });

    testWidgets('where there is no picker (the phone) nothing happens', (tester) async {
      await open(tester, picker: false);
      expect(find.byType(AlertDialog), findsNothing);
      await finish(tester);
    });

    testWidgets('a song already in the cloud is found and unticked', (tester) async {
      r2.files['catalog.json'] = utf8.encode(jsonEncode({'songs': [entry('x', 'One', artist: 'Ann')]}));
      await open(tester);
      expect(tester.widget<Checkbox>(find.byKey(const ValueKey('web-tick-0'))).value, isFalse);
      expect(tester.widget<Checkbox>(find.byKey(const ValueKey('web-tick-1'))).value, isTrue);
      await finish(tester);
    });
  });

  group('the Cloud Library screen offers upload', () {
    Future<void> open(WidgetTester tester, {required CloudConfig cfg, Future<void> Function()? onUpload}) async {
      final r2 = FakeR2();
      r2.files['catalog.json'] = utf8.encode(jsonEncode({'songs': [entry('1', 'Hello')]}));
      tester.view.physicalSize = const Size(900, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [
          cloudConfigStoreProvider.overrideWithValue(MemoryCloudStore(cfg)),
          cloudServiceFactoryProvider.overrideWithValue((c) => CloudLibraryService(c, client: MockClient((r) async => r2.handle(r)))),
        ],
        child: MaterialApp(
          home: Scaffold(body: CloudLibraryView(onTrack: (s, u, i, {required queue}) async {}, onUpload: onUpload)),
        ),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 200)));
      await tester.pump(const Duration(milliseconds: 300));
    }

    testWidgets('a button, only with the keys, that starts the upload and then refreshes', (tester) async {
      var started = 0;
      await open(tester, cfg: config, onUpload: () async => started++);
      expect(find.byKey(const Key('cloud-upload')), findsOneWidget);
      await tester.tap(find.byKey(const Key('cloud-upload')));
      await tester.pump();
      expect(started, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('no button without the keys, or where uploading is not offered', (tester) async {
      await open(tester, cfg: const CloudConfig(publicUrl: 'https://pub-123.r2.dev'), onUpload: () async {});
      expect(find.byKey(const Key('cloud-upload')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
      await open(tester, cfg: config);
      expect(find.byKey(const Key('cloud-upload')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });

  group('help for the web page', () {
    test('the CORS rule names the web Controller and what it needs', () {
      final json = jsonDecode(CloudCors.policy()) as List;
      final rule = json.single as Map;
      expect(rule['AllowedOrigins'], [CloudCors.defaultOrigin]);
      expect(rule['AllowedMethods'], containsAll(['GET', 'PUT', 'DELETE', 'HEAD']));
      expect(rule['AllowedHeaders'], ['*']);
      expect(rule['ExposeHeaders'], ['ETag']);
      expect((jsonDecode(CloudCors.policy('https://other.example')) as List).single['AllowedOrigins'], ['https://other.example']);
    });

    testWidgets('the settings show it, and copy it', (tester) async {
      tester.view.physicalSize = const Size(700, 3200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(ProviderScope(
        overrides: [cloudConfigStoreProvider.overrideWithValue(MemoryCloudStore(const CloudConfig()))],
        child: const MaterialApp(home: CloudSettingsScreen()),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('cloud-import')), findsNothing, reason: 'no notes picker here (the web page)');
      await tester.ensureVisible(find.byKey(const Key('cloud-cors')));
      await tester.tap(find.text('Using it from the web page'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('cloud-cors-text')), findsOneWidget);
      await tester.ensureVisible(find.byKey(const Key('cloud-cors-copy')));
      await tester.tap(find.byKey(const Key('cloud-cors-copy')));
      await tester.pump();
      expect(copied, CloudCors.policy());
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 1));
    });
  });
}
