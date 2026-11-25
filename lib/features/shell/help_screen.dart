import 'package:flutter/material.dart';

/// A short guide to what the app does and how to use the parts that are not
/// obvious.
class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});

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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Help')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final (title, text) in topics) ...[
              Text(title, style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(text,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              const SizedBox(height: 20),
            ],
          ],
        ),
      ),
    );
  }
}
