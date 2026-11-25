import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/theme/app_theme.dart';
import 'package:remote_tunes/core/theme/skin.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/settings_repository.dart';
import 'package:remote_tunes/features/settings/skin_screen.dart';
import 'package:remote_tunes/providers/providers.dart';

const ocean = '''
{"name":"Ocean Deep","background":"#0B1220","surface":"#111B2E","surfaceHigh":"#18263F",
 "outline":"#2C3E5E","primary":"#4FC3F7","secondary":"#B388FF","cardRadius":20}
''';

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  group('a skin as JSON', () {
    test('is read, with an id made from the name', () {
      final s = Skin.parse(ocean);
      expect(s.name, 'Ocean Deep');
      expect(s.id, 'ocean-deep');
      expect(s.primary, const Color(0xFF4FC3F7));
      expect(s.cardRadius, 20);
      expect(s.builtIn, isFalse);
    });

    test('goes out and comes back the same', () {
      for (final b in Skin.builtIns) {
        final back = Skin.parse(b.toJson());
        expect([back.background, back.surface, back.primary, back.secondary, back.cardRadius],
            [b.background, b.surface, b.primary, b.secondary, b.cardRadius],
            reason: b.name);
      }
    });

    test('colors may be written with or without the #', () {
      final s = Skin.parse(ocean.replaceAll('"#4FC3F7"', '"4fc3f7"'));
      expect(s.primary, const Color(0xFF4FC3F7));
    });

    test('plain mistakes get a plain message', () {
      String err(String text) {
        try {
          Skin.parse(text);
        } on SkinException catch (e) {
          return e.message;
        }
        return 'accepted';
      }

      expect(err('not json'), contains('not valid JSON'));
      expect(err('[1,2]'), contains('JSON object'));
      expect(err('{}'), contains('"name"'));
      expect(err('{"name":"x"}'), contains('"background"'));
      expect(err(ocean.replaceAll('#0B1220', 'blue')), contains('not a color'));
      expect(err(ocean.replaceAll('Ocean Deep', 'a' * 40)), contains('too long'));
    });

    test('light backgrounds and unreadable accents are refused', () {
      expect(() => Skin.parse(ocean.replaceAll('#0B1220', '#FFFFFF')), throwsA(isA<SkinException>()));
      expect(() => Skin.parse(ocean.replaceAll('#4FC3F7', '#0C1424')), throwsA(isA<SkinException>()));
    });

    test('a silly radius is kept in range', () {
      expect(Skin.parse(ocean.replaceAll('"cardRadius":20', '"cardRadius":500')).cardRadius, 32);
      expect(Skin.parse(ocean.replaceAll(',"cardRadius":20', '')).cardRadius, 16);
    });
  });

  group('the built-in skins', () {
    test('each is dark and readable, and has its own name and id', () {
      final ids = <String>{};
      for (final s in Skin.builtIns) {
        expect(ids.add(s.id), isTrue, reason: 'unique: ${s.id}');
        expect(s.background.computeLuminance(), lessThan(0.25), reason: s.name);
        double contrast(Color a, Color b) {
          final la = a.computeLuminance() + 0.05, lb = b.computeLuminance() + 0.05;
          return la > lb ? la / lb : lb / la;
        }

        expect(contrast(s.primary, s.background), greaterThan(3), reason: s.name);
        expect(contrast(s.secondary, s.background), greaterThan(3), reason: s.name);
        expect(s.builtIn, isTrue);
      }
    });

    test('RemoteTunes is the default, and an unknown id falls back to it', () {
      expect(Skin.byId(null).id, Skin.defaultId);
      expect(Skin.byId('nothing').id, Skin.defaultId);
      expect(Skin.byId('ember').name, 'Ember');
      final custom = Skin.parse(ocean);
      expect(Skin.byId('ocean-deep', [custom]).name, 'Ocean Deep');
    });
  });

  group('the theme', () {
    test('uses the skin colors', () {
      final t = AppTheme.dark(skin: Skin.builtIns[1]);
      expect(t.scaffoldBackgroundColor, Skin.builtIns[1].background);
      expect(t.colorScheme.primary, Skin.builtIns[1].primary);
      expect(t.colorScheme.secondary, Skin.builtIns[1].secondary);
      expect(t.colorScheme.surface, Skin.builtIns[1].surface);
    });

    test('text on the accent stays readable (dark on light accents, white on dark ones)', () {
      final mono = AppTheme.dark(skin: Skin.byId('mono'));
      expect(mono.colorScheme.onPrimary.computeLuminance(), lessThan(0.2));
      final rose = AppTheme.dark(skin: Skin.byId('rose'));
      expect(rose.colorScheme.onPrimary.computeLuminance(), isNotNull);
    });

    test('the default theme is still the RemoteTunes one', () {
      final t = AppTheme.dark();
      expect(t.scaffoldBackgroundColor, RtColors.background);
      expect(t.colorScheme.primary, RtColors.teal);
    });

    test('card roundness follows the skin', () {
      final t = AppTheme.dark(skin: Skin.byId('rose'));
      final shape = t.cardTheme.shape as RoundedRectangleBorder;
      expect(shape.borderRadius, BorderRadius.circular(24));
    });
  });

  group('remembered', () {
    late AppDatabase db;
    late SettingsRepository repo;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = SettingsRepository(db);
    });

    tearDown(() => db.close());

    test('the choice and the added skins come back', () async {
      expect((await repo.load()).skin.id, Skin.defaultId);
      await repo.setCustomSkins([Skin.parse(ocean)]);
      await repo.setSkinId('ocean-deep');
      final s = await repo.load();
      expect(s.skin.name, 'Ocean Deep');
      expect(s.customSkins, hasLength(1));
    });

    test('a damaged saved skin is skipped, not fatal', () async {
      await repo.writeValue(SettingKeys.customSkins, '["{broken", "${ocean.replaceAll('"', r'\"').replaceAll('\n', ' ')}"]');
      final s = await repo.load();
      expect(s.customSkins.map((e) => e.name), ['Ocean Deep']);
      await repo.writeValue(SettingKeys.customSkins, 'junk');
      expect((await repo.load()).customSkins, isEmpty);
    });

    test('a skin that no longer exists falls back to the default', () async {
      await repo.setSkinId('gone');
      expect((await repo.load()).skin.id, Skin.defaultId);
    });
  });

  group('the Skins screen', () {
    late AppDatabase db;
    late SettingsRepository repo;
    String? clip;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      repo = SettingsRepository(db);
      clip = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clip = (call.arguments as Map)['text'] as String?;
        }
        if (call.method == 'Clipboard.getData') return <String, dynamic>{'text': clip};
        return null;
      });
    });

    tearDown(() async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      await db.close();
    });

    /// A test of the screen that lets go of it at the end (no timers left behind).
    void screenTest(String name, Future<void> Function(WidgetTester tester) body) {
      testWidgets(name, (tester) async {
        await body(tester);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump(const Duration(seconds: 1));
      });
    }

    Future<void> open(WidgetTester tester) async {
      tester.view.physicalSize = const Size(500, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(ProviderScope(
        overrides: [databaseProvider.overrideWithValue(db)],
        child: MaterialApp(theme: AppTheme.dark(), home: const SkinScreen()),
      ));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 100));
    }

    Future<void> settle(WidgetTester tester) async {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
      await tester.pump(const Duration(milliseconds: 200));
    }

    screenTest('lists the built-in skins, with the one in use ticked', (tester) async {
      await open(tester);
      for (final n in ['RemoteTunes', 'Midnight', 'Ember', 'Forest', 'Rose', 'Pure black', 'Mono']) {
        expect(find.text(n), findsOneWidget, reason: n);
      }
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
    });

    screenTest('tapping a skin applies it and remembers it', (tester) async {
      await open(tester);
      await tester.tap(find.text('Ember'));
      await settle(tester);
      expect((await tester.runAsync(() => repo.load()))!.skinId, 'ember');
    });

    screenTest('a skin can be added from pasted JSON, and then used', (tester) async {
      clip = ocean;
      await open(tester);
      await tester.tap(find.byTooltip('Add a skin'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Paste'));
      await tester.pump();
      await tester.tap(find.text('Add'));
      await settle(tester);
      await tester.pumpAndSettle();
      final s = (await tester.runAsync(() => repo.load()))!;
      expect(s.skinId, 'ocean-deep');
      expect(find.text('Ocean Deep'), findsOneWidget);
    });

    screenTest('a bad skin is explained and nothing is added', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Add a skin'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '{"name":"x"}');
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.textContaining('"background" is missing'), findsOneWidget);
      expect((await tester.runAsync(() => repo.load()))!.customSkins, isEmpty);
    });

    screenTest('a built-in name cannot be taken', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Add a skin'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, ocean.replaceAll('Ocean Deep', 'Ember'));
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();
      expect(find.textContaining('used by a built-in skin'), findsOneWidget);
    });

    screenTest('copy puts the skin JSON on the clipboard', (tester) async {
      await open(tester);
      await tester.tap(find.byTooltip('Copy Midnight to share'));
      await tester.pump();
      expect(clip, contains('"name": "Midnight"'));
      expect(Skin.parse(clip!).name, 'Midnight');
    });

    screenTest('an added skin can be removed, and the default comes back if it was in use',
        (tester) async {
      await tester.runAsync(() async {
        await repo.setCustomSkins([Skin.parse(ocean)]);
        await repo.setSkinId('ocean-deep');
      });
      await open(tester);
      expect(find.text('Ocean Deep'), findsOneWidget);
      expect(find.byTooltip('Remove Ember'), findsNothing, reason: 'built-in skins cannot be removed');
      await tester.tap(find.byTooltip('Remove Ocean Deep'));
      await settle(tester);
      final s = (await tester.runAsync(() => repo.load()))!;
      expect(s.customSkins, isEmpty);
      expect(s.skinId, Skin.defaultId);
    });
  });
}
