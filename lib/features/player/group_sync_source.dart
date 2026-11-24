/// What the Player's engine offers for group play (a second phone playing the
/// same song in sync).
abstract class GroupSyncSource {
  /// Where the playing track is right now, in milliseconds, or null if nothing
  /// is loaded. Read at the instant it is asked (not the last second-tick).
  int? get positionMsNow;

  /// The library id of the song that will play after the current one, if it is
  /// a library song (so the other phone can fetch it ahead of time).
  int? get nextLibrarySongId;
}
