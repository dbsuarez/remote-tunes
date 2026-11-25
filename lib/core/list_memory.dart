/// Remembers which audiobook of a list was playing last, so "Play" on that list carries on from
/// there. The phone's player implements it; the web Controller has none.
abstract class ListMemory {
  /// The song the list was left at (null: none, or it is not an audiobook).
  Future<int?> positionFor(String key);

  /// The list the next songs are played from (null: not from a list).
  void setActive(String? key);
}

/// A name for a list that stays the same between runs: `playlist:3`, `folder:99`,
/// `album:Artist|Album`, `artist:Name`, `group:genre|Rock`, or `songs` for the whole library.
String listKeyFor({
  int? playlistId,
  int? folderId,
  String? artist,
  String? album,
  String? groupKind,
  String? groupValue,
}) {
  if (playlistId != null) return 'playlist:$playlistId';
  if (folderId != null) return 'folder:$folderId';
  if (groupValue != null) return 'group:${groupKind ?? ''}|$groupValue';
  if (album != null) return 'album:${artist ?? ''}|$album';
  if (artist != null) return 'artist:$artist';
  return 'songs';
}
