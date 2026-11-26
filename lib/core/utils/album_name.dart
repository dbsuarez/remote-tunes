/// Whether [album] names an album. Songs with no album tag are stored as "Unknown album": that is a
/// placeholder, not an album, so those songs must never share (or take) each other's cover.
bool isRealAlbum(String? album) {
  final a = (album ?? '').trim().toLowerCase();
  return a.isNotEmpty && a != 'unknown album' && a != '<unknown>' && a != 'unknown';
}
