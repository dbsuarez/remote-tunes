import 'dart:typed_data';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/transport/local_websocket_transport.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/library_repository.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
import 'package:remote_tunes/features/music/local_music_source.dart';
import 'package:remote_tunes/features/music/music_source.dart';
import 'package:remote_tunes/features/music/song_art.dart';
import 'package:remote_tunes/features/player/queue_playback_engine.dart';
import 'package:remote_tunes/features/player/server/player_library.dart';

import 'helpers/fake_audio_backend.dart';
import 'music_widgets_test.dart' show tinyJpeg;

/// While a song plays the screen is rebuilt several times a second, and each time it asks for its
/// music source again. Rows must not forget their pictures then.
class _CountingLibrary extends RepositoryPlayerLibrary {
  _CountingLibrary(super.repo);
  final asked = <int>[];

  @override
  Future<Uint8List?> artThumbnail(int songId, {int size = 96}) async {
    asked.add(songId);
    return tinyJpeg;
  }
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  late AppDatabase db;
  late _CountingLibrary library;
  late QueuePlaybackEngine engine;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    library = _CountingLibrary(LibraryRepository(db));
    engine = QueuePlaybackEngine(backend: FakeAudioBackend(), fileExists: (_) => true, urlChecker: FakeUrlChecker());
    SongArt.forgetAll();
  });

  tearDown(() async {
    await engine.dispose();
    await db.close();
  });

  test('the same library and player give the same source every time', () {
    expect(identical(LocalMusicSource(library, engine), LocalMusicSource(library, engine)), isTrue);
    final other = _CountingLibrary(LibraryRepository(db));
    expect(identical(LocalMusicSource(other, engine), LocalMusicSource(library, engine)), isFalse);
  });

  test('the same connection gives the same source every time', () async {
    ControllerClient client() => ControllerClient(transportFactory: (h, p) => LocalWebSocketTransport(host: h, port: p));
    final a = client();
    final b = client();
    expect(identical(RemoteMusicSource(a), RemoteMusicSource(a)), isTrue);
    expect(identical(RemoteMusicSource(a), RemoteMusicSource(b)), isFalse);
    await a.dispose();
    await b.dispose();
  });

  testWidgets('redrawing the screen while playing keeps every picture and asks for nothing again', (tester) async {
    Widget screen() => MaterialApp(home: Scaffold(body: SongArt(source: LocalMusicSource(library, engine), songId: 7)));
    await tester.pumpWidget(screen());
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 500));
    for (var i = 0; i < 5; i++) {
      await tester.pumpWidget(screen());
      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.backgroundImage, isA<MemoryImage>(), reason: 'redraw $i: the cover is still there');
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(library.asked, [7]);
  });
}
