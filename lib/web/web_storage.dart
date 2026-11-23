import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../features/controller/controller_client.dart';
import '../providers/recent_links.dart';

/// A room the user connected to before, for the "Recent rooms" list.
class RecentRoom {
  const RecentRoom({required this.code, this.playerName});

  final String code;
  final String? playerName;

  Map<String, dynamic> toJson() => {
        'code': code,
        if (playerName != null) 'playerName': playerName,
      };

  static RecentRoom? fromJson(Object? raw) {
    if (raw is! Map || raw['code'] is! String || (raw['code'] as String).isEmpty) {
      return null;
    }
    return RecentRoom(
      code: raw['code'] as String,
      playerName: raw['playerName'] is String ? raw['playerName'] as String : null,
    );
  }
}

/// Everything the web Controller remembers, in the browser's local storage:
/// the saved session (so a reload resumes without pairing again, as the spec
/// asks), recent rooms, recent links and the name shown on the Player.
///
/// The session token is a secret: it stays in this browser only and is removed
/// when the user disconnects or the Player no longer accepts it.
class WebStorage {
  WebStorage(this._prefs);

  final SharedPreferences _prefs;

  static const maxRooms = 8;
  static const _kName = 'rt.web.device_name';
  static const _kSession = 'rt.web.session';
  static const _kRooms = 'rt.web.recent_rooms';
  static const _kLinks = 'rt.web.recent_links';
  static const _kLinkSeq = 'rt.web.recent_links_seq';

  static const defaultDeviceName = 'Web Controller';

  // ------------------------------------------------------------------- name

  String get deviceName {
    final v = _prefs.getString(_kName)?.trim();
    return (v == null || v.isEmpty) ? defaultDeviceName : v;
  }

  Future<void> setDeviceName(String name) async {
    final v = name.trim();
    if (v.isEmpty) {
      await _prefs.remove(_kName);
    } else {
      await _prefs.setString(_kName, v);
    }
  }

  // ---------------------------------------------------------------- session

  ControllerSession? loadSession() {
    final raw = _prefs.getString(_kSession);
    if (raw == null) return null;
    try {
      return ControllerSession.fromJson(jsonDecode(raw));
    } on FormatException {
      return null; // damaged storage is treated as "nothing saved"
    }
  }

  Future<void> saveSession(ControllerSession s) =>
      _prefs.setString(_kSession, jsonEncode(s.toJson()));

  Future<void> clearSession() => _prefs.remove(_kSession);

  // ----------------------------------------------------------- recent rooms

  /// Always a new, editable list (callers add and remove entries).
  List<RecentRoom> loadRooms() {
    final raw = _prefs.getString(_kRooms);
    if (raw == null) return <RecentRoom>[];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return <RecentRoom>[];
      return [
        for (final e in list)
          if (RecentRoom.fromJson(e) != null) RecentRoom.fromJson(e)!,
      ];
    } on FormatException {
      return <RecentRoom>[];
    }
  }

  Future<void> _saveRooms(List<RecentRoom> rooms) => _prefs.setString(
      _kRooms, jsonEncode([for (final r in rooms) r.toJson()]));

  /// Adds (or moves to the top) a room, keeping a known player name if none
  /// is given.
  Future<void> rememberRoom(String code, {String? playerName}) async {
    final rooms = loadRooms();
    final old = rooms.where((r) => r.code == code).toList();
    rooms.removeWhere((r) => r.code == code);
    rooms.insert(
      0,
      RecentRoom(code: code, playerName: playerName ?? (old.isEmpty ? null : old.first.playerName)),
    );
    await _saveRooms(rooms.take(maxRooms).toList());
  }

  Future<void> removeRoom(String code) async {
    final rooms = loadRooms()..removeWhere((r) => r.code == code);
    await _saveRooms(rooms);
  }

  // ----------------------------------------------------------- recent links

  /// Always a new, editable list (callers add and remove entries).
  List<RecentLink> loadLinks() {
    final raw = _prefs.getString(_kLinks);
    if (raw == null) return <RecentLink>[];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return <RecentLink>[];
      return [
        for (final e in list)
          if (e is Map && e['id'] is num && e['url'] is String)
            RecentLink(
              id: (e['id'] as num).toInt(),
              url: e['url'] as String,
              title: e['title'] is String ? e['title'] as String : null,
            ),
      ];
    } on FormatException {
      return <RecentLink>[];
    }
  }

  Future<void> saveLinks(List<RecentLink> links) => _prefs.setString(
        _kLinks,
        jsonEncode([
          for (final l in links) {'id': l.id, 'url': l.url, if (l.title != null) 'title': l.title},
        ]),
      );

  int nextLinkId() {
    final next = (_prefs.getInt(_kLinkSeq) ?? 0) + 1;
    _prefs.setInt(_kLinkSeq, next);
    return next;
  }
}

/// Recent links for the web Controller, kept in browser storage.
class WebRecentLinksStore implements RecentLinksStore {
  WebRecentLinksStore(this._storage);

  final WebStorage _storage;
  final StreamController<List<RecentLink>> _controller =
      StreamController<List<RecentLink>>.broadcast();

  @override
  Stream<List<RecentLink>> watch() async* {
    yield _storage.loadLinks();
    yield* _controller.stream;
  }

  @override
  Future<void> remember(String url, {String? title}) async {
    final links = _storage.loadLinks();
    final i = links.indexWhere((l) => l.url == url);
    final kept = title ?? (i >= 0 ? links[i].title : null);
    if (i >= 0) links.removeAt(i);
    links.insert(0, RecentLink(id: _storage.nextLinkId(), url: url, title: kept));
    await _storage.saveLinks(links.take(RecentLinksStore.maxEntries).toList());
    _controller.add(_storage.loadLinks());
  }

  @override
  Future<void> remove(int id) async {
    final links = _storage.loadLinks()..removeWhere((l) => l.id == id);
    await _storage.saveLinks(links);
    _controller.add(links);
  }

  @override
  Future<void> clear() async {
    await _storage.saveLinks(const []);
    _controller.add(const []);
  }
}
