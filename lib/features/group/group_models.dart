import 'dart:async';

/// What the Player says about the song that is playing (`group_sync`). The
/// other phone uses it, with the clock offset, to play the same song at the
/// same moment.
class GroupSync {
  const GroupSync({
    this.songId,
    required this.positionMs,
    required this.atMs,
    required this.playing,
    this.speed = 1.0,
    this.durationMs = 0,
    this.nextSongId,
  });

  /// Library id of the playing song; null if nothing (or an internet link or
  /// another app) is playing, which another phone cannot follow.
  final int? songId;

  /// Where the song was, in ms, at the Player's clock reading [atMs].
  final int positionMs;
  final double atMs;
  final bool playing;
  final double speed;
  final int durationMs;

  /// The song after this one, so it can be fetched ahead of time.
  final int? nextSongId;

  static GroupSync? fromPayload(Map<String, dynamic> p) {
    final pos = p['positionMs'];
    final at = p['atMs'];
    if (pos is! num || at is! num) return null;
    int? id(Object? v) => v is num ? v.toInt() : null;
    final speed = p['speed'] is num ? (p['speed'] as num).toDouble() : 1.0;
    return GroupSync(
      songId: id(p['songId']),
      positionMs: pos.toInt(),
      atMs: at.toDouble(),
      playing: p['playing'] == true,
      speed: speed.clamp(0.5, 2.0),
      durationMs: id(p['durationMs']) ?? 0,
      nextSongId: id(p['nextSongId']),
    );
  }
}

enum GroupPhase {
  /// Not in a group.
  off,

  /// Joining and measuring the clock difference.
  syncing,

  /// Fetching the song from the Player.
  downloading,

  /// Joined, nothing is playing.
  idle,

  /// Playing along with the Player.
  playing,

  /// Something is wrong (see [GroupStatus.message]).
  problem,
}

/// What the Group card shows.
class GroupStatus {
  const GroupStatus({
    this.phase = GroupPhase.off,
    this.message = '',
    this.offsetMs,
    this.rttMs,
    this.spreadMs,
    this.driftMs,
    this.nudgeMs = 0,
    this.title = '',
    this.available = true,
  });

  final GroupPhase phase;

  /// Plain-language detail for [GroupPhase.problem] and waiting states.
  final String message;

  /// Player clock minus this phone's clock, in ms.
  final double? offsetMs;
  final double? rttMs;
  final double? spreadMs;

  /// How far this phone's audio is from where it should be, in ms (positive =
  /// ahead). Only while playing.
  final double? driftMs;

  /// The manual latency adjustment for this phone, in ms.
  final int nudgeMs;
  final String title;

  /// False when group play cannot be used right now (not connected locally).
  final bool available;

  bool get isOn => phase != GroupPhase.off;

  GroupStatus copyWith({
    GroupPhase? phase,
    String? message,
    double? offsetMs,
    double? rttMs,
    double? spreadMs,
    double? driftMs,
    bool clearDrift = false,
    int? nudgeMs,
    String? title,
    bool? available,
  }) =>
      GroupStatus(
        phase: phase ?? this.phase,
        message: message ?? this.message,
        offsetMs: offsetMs ?? this.offsetMs,
        rttMs: rttMs ?? this.rttMs,
        spreadMs: spreadMs ?? this.spreadMs,
        driftMs: clearDrift ? null : (driftMs ?? this.driftMs),
        nudgeMs: nudgeMs ?? this.nudgeMs,
        title: title ?? this.title,
        available: available ?? this.available,
      );
}

/// This phone playing the Player's song along with it. The real thing needs
/// audio and the local network, so it only exists in the phone app; the web
/// Controller has none (the provider is null there).
abstract class GroupFollower {
  GroupStatus get status;
  Stream<GroupStatus> get statusStream;

  /// Starts playing along. Throws a message-carrying exception if it cannot.
  Future<void> join();
  Future<void> leave();

  /// Latency adjustment in ms (positive when this phone sounds late), saved on
  /// this phone.
  Future<void> setNudgeMs(int ms);

  /// Measures the clock difference again.
  Future<void> resync();
}
