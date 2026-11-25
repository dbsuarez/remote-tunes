import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import 'guide_doc.dart';

/// A short guide to what the app does and how to use the parts that are not
/// obvious.
class HelpScreen extends StatefulWidget {
  const HelpScreen({super.key, this.loadGuide});

  /// Where the guide's text comes from (tests give their own).
  final Future<String> Function()? loadGuide;

  /// The guide bundled with the app (the same file as docs/22_USER_GUIDE.md).
  static const guideAsset = 'docs/22_USER_GUIDE.md';

  static const topics = <(String, String)>[
    (
      'Playing your music',
      'Use the + button in the Library tab to add songs or a whole folder. Tap a song to play it; '
          'Now Playing has the controls, the lyrics (the button on the cover) and the queue (swipe up '
          'the handle at the bottom).'
    ),
    (
      'Control another phone',
      'Tap the chip at the top and choose "Control another phone". On the other phone choose '
          '"Start remote playback": it shows a QR code and a pairing code. Scan or type it, then Accept. '
          'After that the same screens control that phone. Nothing listens on the network until you '
          'start remote playback.'
    ),
    (
      'Play along on two phones',
      'While controlling another phone, the Group play card on Now Playing lets this phone play the '
          'same song in sync. "Auto-align" listens to a short click track to line the two up.'
    ),
    (
      'Search and playlists',
      'Search looks through songs, albums, artists and folders. Long-press a song, folder or search '
          'result to pick several, then add them to the queue or a playlist. The Library list also has '
          'Genres, Years and Album Artists (Settings > Update tags from files fills them in).'
    ),
    (
      'Sound',
      'The equalizer (icon at the top) has presets, bands, preamp, bass and treble. Settings has '
          'Crossfade, and "Even out loudness" for files with Replay Gain tags.'
    ),
    (
      'Updates',
      'Settings > App updates checks GitHub for a newer version and installs it. "What\'s new" in this '
          'menu shows what changed.'
    ),
    (
      'Privacy',
      'Your music never leaves your phones. The few things that use the internet (lyrics, album art, '
          'the Online Library, updates) only send what they need, and can be switched off in Settings.'
    ),
  ];

  @override
  State<HelpScreen> createState() => _HelpScreenState();
}

class _HelpScreenState extends State<HelpScreen> {
  GuideDoc? _guide;
  bool _failed = false;
  String _query = '';
  final _search = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final text = await (widget.loadGuide ?? () => rootBundle.loadString(HelpScreen.guideAsset))();
      if (mounted) setState(() => _guide = GuideDoc.parse(text));
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final guide = _guide;
    final searching = _query.trim().isNotEmpty;
    final found = guide?.search(_query) ?? const <GuideSection>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Help')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // The quick start stays up top; the full guide is below it.
            if (!searching)
              for (final (title, text) in HelpScreen.topics) ...[
                Text(title, style: theme.textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(text,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                const SizedBox(height: 20),
              ],
            Text('The full guide', style: theme.textTheme.titleLarge),
            const SizedBox(height: 8),
            TextField(
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search the guide (try "crossfade")',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: searching
                    ? IconButton(
                        tooltip: 'Clear',
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(() {
                          _search.clear();
                          _query = '';
                        }),
                      )
                    : null,
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            if (_failed)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('The guide could not be opened.'),
              )
            else if (guide == null)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (found.isEmpty)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Text('Nothing in the guide matches that.'),
              )
            else ...[
              if (!searching)
                for (final b in guide.intro) guideBlockWidget(context, b),
              for (final section in found)
                ExpansionTile(
                  // A new key when searching, so matches open by themselves.
                  key: ValueKey('${section.title}|$searching'),
                  initiallyExpanded: searching,
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 12),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  title: Text(section.title, style: theme.textTheme.titleMedium),
                  children: [for (final b in section.blocks) guideBlockWidget(context, b)],
                ),
            ],
          ],
        ),
      ),
    );
  }
}
