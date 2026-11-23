import 'online/room_code.dart';

/// What the Player's pairing QR code says. Pure Dart so the web and phone
/// Controllers share it.
///
/// Format: `remotetunes://pair?v=1&h=<ip>&p=<port>&r=<room>&t=<ticket>&n=<name>`
///  * h/p: the Player's local address (absent when the Player is Online only)
///  * r:   the online room code (absent when online is off)
///  * t:   a one-time pairing ticket. Scanning it replaces typing the 6-digit
///         code; the Player user still has to tap Accept.
///
/// A scanned QR is untrusted input: [parse] checks every field.
class PairingQr {
  const PairingQr({
    required this.ticket,
    this.host,
    this.port,
    this.roomCode,
    this.playerName,
  });

  static const scheme = 'remotetunes';
  static const version = '1';

  final String ticket;
  final String? host;
  final int? port;
  final String? roomCode;
  final String? playerName;

  bool get hasLocal => host != null && port != null;
  bool get hasOnline => roomCode != null;

  String encode() => Uri(
        scheme: scheme,
        host: 'pair',
        queryParameters: {
          'v': version,
          if (hasLocal) 'h': host!,
          if (hasLocal) 'p': '$port',
          if (hasOnline) 'r': roomCode!,
          't': ticket,
          if (playerName != null && playerName!.isNotEmpty) 'n': playerName!,
        },
      ).toString();

  static final _ticketRe = RegExp(r'^[A-Za-z0-9]{6,64}$');
  static final _hostRe = RegExp(r'^[A-Za-z0-9.\-]{1,253}$');

  /// Null when [raw] is not a RemoteTunes pairing code.
  static PairingQr? parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || uri.scheme != scheme || uri.host != 'pair') return null;
    final q = uri.queryParameters;
    if (q['v'] != version) return null;

    final ticket = q['t'];
    if (ticket == null || !_ticketRe.hasMatch(ticket)) return null;

    String? host = q['h'];
    int? port = int.tryParse(q['p'] ?? '');
    if (host != null && !_hostRe.hasMatch(host)) host = null;
    if (port != null && (port < 1 || port > 65535)) port = null;
    if (host == null || port == null) {
      host = null;
      port = null;
    }

    String? room = q['r'] == null ? null : RoomCode.normalize(q['r']!);
    if (room != null && !RoomCode.isValid(room)) room = null;

    if (host == null && room == null) return null;

    final name = q['n'];
    return PairingQr(
      ticket: ticket,
      host: host,
      port: port,
      roomCode: room,
      playerName: (name == null || name.isEmpty)
          ? null
          : (name.length > 40 ? name.substring(0, 40) : name),
    );
  }
}
