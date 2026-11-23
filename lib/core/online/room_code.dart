import 'dart:math';

/// Online room codes: short, random, shown on the Player and typed on the
/// Controller. 8 characters from 31 look-alike-free symbols (about 40 bits), so
/// a code is practically unguessable. A new one is made every time the Player
/// goes online (short-lived, docs/02_ARCHITECTURE.md).
class RoomCode {
  RoomCode._();

  /// No 0/O, 1/I/L to avoid typing mistakes.
  static const String alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const int length = 8;

  /// Realtime channel name for a room: `remotetunes:<room-code>`.
  static String channelName(String code) => 'remotetunes:$code';

  static String generate([Random? random]) {
    final r = random ?? Random.secure();
    return String.fromCharCodes(
      List.generate(length, (_) => alphabet.codeUnitAt(r.nextInt(alphabet.length))),
    );
  }

  /// Cleans up what a person typed or pasted: upper-cases and drops spaces
  /// and dashes. Characters that are never used (0, 1, I, L, O) are left in
  /// place so [problem] can tell the user.
  static String normalize(String input) {
    return input.toUpperCase().replaceAll(RegExp(r'[\s\-_]'), '');
  }

  static bool isValid(String normalized) {
    if (normalized.length != length) return false;
    for (final unit in normalized.codeUnits) {
      if (!alphabet.codeUnits.contains(unit)) return false;
    }
    return true;
  }

  /// "ABCD-EFGH" for display.
  static String format(String code) =>
      code.length == length ? '${code.substring(0, 4)}-${code.substring(4)}' : code;

  /// Plain-language problem with [input], or null if it is a valid code.
  static String? problem(String input) {
    final n = normalize(input);
    if (n.isEmpty) return 'Enter the room code shown on the Player.';
    if (n.length != length) return 'A room code has $length letters and numbers.';
    if (!isValid(n)) {
      return 'That code has a character that is never used (the letters I, L, O '
          'and the digits 0, 1 are not in room codes). Check it and try again.';
    }
    return null;
  }
}
