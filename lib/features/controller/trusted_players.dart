import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// A Player this phone has paired with and may reconnect to without pairing
/// again. The token is a secret kept only on this phone.
class TrustedPlayer {
  const TrustedPlayer({
    required this.sessionId,
    required this.token,
    required this.peerId,
    required this.name,
    this.host,
    this.port,
    this.roomCode,
    required this.lastUsed,
  });

  final String sessionId;
  final String token;

  /// This phone's address in the Player's online room (kept stable so the
  /// Player recognises it).
  final String peerId;
  final String name;

  /// Where it was last reached. A phone's Wi-Fi address can change, so the
  /// Controller also looks the Player up by name on the network.
  final String? host;
  final int? port;
  final String? roomCode;
  final DateTime lastUsed;

  TrustedPlayer copyWith({
    String? name,
    String? host,
    int? port,
    String? roomCode,
    DateTime? lastUsed,
  }) =>
      TrustedPlayer(
        sessionId: sessionId,
        token: token,
        peerId: peerId,
        name: name ?? this.name,
        host: host ?? this.host,
        port: port ?? this.port,
        roomCode: roomCode ?? this.roomCode,
        lastUsed: lastUsed ?? this.lastUsed,
      );

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'token': token,
        'peerId': peerId,
        'name': name,
        if (host != null) 'host': host,
        if (port != null) 'port': port,
        if (roomCode != null) 'roomCode': roomCode,
        'lastUsed': lastUsed.toIso8601String(),
      };

  static TrustedPlayer? fromJson(Object? raw) {
    if (raw is! Map) return null;
    String? s(String k) =>
        raw[k] is String && (raw[k] as String).isNotEmpty ? raw[k] as String : null;
    final sid = s('sessionId');
    final token = s('token');
    final peer = s('peerId');
    if (sid == null || token == null || peer == null) return null;
    final host = s('host');
    final room = s('roomCode');
    final port = raw['port'] is num ? (raw['port'] as num).toInt() : null;
    if ((host == null || port == null) && room == null) return null;
    return TrustedPlayer(
      sessionId: sid,
      token: token,
      peerId: peer,
      name: s('name') ?? 'Player',
      host: host,
      port: port,
      roomCode: room,
      lastUsed: DateTime.tryParse(s('lastUsed') ?? '') ?? DateTime.now(),
    );
  }
}

/// Where trusted Players are remembered on this phone.
abstract class TrustedPlayersStore {
  /// Newest first.
  Future<List<TrustedPlayer>> load();

  /// Adds or replaces (by session id).
  Future<void> save(TrustedPlayer player);

  Future<void> remove(String sessionId);
}

/// Keeps trusted Players in the app's private preferences.
class PrefsTrustedPlayersStore implements TrustedPlayersStore {
  PrefsTrustedPlayersStore([Future<SharedPreferences>? prefs])
      : _prefs = prefs ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefs;
  static const _key = 'rt.trusted_players';
  static const maxPlayers = 10;

  @override
  Future<List<TrustedPlayer>> load() async {
    final raw = (await _prefs).getString(_key);
    if (raw == null) return <TrustedPlayer>[];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return <TrustedPlayer>[];
      final out = [
        for (final e in list)
          if (TrustedPlayer.fromJson(e) != null) TrustedPlayer.fromJson(e)!,
      ]..sort((a, b) => b.lastUsed.compareTo(a.lastUsed));
      return out;
    } on FormatException {
      return <TrustedPlayer>[];
    }
  }

  Future<void> _write(List<TrustedPlayer> list) async => (await _prefs)
      .setString(_key, jsonEncode([for (final p in list) p.toJson()]));

  @override
  Future<void> save(TrustedPlayer player) async {
    final list = await load();
    list.removeWhere((p) => p.sessionId == player.sessionId);
    list.insert(0, player);
    await _write(list.take(maxPlayers).toList());
  }

  @override
  Future<void> remove(String sessionId) async {
    final list = await load()..removeWhere((p) => p.sessionId == sessionId);
    await _write(list);
  }
}
