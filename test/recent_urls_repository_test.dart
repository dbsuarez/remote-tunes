import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/data/database/app_database.dart';
import 'package:remote_tunes/data/repositories/recent_urls_repository.dart';

void main() {
  late AppDatabase db;
  late RecentUrlsRepository repo;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = RecentUrlsRepository(db);
  });

  tearDown(() => db.close());

  test('remembers links, newest first', () async {
    await repo.remember('https://a.example/1.mp3', title: 'One');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.remember('https://a.example/2.mp3');
    final rows = await repo.all();
    expect(rows.map((r) => r.url), ['https://a.example/2.mp3', 'https://a.example/1.mp3']);
    expect(rows.last.title, 'One');
    expect(rows.first.title, isNull);
  });

  test('playing a saved link again moves it to the top without duplicating',
      () async {
    await repo.remember('https://a.example/1.mp3', title: 'One');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.remember('https://a.example/2.mp3');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    await repo.remember('https://a.example/1.mp3'); // no title given
    final rows = await repo.all();
    expect(rows, hasLength(2));
    expect(rows.first.url, 'https://a.example/1.mp3');
    expect(rows.first.title, 'One', reason: 'an earlier title is kept');

    await repo.remember('https://a.example/1.mp3', title: 'Renamed');
    expect((await repo.all()).first.title, 'Renamed');
  });

  test('keeps only the newest 20', () async {
    for (var i = 1; i <= 25; i++) {
      await repo.remember('https://a.example/$i.mp3');
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    final rows = await repo.all();
    expect(rows, hasLength(RecentUrlsRepository.maxEntries));
    expect(rows.first.url, 'https://a.example/25.mp3');
    expect(rows.any((r) => r.url == 'https://a.example/1.mp3'), isFalse);
    final count = await db.customSelect('SELECT COUNT(*) AS c FROM recent_urls').getSingle();
    expect(count.read<int>('c'), RecentUrlsRepository.maxEntries);
  });

  test('remove and clear', () async {
    await repo.remember('https://a.example/1.mp3');
    await repo.remember('https://a.example/2.mp3');
    final first = (await repo.all()).first;
    await repo.remove(first.id);
    expect(await repo.all(), hasLength(1));
    await repo.clear();
    expect(await repo.all(), isEmpty);
  });

  test('watch emits updates', () async {
    final stream = repo.watch();
    expect(await stream.first, isEmpty);
    final expectation = expectLater(
      stream,
      emitsThrough(predicate<List<RecentUrl>>((l) => l.length == 1)),
    );
    await repo.remember('https://a.example/1.mp3');
    await expectation;
  });
}
