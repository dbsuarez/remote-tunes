import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/features/library/folder_choice.dart';
import 'package:remote_tunes/features/library/import_service.dart';

const root = '/m';
final scan = FolderScan(root, [
  '/m/top.mp3',
  '/m/Rock/a.mp3',
  '/m/Rock/Live/b.mp3',
  '/m/Podcasts/t1.mp3',
  '/m/Podcasts/t2.mp3',
], const [
  FolderNode('/m/Podcasts', 'Podcasts', 1, 2),
  FolderNode('/m/Rock', 'Rock', 1, 2),
  FolderNode('/m/Rock/Live', 'Live', 2, 1),
]);

void main() {
  FolderChoice? answer;

  Future<void> open(WidgetTester tester,
      {Set<String> stored = const {}, int existing = 0}) async {
    answer = null;
    tester.view.physicalSize = const Size(500, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () async => answer = await showFolderChoice(context,
              scan: scan, alreadyExcluded: stored, alreadyInLibrary: existing),
          child: const Text('go'),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('everything starts ticked and the button says how many songs it adds', (tester) async {
    await open(tester);
    expect(find.text('Add 5 songs'), findsOneWidget);
    expect(tester.widgetList<CheckboxListTile>(find.byType(CheckboxListTile)).every((c) => c.value == true),
        isTrue);
  });

  testWidgets('unticking a folder leaves it and what is inside it out', (tester) async {
    await open(tester);
    await tester.tap(find.text('Rock'));
    await tester.pump();
    expect(find.text('Add 3 songs'), findsOneWidget);
    expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Live')).value, isFalse);
    expect(find.text('2 songs left out'), findsOneWidget);
    await tester.tap(find.text('Add 3 songs'));
    await tester.pumpAndSettle();
    expect(answer!.excluded, {'/m/Rock'}, reason: 'the folder inside is covered by its parent');
  });

  testWidgets('ticking a folder inside a left-out one brings its parents back', (tester) async {
    await open(tester);
    await tester.tap(find.text('Rock'));
    await tester.pump();
    await tester.tap(find.text('Live'));
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Rock')).value, isTrue);
    expect(find.text('Add 5 songs'), findsOneWidget);
  });

  testWidgets('folders left out before start unticked', (tester) async {
    await open(tester, stored: {'/m/Podcasts'});
    expect(tester.widget<CheckboxListTile>(find.widgetWithText(CheckboxListTile, 'Podcasts')).value, isFalse);
    expect(find.text('Add 3 songs'), findsOneWidget);
  });

  testWidgets('removing songs already in the library is offered only when something is left out',
      (tester) async {
    await open(tester, existing: 4);
    expect(find.textContaining('Also remove their songs'), findsNothing);
    await tester.tap(find.text('Podcasts'));
    await tester.pump();
    expect(find.textContaining('Also remove their songs'), findsOneWidget);
    await tester.tap(find.textContaining('Also remove their songs'));
    await tester.pump();
    await tester.tap(find.textContaining('Add 3'));
    await tester.pumpAndSettle();
    expect(answer!.removeExisting, isTrue);
  });

  testWidgets('cancel gives nothing', (tester) async {
    await open(tester);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(answer, isNull);
  });

  testWidgets('the report shows each count, and the problems', (tester) async {
    final r = ImportResult()
      ..found = 20
      ..added = 12
      ..duplicates = 3
      ..excluded = 4
      ..removed = 1;
    r.failures.add(const ImportFailure('bad.mp3', 'This file is empty.'));
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ImportReportDialog(result: r))));
    for (final l in ['Songs found', 'Added', 'Already in your library', 'Left out (excluded)',
        'Removed from the library', 'Skipped (problems)', 'bad.mp3', 'This file is empty.']) {
      expect(find.text(l), findsOneWidget, reason: l);
    }
    for (final n in ['20', '12', '3', '4', '1']) {
      expect(find.text(n), findsWidgets, reason: n);
    }
  });

  testWidgets('the report hides rows that are zero', (tester) async {
    final r = ImportResult()
      ..found = 2
      ..added = 2;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: ImportReportDialog(result: r))));
    expect(find.text('Added'), findsOneWidget);
    expect(find.text('Left out (excluded)'), findsNothing);
    expect(find.text('Skipped (problems)'), findsNothing);
  });
}
