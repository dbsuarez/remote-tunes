import 'constants.dart';
import 'online/room_code.dart';

/// What the Player's pairing QR code says. Pure Dart so the web and phone
/// Controllers share it.
///
/// The code is a link to the web Controller, so any phone camera opens it, and
/// the RemoteTunes app reads the same code:
///
///   `https://<web controller>/#/pair?v=1&h=<ip>&p=<port>&r=<room>&t=<ticket>&n=<name>`
///
///  * h/p: the Player's local address (absent when the Player is Online only)
///  * r:   the online room code (absent when online is off)
///  * t:   a one-time pairing ticket. Scanning it replaces typing the 6-digit
///         code; the Player user still has to tap Accept.
///
/// Everything is after the `#`, which browsers never send to the web server.
/// The older `remotetunes://pair?...` form is still understood.
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

  /// The text shown as a QR code: a link to the web Controller.
  String encode() {
    final query = Uri(queryParameters: {
      'v': version,
      if (hasLocal) 'h': host!,
      if (hasLocal) 'p': '$port',
      if (hasOnline) 'r': roomCode!,
      't': ticket,
      if (playerName != null && playerName!.isNotEmpty) 'n': playerName!,
    }).query;
    return '${AppConstants.webControllerUrl}#/pair?$query';
  }

  static final _ticketRe = RegExp(r'^[A-Za-z0-9]{6,64}$');
  static final _hostRe = RegExp(r'^[A-Za-z0-9.\-]{1,253}$');

  /// Null when [raw] is not a RemoteTunes pairing code. Accepts the web link
  /// (it must point at this app's web Controller) and the older
  /// `remotetunes://pair?...` form.
  static PairingQr? parse(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null) return null;
    if (uri.scheme == scheme && uri.host == 'pair') {
      return _fromQuery(uri.queryParameters);
    }
    final web = Uri.tryParse(AppConstants.webControllerUrl);
    if (web != null &&
        uri.scheme == 'https' &&
        uri.host == web.host &&
        uri.path == web.path) {
      return fromFragment(uri.fragment);
    }
    return null;
  }

  /// For the web page itself: reads the part of its own address after the `#`
  /// (for example `/pair?v=1&r=...&t=...`). Null if there is no pairing link.
  static PairingQr? fromFragment(String fragment) {
    const prefix = '/pair?';
    if (!fragment.startsWith(prefix)) return null;
    try {
      return _fromQuery(Uri.splitQueryString(fragment.substring(prefix.length)));
    } on FormatException {
      return null;
    }
  }

  static PairingQr? _fromQuery(Map<String, String> q) {
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
