import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/features/controller/controller_client.dart';
import 'package:remote_tunes/features/group/group_card.dart';
import 'package:remote_tunes/features/group/group_models.dart';
import 'package:remote_tunes/features/group/group_providers.dart';

class FakeFollower implements GroupFollower {
  FakeFollower([this._status = const GroupStatus()]);

  GroupStatus _status;
  final _c = StreamController<GroupStatus>.broadcast();
  final calls = <String>[];
  Object? joinFails;

  void emit(GroupStatus s) {
    _status = s;
    _c.add(s);
  }

  @override
  GroupStatus get status => _status;
  @override
  Stream<GroupStatus> get statusStream => _c.stream;

  @override
  Future<void> join() async {
    calls.add('join');
    if (joinFails != null) throw joinFails!;
    emit(_status.copyWith(phase: GroupPhase.syncing, message: 'Joining…'));
  }

  @override
  Future<void> leave() async {
    calls.add('leave');
    emit(const GroupStatus());
  }

  @override
  Future<void> setNudgeMs(int ms) async {
    calls.add('nudge $ms');
    emit(_status.copyWith(nudgeMs: ms));
  }

  @override
  Future<void> resync() async => calls.add('resync');

  CalibrationReport report = const CalibrationReport(ok: true, message: 'Done.');
  @override
  Future<CalibrationReport> autoAlign() async {
    calls.add('autoAlign');
    return report;
  }

  @override
  void cancelAutoAlign() => calls.add('cancelAutoAlign');
}

void main() {
  Future<void> open(WidgetTester tester, GroupFollower? f, {bool enabled = true}) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ProviderScope(
      overrides: [groupFollowerProvider.overrideWithValue(f)],
      child: MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: GroupCard(enabled: enabled))),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('where group play is impossible (the web page) nothing is shown',
      (tester) async {
    await open(tester, null);
    expect(find.text('Play on this phone too'), findsNothing);
  });

  testWidgets('off: it explains what it does and offers the switch', (tester) async {
    await open(tester, FakeFollower());
    expect(find.text('Play on this phone too'), findsOneWidget);
    expect(find.textContaining('same Wi-Fi'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);
  });

  testWidgets('the switch joins, and shows the status and the numbers', (tester) async {
    final f = FakeFollower();
    await open(tester, f);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(f.calls, ['join']);
    expect(find.text('Joining…'), findsOneWidget);

    f.emit(const GroupStatus(
      phase: GroupPhase.playing,
      driftMs: 12,
      rttMs: 8,
      spreadMs: 1.4,
      nudgeMs: 25,
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Playing in sync'), findsOneWidget);
    expect(find.text('+12 ms'), findsOneWidget);
    expect(find.text('8 ms'), findsOneWidget);
    expect(find.text('1 ms'), findsOneWidget);
    expect(find.text('+25 ms'), findsWidgets);
  });

  testWidgets('the fine-tune buttons move it 5 ms at a time and Measure again works',
      (tester) async {
    final f = FakeFollower(const GroupStatus(phase: GroupPhase.playing, nudgeMs: 10));
    await open(tester, f);
    await tester.tap(find.byTooltip('Later by 5 ms'));
    await tester.pump();
    await tester.tap(find.byTooltip('Earlier by 5 ms'));
    await tester.pump();
    await tester.tap(find.text('Measure again'));
    expect(f.calls, ['nudge 15', 'nudge 10', 'resync']);
  });

  testWidgets('a download in progress and a problem are shown plainly', (tester) async {
    final f = FakeFollower(const GroupStatus(
        phase: GroupPhase.downloading, message: 'Getting the song from the Player… 40%'));
    await open(tester, f);
    expect(find.text('Getting the song from the Player… 40%'), findsOneWidget);
    f.emit(const GroupStatus(
        phase: GroupPhase.problem, message: 'The Player no longer has that song.'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('The Player no longer has that song.'), findsOneWidget);
  });

  testWidgets('if joining is refused the reason is shown', (tester) async {
    final f = FakeFollower()
      ..joinFails = ControllerException('Playing on both phones needs the local network.');
    await open(tester, f);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('Playing on both phones needs the local network.'), findsOneWidget);
  });

  testWidgets('when the connection is not local the switch is off limits', (tester) async {
    await open(tester, FakeFollower(const GroupStatus(available: false)));
    expect(find.textContaining('Needs a connection over the same Wi-Fi'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
  });

  testWidgets('while reconnecting the switch is disabled', (tester) async {
    await open(tester, FakeFollower(), enabled: false);
    expect(tester.widget<Switch>(find.byType(Switch)).onChanged, isNull);
  });

  testWidgets('switching off leaves', (tester) async {
    final f = FakeFollower(const GroupStatus(phase: GroupPhase.playing));
    await open(tester, f);
    await tester.tap(find.byType(Switch));
    await tester.pump();
    expect(f.calls, ['leave']);
  });
}
