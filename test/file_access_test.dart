import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/file_access.dart';
import 'package:remote_tunes/features/settings/file_access_tile.dart';

class _Fake extends FileAccess {
  _Fake(this.allowed);
  bool allowed;
  int opened = 0;
  @override
  Future<bool> canWriteAll() async => allowed;
  @override
  Future<void> openSettings() async => opened++;
}

void main() {
  Future<void> show(WidgetTester tester, _Fake f) async {
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: FileAccessTile(access: f))));
    await tester.pump();
  }

  testWidgets('when it is not allowed, tapping opens the phone page', (tester) async {
    final f = _Fake(false);
    await show(tester, f);
    expect(find.textContaining('Not allowed'), findsOneWidget);
    await tester.tap(find.text('All files access'));
    expect(f.opened, 1);
  });

  testWidgets('when it is allowed it says so and has nothing to open', (tester) async {
    final f = _Fake(true);
    await show(tester, f);
    expect(find.textContaining('Allowed'), findsOneWidget);
    await tester.tap(find.text('All files access'));
    expect(f.opened, 0);
  });

  testWidgets('coming back from the phone page checks again', (tester) async {
    final f = _Fake(false);
    await show(tester, f);
    f.allowed = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(find.textContaining('Allowed'), findsOneWidget);
  });
}
