import 'package:flutter/material.dart';

/// One piece of the guide.
sealed class GuideBlock {
  const GuideBlock();

  /// The block's text without the markings (for searching).
  String get plain;
}

class GuideParagraph extends GuideBlock {
  const GuideParagraph(this.text);
  final String text;
  @override
  String get plain => _strip(text);
}

class GuideSubheading extends GuideBlock {
  const GuideSubheading(this.text);
  final String text;
  @override
  String get plain => _strip(text);
}

class GuideBullet extends GuideBlock {
  const GuideBullet(this.text, {this.number});
  final String text;

  /// 1, 2, 3... for a numbered step; null for a bullet.
  final int? number;
  @override
  String get plain => _strip(text);
}

/// A section of the guide (a `##` heading and what is under it).
class GuideSection {
  GuideSection(this.title, this.blocks);

  final String title;
  final List<GuideBlock> blocks;

  String get plain => '$title ${blocks.map((b) => b.plain).join(' ')}'.toLowerCase();
}

String _strip(String s) => s
    .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!)
    .replaceAll('**', '')
    .replaceAll('`', '')
    .replaceAll('*', '');

/// The guide, read from its Markdown: an introduction and its sections.
///
/// Only what the guide uses is understood: `#` and `##` and `###` headings,
/// paragraphs, `-` bullets, `1.` steps, and **bold**, *italic*, `code` and
/// [links] (shown as their text) inside a line.
class GuideDoc {
  GuideDoc(this.title, this.intro, this.sections);

  final String title;
  final List<GuideBlock> intro;
  final List<GuideSection> sections;

  factory GuideDoc.parse(String markdown) {
    var title = 'Guide';
    final intro = <GuideBlock>[];
    final sections = <GuideSection>[];
    var current = intro;
    final para = <String>[];

    void flush() {
      if (para.isNotEmpty) {
        current.add(GuideParagraph(para.join(' ')));
        para.clear();
      }
    }

    for (final raw in markdown.split('\n')) {
      final line = raw.trimRight();
      if (line.trim().isEmpty) {
        flush();
      } else if (line.trim() == '---') {
        flush();
      } else if (line.startsWith('### ')) {
        flush();
        current.add(GuideSubheading(line.substring(4).trim()));
      } else if (line.startsWith('## ')) {
        flush();
        final t = line.substring(3).trim().replaceFirst(RegExp(r'^\d+\.\s*'), '');
        final blocks = <GuideBlock>[];
        sections.add(GuideSection(t, blocks));
        current = blocks;
      } else if (line.startsWith('# ')) {
        flush();
        title = line.substring(2).trim();
      } else if (RegExp(r'^\s*[-*] ').hasMatch(line)) {
        flush();
        current.add(GuideBullet(line.replaceFirst(RegExp(r'^\s*[-*] '), '').trim()));
      } else if (RegExp(r'^\s*\d+\. ').hasMatch(line)) {
        flush();
        final m = RegExp(r'^\s*(\d+)\. (.*)').firstMatch(line)!;
        current.add(GuideBullet(m[2]!.trim(), number: int.parse(m[1]!)));
      } else {
        para.add(line.trim());
      }
    }
    flush();
    return GuideDoc(title, intro, sections);
  }

  /// Sections that mention every word of [query] (all of them when it is empty).
  List<GuideSection> search(String query) {
    final words = query.toLowerCase().split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    if (words.isEmpty) return sections;
    return [
      for (final s in sections)
        if (words.every(s.plain.contains)) s,
    ];
  }
}

/// A line of the guide as styled text: **bold**, *italic*, `code`; links show as
/// their text.
TextSpan guideSpan(String text, TextStyle base) {
  final spans = <InlineSpan>[];
  final re = RegExp(r'\*\*(.+?)\*\*|`(.+?)`|\*(.+?)\*|\[([^\]]+)\]\([^)]*\)');
  var at = 0;
  for (final m in re.allMatches(text)) {
    if (m.start > at) spans.add(TextSpan(text: text.substring(at, m.start)));
    if (m[1] != null) {
      spans.add(TextSpan(text: m[1], style: const TextStyle(fontWeight: FontWeight.w700)));
    } else if (m[2] != null) {
      spans.add(TextSpan(
          text: m[2],
          style: TextStyle(
              fontFamily: 'monospace', backgroundColor: base.color?.withValues(alpha: 0.1))));
    } else if (m[3] != null) {
      spans.add(TextSpan(text: m[3], style: const TextStyle(fontStyle: FontStyle.italic)));
    } else {
      spans.add(TextSpan(text: m[4]));
    }
    at = m.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return TextSpan(style: base, children: spans);
}

/// A block drawn for a phone screen.
Widget guideBlockWidget(BuildContext context, GuideBlock block) {
  final theme = Theme.of(context);
  final body = theme.textTheme.bodyMedium!;
  switch (block) {
    case GuideParagraph b:
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text.rich(guideSpan(b.text, body)),
      );
    case GuideSubheading b:
      return Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 6),
        child: Text(b.text, style: theme.textTheme.titleSmall),
      );
    case GuideBullet b:
      return Padding(
        padding: const EdgeInsets.only(bottom: 6, left: 4),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 22,
              child: Text(b.number == null ? '•' : '${b.number}.', style: body),
            ),
            Expanded(child: Text.rich(guideSpan(b.text, body))),
          ],
        ),
      );
  }
}
