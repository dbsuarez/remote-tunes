import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/features/shell/guide_doc.dart';
import 'package:remote_tunes/features/shell/help_screen.dart';

const sample = '''
# Guide

Intro with **bold** and a [link](x.md).

---

## 1. Sound

### Crossfade
One song fades into the next. See `Settings`.

- First point
- Second *point*

1. Do this
2. Then that

## 2. Two phones

Scan the QR code to pair.
''';

void main() {
  group('reading the guide', () {
    test('title, intro and sections (numbers dropped from the headings)', () {
      final g = GuideDoc.parse(sample);
      expect(g.title, 'Guide');
      expect(g.intro, hasLength(1));
      expect([for (final s in g.sections) s.title], ['Sound', 'Two phones']);
    });

    test('blocks: subheading, paragraph, bullets and numbered steps', () {
      final s = GuideDoc.parse(sample).sections.first;
      expect(s.blocks[0], isA<GuideSubheading>());
      expect(s.blocks[1], isA<GuideParagraph>());
      final bullets = s.blocks.whereType<GuideBullet>().toList();
      expect(bullets.map((b) => b.number), [null, null, 1, 2]);
      expect(bullets[1].plain, 'Second point');
    });

    test('lines of a paragraph are joined, links show as their text', () {
      final g = GuideDoc.parse('## A\n\nline one\nline two [see](a.md)\n');
      expect(g.sections.single.blocks.single.plain, 'line one line two see');
    });

    test('search needs every word, in any case, in the section title or text', () {
      final g = GuideDoc.parse(sample);
      expect(g.search('').length, 2);
      expect([for (final s in g.search('CROSSFADE')) s.title], ['Sound']);
      expect([for (final s in g.search('qr pair')) s.title], ['Two phones']);
      expect(g.search('crossfade qr'), isEmpty);
    });
  });

  group('the real guide that ships with the app', () {
    final text = File('docs/22_USER_GUIDE.md').readAsStringSync();
    final g = GuideDoc.parse(text);

    test('has its sections, and no table is left (they do not fit a phone)', () {
      expect(g.sections.length, greaterThanOrEqualTo(10));
      expect(text.split('\n').any((l) => l.startsWith('|')), isFalse);
      expect(g.sections.first.title, 'What the app is');
    });

    test('finds what it is asked for', () {
      expect(g.search('crossfade'), isNotEmpty);
      expect(g.search('all files access'), isNotEmpty);
      expect(g.search('left out'), isNotEmpty);
    });
  });

  group('the Help screen', () {
    Future<void> open(WidgetTester tester, {Future<String> Function()? load}) async {
      tester.view.physicalSize = const Size(500, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: HelpScreen(loadGuide: load ?? () async => sample),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('keeps the quick start and lists the guide sections', (tester) async {
      await open(tester);
      expect(find.text('Playing your music'), findsOneWidget);
      expect(find.text('The full guide'), findsOneWidget);
      expect(find.text('Sound'), findsWidgets);
      expect(find.text('Two phones'), findsOneWidget);
    });

    testWidgets('a section opens on a tap and shows its text', (tester) async {
      await open(tester);
      expect(find.text('First point'), findsNothing);
      await tester.tap(find.text('Sound').last);
      await tester.pumpAndSettle();
      expect(find.textContaining('One song fades'), findsOneWidget);
    });

    testWidgets('searching shows only the sections that match, already open', (tester) async {
      await open(tester);
      await tester.enterText(find.byType(TextField), 'qr code');
      await tester.pumpAndSettle();
      expect(find.text('Two phones'), findsOneWidget);
      expect(find.textContaining('Scan the QR code'), findsOneWidget);
      expect(find.text('Playing your music'), findsNothing, reason: 'the quick start steps aside');
      await tester.enterText(find.byType(TextField), 'zzzz');
      await tester.pumpAndSettle();
      expect(find.text('Nothing in the guide matches that.'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear'));
      await tester.pumpAndSettle();
      expect(find.text('Playing your music'), findsOneWidget);
    });

    testWidgets('if the guide cannot be read it says so, and the quick start still shows',
        (tester) async {
      await open(tester, load: () async => throw StateError('gone'));
      expect(find.text('The guide could not be opened.'), findsOneWidget);
      expect(find.text('Playing your music'), findsOneWidget);
    });
  });
}
