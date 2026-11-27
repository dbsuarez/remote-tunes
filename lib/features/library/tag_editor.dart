/// Changes some tags of an MP3, M4A or FLAC file and leaves every other byte of its information as it
/// was: lyrics, loudness values, comments and anything the app does not know. Only the changed entries
/// are rewritten; the music itself is copied unread.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

enum TagField { title, artist, album, albumArtist, genre, year, composer, track }

/// The file is of a kind handled here, but built in a way that cannot be changed safely.
class TagUnsupported implements Exception {
  const TagUnsupported([this.why = '']);
  final String why;
  @override
  String toString() => 'TagUnsupported $why';
}

/// A piece of the new file: bytes of its own, or a stretch of the old file.
class _Piece {
  _Piece(this.bytes)
      : from = 0,
        length = bytes!.length;
  _Piece.copy(this.from, this.length) : bytes = null;
  final Uint8List? bytes;
  final int from;
  final int length;
}

/// Writes [source] with [fields] changed (a null value takes a field away) and, if given, [cover] (a
/// JPEG) as its front cover, into [target]. Gives false, writing nothing, for kinds of files not handled
/// here. Throws [TagUnsupported] for one that should not be touched.
bool rewriteTags(File source, File target, Map<TagField, String?> fields, {Uint8List? cover}) {
  final input = source.openSync();
  try {
    final length = input.lengthSync();
    final head = _read(input, 0, length < 12 ? length : 12);
    if (head.length < 12) return false;
    final List<_Piece> pieces;
    if (_text(head, 0, 3) == 'ID3' || (head[0] == 0xFF && (head[1] & 0xE0) == 0xE0 && (head[1] & 0x06) != 0)) {
      pieces = _mp3(input, length, fields, cover);
    } else if (_text(head, 0, 4) == 'fLaC') {
      pieces = _flac(input, length, fields, cover);
    } else if (_text(head, 4, 4) == 'ftyp') {
      pieces = _mp4(input, length, fields, cover);
    } else {
      return false;
    }
    final out = target.openSync(mode: FileMode.write);
    try {
      final buffer = Uint8List(1 << 20);
      for (final piece in pieces) {
        if (piece.bytes != null) {
          out.writeFromSync(piece.bytes!);
          continue;
        }
        input.setPositionSync(piece.from);
        var left = piece.length;
        while (left > 0) {
          final n = input.readIntoSync(buffer, 0, left < buffer.length ? left : buffer.length);
          if (n <= 0) throw const TagUnsupported('the file ended early');
          out.writeFromSync(buffer, 0, n);
          left -= n;
        }
      }
      out.flushSync();
    } finally {
      out.closeSync();
    }
    return true;
  } finally {
    input.closeSync();
  }
}

Uint8List _read(RandomAccessFile f, int at, int length) {
  f.setPositionSync(at);
  final out = f.readSync(length);
  if (out.length != length) throw const TagUnsupported('the file ended early');
  return out;
}

String _text(List<int> b, int at, int length) => String.fromCharCodes(b, at, at + length);

int _be(List<int> b, int at, int length) {
  var v = 0;
  for (var i = 0; i < length; i++) {
    v = (v << 8) | b[at + i];
  }
  return v;
}

Uint8List _beBytes(int v, int length) =>
    Uint8List.fromList([for (var i = length - 1; i >= 0; i--) (v >> (8 * i)) & 0xFF]);

Uint8List _join(List<List<int>> parts) {
  final b = BytesBuilder(copy: false);
  for (final p in parts) {
    b.add(p);
  }
  return b.toBytes();
}

// ------------------------------------------------------------------ MP3 (ID3v2)

int _syncsafe(List<int> b, int at) {
  if ((b[at] | b[at + 1] | b[at + 2] | b[at + 3]) & 0x80 != 0) throw const TagUnsupported('bad size');
  return (b[at] << 21) | (b[at + 1] << 14) | (b[at + 2] << 7) | b[at + 3];
}

Uint8List _toSyncsafe(int v) =>
    Uint8List.fromList([(v >> 21) & 0x7F, (v >> 14) & 0x7F, (v >> 7) & 0x7F, v & 0x7F]);

List<_Piece> _mp3(RandomAccessFile f, int length, Map<TagField, String?> fields, Uint8List? cover) {
  var version = 3;
  var audioAt = 0;
  final kept = <({String id, Uint8List frame, Uint8List body})>[];
  final head = _read(f, 0, 10);
  if (_text(head, 0, 3) == 'ID3') {
    version = head[3];
    final flags = head[5];
    if (version != 3 && version != 4) throw TagUnsupported('ID3v2.$version');
    // Unsynchronised tags would have to be decoded and encoded again.
    if (flags & 0x80 != 0) throw const TagUnsupported('unsynchronised');
    final size = _syncsafe(head, 6);
    audioAt = 10 + size + (version == 4 && flags & 0x10 != 0 ? 10 : 0);
    if (audioAt > length) throw const TagUnsupported('tag longer than the file');
    final tag = _read(f, 10, size);
    var at = 0;
    // An extended header holds nothing worth keeping.
    if (flags & 0x40 != 0 && size >= 4) at = version == 4 ? _syncsafe(tag, 0) : _be(tag, 0, 4) + 4;
    while (at + 10 <= size && tag[at] != 0) {
      final id = _text(tag, at, 4);
      if (!RegExp(r'^[A-Z0-9]{4}$').hasMatch(id)) throw const TagUnsupported('unreadable frame');
      final n = version == 4 ? _syncsafe(tag, at + 4) : _be(tag, at + 4, 4);
      if (n < 0 || at + 10 + n > size) throw const TagUnsupported('unreadable frame size');
      kept.add((
        id: id,
        frame: Uint8List.sublistView(tag, at, at + 10 + n),
        body: Uint8List.sublistView(tag, at + 10, at + 10 + n),
      ));
      at += 10 + n;
    }
  }

  Uint8List frame(String id, List<int> body) =>
      _join([ascii.encode(id), version == 4 ? _toSyncsafe(body.length) : _beBytes(body.length, 4), [0, 0], body]);

  /// The text of a frame (only for the numbers of a track).
  String valueOf(Uint8List body) {
    if (body.isEmpty) return '';
    final data = body.sublist(1);
    final text = body[0] == 1 || body[0] == 2
        ? String.fromCharCodes([
            for (var i = data.length >= 2 && data[0] == 0xFF && data[1] == 0xFE ? 2 : 0; i + 1 < data.length; i += 2)
              data[i] | (data[i + 1] << 8)
          ])
        : latin1.decode(data);
    return text.replaceAll('\u0000', '').trim();
  }

  const ids = {
    TagField.title: ['TIT2'],
    TagField.artist: ['TPE1'],
    TagField.album: ['TALB'],
    TagField.albumArtist: ['TPE2'],
    TagField.genre: ['TCON'],
    TagField.year: ['TYER', 'TDRC'],
    TagField.composer: ['TCOM'],
    TagField.track: ['TRCK'],
  };
  final added = <Uint8List>[];
  for (final change in fields.entries) {
    final names = ids[change.key]!;
    var value = change.value;
    if (change.key == TagField.track && value != null) {
      // "3/12" keeps its total.
      final old = kept.where((k) => k.id == 'TRCK').map((k) => valueOf(k.body)).firstOrNull ?? '';
      final slash = old.indexOf('/');
      if (slash >= 0) value = '$value${old.substring(slash)}';
    }
    kept.removeWhere((k) => names.contains(k.id));
    if (value == null) continue;
    final id = change.key == TagField.year && version == 4 ? 'TDRC' : names.first;
    final body = version == 4
        ? [3, ...utf8.encode(value)]
        : [1, 0xFF, 0xFE, for (final u in value.codeUnits) ...[u & 0xFF, u >> 8]];
    added.add(frame(id, body));
  }
  if (cover != null) {
    // The front cover and unnamed pictures give way; a back cover and the like stay.
    kept.removeWhere((k) {
      if (k.id != 'APIC') return false;
      final end = k.body.indexOf(0, 1);
      return end < 0 || end + 1 >= k.body.length || k.body[end + 1] == 3 || k.body[end + 1] == 0;
    });
    added.insert(0, frame('APIC', [0, ...ascii.encode('image/jpeg'), 0, 3, 0, ...cover]));
  }
  final frames = _join([...added, for (final k in kept) k.frame, Uint8List(1024)]);
  return [
    _Piece(_join([ascii.encode('ID3'), [version, 0, 0], _toSyncsafe(frames.length), frames])),
    _Piece.copy(audioAt, length - audioAt),
  ];
}

// ------------------------------------------------------------------ FLAC

List<_Piece> _flac(RandomAccessFile f, int length, Map<TagField, String?> fields, Uint8List? cover) {
  final blocks = <({int type, Uint8List data})>[];
  var at = 4;
  var last = false;
  while (!last) {
    if (at + 4 > length) throw const TagUnsupported('unfinished blocks');
    final h = _read(f, at, 4);
    last = h[0] & 0x80 != 0;
    final n = _be(h, 1, 3);
    if (at + 4 + n > length) throw const TagUnsupported('block longer than the file');
    blocks.add((type: h[0] & 0x7F, data: _read(f, at + 4, n)));
    at += 4 + n;
  }
  if (blocks.isEmpty || blocks.first.type != 0) throw const TagUnsupported('no stream info');

  Uint8List le(int v) => Uint8List.fromList([v & 0xFF, (v >> 8) & 0xFF, (v >> 16) & 0xFF, (v >> 24) & 0xFF]);
  int fromLe(Uint8List b, int at) => b[at] | (b[at + 1] << 8) | (b[at + 2] << 16) | (b[at + 3] << 24);

  Uint8List comments(Uint8List? old) {
    var vendor = Uint8List.fromList(utf8.encode('RemoteTunes'));
    final entries = <Uint8List>[];
    if (old != null) {
      var p = 0;
      Uint8List take() {
        if (p + 4 > old.length) throw const TagUnsupported('unreadable comments');
        final n = fromLe(old, p);
        if (n < 0 || p + 4 + n > old.length) throw const TagUnsupported('unreadable comments');
        final out = Uint8List.sublistView(old, p + 4, p + 4 + n);
        p += 4 + n;
        return out;
      }

      vendor = take();
      if (p + 4 > old.length) throw const TagUnsupported('unreadable comments');
      final count = fromLe(old, p);
      p += 4;
      for (var i = 0; i < count; i++) {
        entries.add(take());
      }
    }
    const keys = {
      TagField.title: ['TITLE'],
      TagField.artist: ['ARTIST'],
      TagField.album: ['ALBUM'],
      TagField.albumArtist: ['ALBUMARTIST', 'ALBUM ARTIST', 'ALBUM_ARTIST'],
      TagField.genre: ['GENRE'],
      TagField.year: ['DATE', 'YEAR'],
      TagField.composer: ['COMPOSER'],
      TagField.track: ['TRACKNUMBER'],
    };
    for (final change in fields.entries) {
      final names = keys[change.key]!;
      entries.removeWhere((e) {
        final eq = e.indexOf(0x3D);
        return eq > 0 && names.contains(latin1.decode(e.sublist(0, eq)).toUpperCase());
      });
      if (change.value != null) {
        entries.add(Uint8List.fromList(utf8.encode('${names.first}=${change.value}')));
      }
    }
    return _join([
      le(vendor.length),
      vendor,
      le(entries.length),
      for (final e in entries) ...[le(e.length), e],
    ]);
  }

  final old = blocks.where((b) => b.type == 4).map((b) => b.data).firstOrNull;
  final out = <({int type, Uint8List data})>[
    blocks.first,
    if (fields.isNotEmpty) (type: 4, data: comments(old)) else if (old != null) (type: 4, data: old),
    if (cover != null)
      (
        type: 6,
        data: _join([
          _beBytes(3, 4),
          _beBytes(10, 4),
          ascii.encode('image/jpeg'),
          _beBytes(0, 4), // no description
          Uint8List(16), // size and colors: left for the reader to find
          _beBytes(cover.length, 4),
          cover,
        ])
      ),
    for (final b in blocks.skip(1))
      if (b.type != 4 &&
          b.type != 1 &&
          !(cover != null && b.type == 6 && b.data.length >= 4 && (_be(b.data, 0, 4) == 3 || _be(b.data, 0, 4) == 0)))
        b,
    (type: 1, data: Uint8List(1024)),
  ];
  if (out.any((b) => b.data.length > 0xFFFFFF)) throw const TagUnsupported('a block too large');
  return [
    _Piece(_join([
      ascii.encode('fLaC'),
      for (var i = 0; i < out.length; i++) ...[
        [out[i].type | (i == out.length - 1 ? 0x80 : 0)],
        _beBytes(out[i].data.length, 3),
        out[i].data,
      ],
    ])),
    _Piece.copy(at, length - at),
  ];
}

// ------------------------------------------------------------------ M4A / MP4

/// A box: its four-letter kind and what is inside it.
class _Box {
  _Box(this.kind, this.body);
  final String kind;
  Uint8List body;
  Uint8List get bytes => _join([_beBytes(body.length + 8, 4), latin1.encode(kind), body]);
}

List<_Box> _boxes(Uint8List data, [int from = 0]) {
  final out = <_Box>[];
  var at = from;
  while (at + 8 <= data.length) {
    var size = _be(data, at, 4);
    var header = 8;
    if (size == 1) {
      if (at + 16 > data.length) throw const TagUnsupported('unreadable box');
      size = _be(data, at + 8, 8);
      header = 16;
    } else if (size == 0) {
      size = data.length - at;
    }
    if (size < header || at + size > data.length) throw const TagUnsupported('unreadable box');
    out.add(_Box(latin1.decode(data.sublist(at + 4, at + 8)), Uint8List.sublistView(data, at + header, at + size)));
    at += size;
  }
  // A few files end a list with four zero bytes.
  if (at != data.length && !(data.length - at == 4 && _be(data, at, 4) == 0)) {
    throw const TagUnsupported('stray bytes in a box');
  }
  return out;
}

/// Replaces (or adds) the child [kind] of a list of boxes by what [change] makes of it.
List<int> _child(List<_Box> boxes, String kind, Uint8List Function(Uint8List? old) change) {
  final at = boxes.indexWhere((b) => b.kind == kind);
  if (at < 0) {
    boxes.add(_Box(kind, change(null)));
  } else {
    boxes[at].body = change(boxes[at].body);
  }
  return const [];
}

Uint8List _all(List<_Box> boxes) => _join([for (final b in boxes) b.bytes]);

/// Moves every position of music data that lies at or after [from] by [by].
Uint8List _shift(Uint8List body, String kind, int from, int by) {
  if (kind == 'stco' || kind == 'co64') {
    final wide = kind == 'co64' ? 8 : 4;
    final out = Uint8List.fromList(body);
    final count = _be(out, 4, 4);
    if (8 + count * wide > out.length) throw const TagUnsupported('unreadable offsets');
    for (var i = 0; i < count; i++) {
      final at = 8 + i * wide;
      final v = _be(out, at, wide);
      if (v < from) continue;
      final moved = v + by;
      if (moved < 0 || (wide == 4 && moved > 0xFFFFFFFF)) throw const TagUnsupported('offset out of range');
      out.setRange(at, at + wide, _beBytes(moved, wide));
    }
    return out;
  }
  if (const {'trak', 'mdia', 'minf', 'stbl', 'moov'}.contains(kind)) {
    return _join([for (final b in _boxes(body)) _Box(b.kind, _shift(b.body, b.kind, from, by)).bytes]);
  }
  return body;
}

List<_Piece> _mp4(RandomAccessFile f, int length, Map<TagField, String?> fields, Uint8List? cover) {
  ({int at, int size, int header})? moov;
  var at = 0;
  while (at + 8 <= length) {
    final h = _read(f, at, 8);
    var size = _be(h, 0, 4);
    var header = 8;
    if (size == 1) {
      size = _be(_read(f, at + 8, 8), 0, 8);
      header = 16;
    } else if (size == 0) {
      size = length - at;
    }
    if (size < header || at + size > length) throw const TagUnsupported('unreadable file');
    final kind = _text(h, 4, 4);
    // Music in fragments keeps positions in places not handled here.
    if (kind == 'moof') throw const TagUnsupported('fragmented');
    if (kind == 'moov') moov = (at: at, size: size, header: header);
    at += size;
  }
  if (moov == null) throw const TagUnsupported('no movie box');
  if (moov.size > 64 * 1024 * 1024) throw const TagUnsupported('movie box too large');

  Uint8List data(int type, List<int> payload) => _Box('data', _join([_beBytes(type, 4), Uint8List(4), payload])).bytes;

  Uint8List items(Uint8List? old) {
    final list = old == null ? <_Box>[] : _boxes(old);
    const names = {
      TagField.title: '©nam',
      TagField.artist: '©ART',
      TagField.album: '©alb',
      TagField.albumArtist: 'aART',
      TagField.genre: '©gen',
      TagField.year: '©day',
      TagField.composer: '©wrt',
      TagField.track: 'trkn',
    };
    for (final change in fields.entries) {
      final kind = names[change.key]!;
      var total = 0;
      if (change.key == TagField.track) {
        final track = list.where((b) => b.kind == 'trkn').firstOrNull;
        // data box: 8 header, 8 type and language, then 0, number, total.
        if (track != null && track.body.length >= 22) total = _be(track.body, 20, 2);
      }
      list.removeWhere((b) => b.kind == kind || (change.key == TagField.genre && b.kind == 'gnre'));
      final value = change.value;
      if (value == null) continue;
      if (change.key == TagField.track) {
        final number = int.tryParse(value);
        if (number == null || number < 0 || number > 0xFFFF) continue;
        list.add(_Box(kind, data(0, [0, 0, ..._beBytes(number, 2), ..._beBytes(total, 2), 0, 0])));
      } else {
        list.add(_Box(kind, data(1, utf8.encode(value))));
      }
    }
    if (cover != null) {
      list.removeWhere((b) => b.kind == 'covr');
      list.add(_Box('covr', data(13, cover)));
    }
    return _all(list);
  }

  Uint8List meta(Uint8List? old) {
    // Usually four bytes of version come first; some files go straight to the boxes.
    final plain = old != null && old.length >= 8 && _text(old, 4, 4) == 'hdlr';
    final start = old == null || plain ? 0 : 4;
    final list = old == null
        ? <_Box>[
            _Box('hdlr', _join([Uint8List(8), ascii.encode('mdirappl'), Uint8List(9)])),
          ]
        : _boxes(old, start);
    _child(list, 'ilst', items);
    return _join([if (!plain) Uint8List(4), _all(list)]);
  }

  Uint8List udta(Uint8List? old) {
    final list = old == null ? <_Box>[] : _boxes(old);
    _child(list, 'meta', meta);
    return _all(list);
  }

  final inside = _boxes(_read(f, moov.at + moov.header, moov.size - moov.header));
  _child(inside, 'udta', udta);
  final body = _all(inside);
  final end = moov.at + moov.size;
  final by = body.length + 8 - moov.size;
  // Music stored after this box moves with its size.
  final moved = by == 0 ? body : _shift(body, 'moov', end, by);
  return [
    _Piece.copy(0, moov.at),
    _Piece(_Box('moov', moved).bytes),
    _Piece.copy(end, length - end),
  ];
}
