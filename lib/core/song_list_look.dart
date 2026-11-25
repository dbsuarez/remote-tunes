/// How a song list is drawn ("View as" in List options).
enum SongListView {
  list('List', 'Cover, title and artist (the way it has always been)'),
  listSmall('List - small', 'A little smaller'),
  listCompact('List - compact', 'Small cover, tight rows: more songs on the screen'),
  noImages('List - no images', 'Text only'),
  oneLine('1 line', 'Title and artist on one line'),
  grid('Grid', 'Big covers side by side');

  const SongListView(this.label, this.hint);
  final String label;
  final String hint;

  static SongListView parse(String? name) =>
      values.firstWhere((v) => v.name == name, orElse: () => SongListView.list);
}

/// The look chosen for one kind of list (All songs, an album, a playlist...).
class ListLook {
  const ListLook({this.view = SongListView.list, this.titlesOnly = false});

  final SongListView view;

  /// Only the song title (no artist / album line).
  final bool titlesOnly;

  static const standard = ListLook();

  bool get isStandard => view == SongListView.list && !titlesOnly;

  ListLook copyWith({SongListView? view, bool? titlesOnly}) =>
      ListLook(view: view ?? this.view, titlesOnly: titlesOnly ?? this.titlesOnly);

  String encode() => '${view.name}|${titlesOnly ? 1 : 0}';

  static ListLook parse(String? s) {
    if (s == null) return standard;
    final p = s.split('|');
    return ListLook(view: SongListView.parse(p.first), titlesOnly: p.length > 1 && p[1] == '1');
  }

  @override
  bool operator ==(Object other) =>
      other is ListLook && other.view == view && other.titlesOnly == titlesOnly;

  @override
  int get hashCode => Object.hash(view, titlesOnly);
}

/// The names of the kinds of list that remember their own look, and what to call them.
const listKindLabels = <String, String>{
  'songs': 'All songs',
  'favorites': 'Favorites',
  'recent': 'Recently played',
  'top': 'Most played',
  'skipped': 'Most skipped',
  'never': 'Never played',
  'newest': 'Recently added',
  'album': 'Album songs',
  'artist': 'Artist songs',
  'playlist': 'Playlist songs',
  'folder': 'Folder songs',
  'group': 'Genre, year and composer songs',
};

/// The saved looks as one text (`kind=view|t;kind=view|t`) and back.
String encodeListLooks(Map<String, ListLook> looks) => [
      for (final e in looks.entries)
        if (!e.value.isStandard) '${e.key}=${e.value.encode()}',
    ].join(';');

Map<String, ListLook> decodeListLooks(String? raw) {
  if (raw == null || raw.isEmpty) return const {};
  final out = <String, ListLook>{};
  for (final part in raw.split(';')) {
    final i = part.indexOf('=');
    if (i <= 0) continue;
    final k = part.substring(0, i);
    if (!listKindLabels.containsKey(k)) continue;
    out[k] = ListLook.parse(part.substring(i + 1));
  }
  return out;
}
