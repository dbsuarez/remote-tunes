import 'package:flutter/material.dart';

/// The menu: shortcuts to the parts of the app, and the pages that are not tabs.
class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.onNowPlaying,
    required this.onLyrics,
    required this.onLibrary,
    required this.onPlaylists,
    required this.onSearch,
    required this.onQueue,
    required this.onEqualizer,
    required this.onRemotePlayback,
    required this.onSettings,
    required this.onChangelog,
    required this.onHelp,
    this.onSkins,
    this.onInsights,
    this.showEqualizer = true,
    this.version,
    this.updateAvailable = false,
  });

  /// The installed version ("1.0.2"), shown under the name.
  final String? version;

  /// A newer version is out: a note under the version opens Settings.
  final bool updateAvailable;

  final VoidCallback onNowPlaying;
  final VoidCallback onLyrics;
  final VoidCallback onLibrary;
  final VoidCallback onPlaylists;
  final VoidCallback onSearch;
  final VoidCallback onQueue;
  final VoidCallback onEqualizer;
  final VoidCallback onRemotePlayback;
  final VoidCallback onSettings;
  final VoidCallback onChangelog;
  final VoidCallback onHelp;

  /// What the library says about itself (null: not shown, e.g. for another phone's library).
  final VoidCallback? onInsights;

  /// Skin settings (null: not shown).
  final VoidCallback? onSkins;

  /// The equalizer is for this phone's own music only.
  final bool showEqualizer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    /// Closes the menu, then does [action].
    Widget item(IconData icon, String label, VoidCallback action) => ListTile(
          leading: Icon(icon),
          title: Text(label),
          onTap: () {
            Navigator.of(context).pop();
            action();
          },
        );

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('RemoteTunes',
                      style: theme.textTheme.titleLarge?.copyWith(color: theme.colorScheme.primary)),
                  if (version != null)
                    Text('Version $version',
                        key: const Key('drawer-version'),
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
            if (updateAvailable)
              ListTile(
                key: const Key('drawer-update'),
                dense: true,
                leading: Icon(Icons.system_update_rounded, color: theme.colorScheme.primary),
                title: const Text('A new version is available'),
                onTap: () {
                  Navigator.of(context).pop();
                  onSettings();
                },
              ),
            item(Icons.play_circle_outline_rounded, 'Now Playing', onNowPlaying),
            item(Icons.lyrics_outlined, 'Lyrics', onLyrics),
            item(Icons.library_music_outlined, 'Library', onLibrary),
            item(Icons.queue_music_rounded, 'Playlists', onPlaylists),
            item(Icons.search_rounded, 'Search', onSearch),
            item(Icons.format_list_numbered_rounded, 'Queue', onQueue),
            const Divider(),
            if (showEqualizer) item(Icons.equalizer_rounded, 'Equalizer', onEqualizer),
            if (onInsights != null) item(Icons.insights_rounded, 'Insights', onInsights!),
            item(Icons.cast_connected_rounded, 'Remote playback', onRemotePlayback),
            if (onSkins != null) item(Icons.palette_outlined, 'Skin settings', onSkins!),
            item(Icons.settings_rounded, 'Settings', onSettings),
            const Divider(),
            item(Icons.new_releases_outlined, "What's new", onChangelog),
            item(Icons.help_outline_rounded, 'Help', onHelp),
          ],
        ),
      ),
    );
  }
}
