import 'dart:math';

final _random = Random();

/// [items] with any one of them moved to the front when [shuffle] is on. For lists sent to the player
/// one song at a time, where whatever goes first is what starts playing (the player's shuffle decides
/// the order of the rest).
List<T> startAnywhere<T>(List<T> items, {required bool shuffle}) {
  if (!shuffle || items.length < 2) return items;
  final first = _random.nextInt(items.length);
  return [items[first], ...items.take(first), ...items.skip(first + 1)];
}
