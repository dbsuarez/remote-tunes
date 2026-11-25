import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/models/enums.dart';
import 'package:remote_tunes/core/protocol/library_models.dart';
import 'package:remote_tunes/features/music/queue_view.dart';

import 'music_widgets_test.dart' show FakeMusicSource, host, settleUi;

RemoteQueueItem _item(int i) => RemoteQueueItem(
      queueItemId: i,
      isCurrent: false,
      song: RemoteSong(id: i, title: 'Song $i', artist: 'A', album: 'B'),
    );

void main() {
  late FakeMusicSource source;

  setUp(() {
    source = FakeMusicSource(queue: [for (var i = 0; i < 60; i++) _item(i)]);
  });

  Widget view({required bool scroll, required int token}) => host(QueueView(
        source: source,
        revision: 1,
        currentIndex: 45,
        shuffle: false,
        repeat: RepeatMode.off,
        scrollToCurrent: scroll,
        scrollToken: token,
      ));

  Future<void> start(WidgetTester tester) async {
    tester.view.physicalSize = const Size(700, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('opening the Queue scrolls to the song playing', (tester) async {
    await start(tester);
    await tester.pumpWidget(view(scroll: true, token: 0));
    await settleUi(tester);
    expect(find.text('Song 45'), findsNothing);
    await tester.pumpWidget(view(scroll: true, token: 1));
    await settleUi(tester);
    await tester.pumpAndSettle();
    expect(find.text('Song 45'), findsOneWidget);
  });

  testWidgets('with the setting off, the list stays put', (tester) async {
    await start(tester);
    await tester.pumpWidget(view(scroll: false, token: 0));
    await settleUi(tester);
    await tester.pumpWidget(view(scroll: false, token: 1));
    await settleUi(tester);
    await tester.pumpAndSettle();
    expect(find.text('Song 45'), findsNothing);
    expect(find.text('Song 0'), findsOneWidget);
  });
}
