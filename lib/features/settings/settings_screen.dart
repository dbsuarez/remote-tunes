// ignore_for_file: unused_local_variable
import '../cloud/cloud_settings_screen.dart';
import '../../core/visualizer_position.dart';
import '../library/music_folders_screen.dart';
import '../backup/backup_screen.dart';
import '../tagging/tag_cleanup_screen.dart';
import '../../providers/library_providers.dart';
import '../library/folder_choice.dart';
import '../player/visualizer.dart';
import 'file_access_tile.dart';
import 'package:flutter/material.dart';
import '../update/update_widgets.dart';
import 'album_art_dialog.dart';
import '../library/import_actions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models/enums.dart';
import '../../core/online_defaults.dart';
import '../../core/router/app_router.dart';
import '../../core/song_list_style.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/settings_repository.dart';
import '../../providers/connection_providers.dart';
import '../../providers/providers.dart';
import '../external/external_limits.dart';
import '../home/widgets/connection_mode_selector.dart';
import '../online/online_setup.dart';

/// One setting (or a few that belong together), with the words people look it up by.
class _Entry {
  const _Entry({
    required this.id,
    required this.title,
    required this.keywords,
    required this.build,
  });

  final String id;
  final String title;
  final String keywords;

  /// Draws it. [c] has what the old long page had at hand.
  final Widget Function(_Ctx c) build;
}

/// What a setting's widgets need.
class _Ctx {
  const _Ctx({
    required this.context,
    required this.ref,
    required this.s,
    required this.repo,
  });

  final BuildContext context;
  final WidgetRef ref;
  final AppSettings s;
  final SettingsRepository repo;

  ThemeData get theme => Theme.of(context);
}

class _Group {
  const _Group({
    required this.id,
    required this.title,
    required this.icon,
    required this.summary,
    required this.entries,
  });

  final String id;
  final String title;
  final IconData icon;
  final String Function(AppSettings s) summary;
  final List<_Entry> entries;
}

/// The groups on the front page, in the order shown.
final List<_Group> _groups = [
  _Group(
    id: 'playback',
    title: 'Playback and sound',
    icon: Icons.graphic_eq_rounded,
    summary: (s) =>
        'Crossfade ${s.crossfadeSeconds == 0 ? 'off' : '${s.crossfadeSeconds} s'}, loudness, equalizer, visualizer',
    entries: [
      _Entry(
        id: 'volume',
        title: 'Default volume',
        keywords: 'volume loudness level start',
        build: (c) {
          final context = c.context;
          final ref = c.ref;
          final s = c.s;
          final repo = c.repo;
          final theme = c.theme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _VolumeSetting(
                value: s.defaultVolume,
                onSave: repo.setDefaultVolume,
              ),
            ],
          );
        },
      ),
      _Entry(
        id: 'repeat',
        title: 'Repeat and shuffle',
        keywords: 'repeat shuffle remembered random',
        build: (c) {
          final context = c.context;
          final ref = c.ref;
          final s = c.s;
          final repo = c.repo;
          final theme = c.theme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Repeat and shuffle are remembered: they stay as you leave them with the buttons on Now Playing.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              Text('Repeat', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<RepeatMode>(
                  showSelectedIcon: false,
                  segments: [
                    for (final m in RepeatMode.values)
                      ButtonSegment(value: m, label: Text(m.label)),
                  ],
                  selected: {s.repeatMode},
                  onSelectionChanged: (v) => repo.setRepeatMode(v.first),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Shuffle'),
                value: s.shuffleEnabled,
                onChanged: repo.setShuffleEnabled,
              ),
            ],
          );
        },
      ),
      _Entry(
        id: 'crossfade',
        title: 'Crossfade',
        keywords: 'crossfade fade next song gapless seconds',
        build: (c) {
          final context = c.context;
          final ref = c.ref;
          final s = c.s;
          final repo = c.repo;
          final theme = c.theme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.compare_arrows_rounded),
                title: Text(
                  s.crossfadeSeconds == 0
                      ? 'Crossfade: off'
                      : 'Crossfade: ${s.crossfadeSeconds} seconds',
                ),
                subtitle: const Text(
                  'One song fades out while the next fades in. Only for songs on this phone, '
                  'and only when the next song is also a file here.',
                ),
              ),
              Slider(
                value: s.crossfadeSeconds.toDouble(),
                max: 12,
                divisions: 12,
                label: s.crossfadeSeconds == 0
                    ? 'Off'
                    : '${s.crossfadeSeconds} s',
                onChanged: (v) => repo.setCrossfadeSeconds(v.round()),
              ),
            ],
          );
        },
      ),
      _Entry(
        id: 'loudness',
        title: 'Even out loudness',
        keywords: 'loudness replay gain volume normalise tags',
        build: (c) {
          final context = c.context;
          final ref = c.ref;
          final s = c.s;
          final repo = c.repo;
          final theme = c.theme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.graphic_eq_rounded),
                title: const Text('Even out loudness'),
                subtitle: const Text(
                  'Turns loud songs down to the level in their Replay Gain tags, so songs sound '
                  'about equally loud. Run "Update tags from files" once to read the tags. '
                  'It never turns a song up.',
                ),
              ),
              RadioGroup<ReplayGainMode>(
                groupValue: s.replayGainMode,
                onChanged: (v) {
                  if (v != null) repo.setReplayGainMode(v);
                },
                child: Column(
                  children: [
                    for (final m in ReplayGainMode.values)
                      RadioListTile<ReplayGainMode>(
                        contentPadding: const EdgeInsets.only(left: 16),
                        dense: true,
                        value: m,
                        title: Text(m.label),
                      ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
      _Entry(
        id: 'eq',
        title: 'Equalizer',
        keywords: 'equalizer eq bass treble bands presets sound',
        build: (c) {
          final context = c.context;
          final ref = c.ref;
          final s = c.s;
          final repo = c.repo;
          final theme = c.theme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.equalizer_rounded),
                title: const Text('Equalizer'),
                subtitle: const Text(
                  'Presets and bands for the music on this phone.',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(AppRoutes.equalizer),
              ),
            ],
          );
        },
      ),
      _Entry(
        id: 'visualizer',
        title: 'Visualizer',
        keywords: 'visualizer bars equalizer animation microphone style',
        build: (c) {
          final context = c.context;
          final ref = c.ref;
          final s = c.s;
          final repo = c.repo;
          final theme = c.theme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Visualizer'),
                subtitle: const Text(
                  'Moving bars under the cover (or over it, see below) while music plays. Android asks for the microphone '
                  'permission to read the sound; nothing is recorded. Uses a little more battery.',
                ),
                value: s.visualizerEnabled,
                onChanged: (on) => switchVisualizer(context, repo, on),
              ),
              if (s.visualizerEnabled)
                SwitchListTile(
                  key: const ValueKey('viz-on-cover'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show it on the cover'),
                  subtitle: const Text(
                    'Draws it over the dimmed cover instead of under it. The lyrics and the visualizer '
                    'then never show together: opening the lyrics hides it.',
                  ),
                  value: s.visualizerOnCover,
                  onChanged: repo.setVisualizerOnCover,
                ),
              if (s.visualizerEnabled && s.visualizerOnCover)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Position on the cover', style: theme.textTheme.bodyMedium),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          for (final v in VisualizerCoverPosition.values)
                            ChoiceChip(
                              key: ValueKey('viz-pos-${v.name}'),
                              label: Text(v.label),
                              selected: VisualizerCoverPosition.parse(s.visualizerCoverPosition) == v,
                              onSelected: (_) => repo.setVisualizerCoverPosition(v.name),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              if (s.visualizerEnabled)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final v in VisualizerStyle.values)
                        ChoiceChip(
                          key: ValueKey('viz-${v.name}'),
                          label: Text(v.label),
                          tooltip: v.hint,
                          selected: s.visualizerStyle == v.name,
                          onSelected: (_) => repo.setVisualizerStyle(v.name),
                        ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
      _Entry(
        id: 'queuescroll',
        title: 'Queue opens at the song playing',
        keywords: 'queue scroll current playing',
        build: (c) {
          final context = c.context;
          final ref = c.ref;
          final s = c.s;
          final repo = c.repo;
          final theme = c.theme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Queue opens at the song playing'),
                subtitle: const Text(
                  'Going to the Queue scrolls to the song that is playing now. Switch off to keep the list where you left it.',
                ),
                value: s.queueScrollToCurrent,
                onChanged: repo.setQueueScrollToCurrent,
              ),
            ],
          );
        },
      ),
    ],
  ),
  _Group(
    id: 'library',
    title: 'Library',
    icon: Icons.library_music_outlined,
    summary: (s) => 'Music folders and rescan, album art, tags, excluded folders, counts',
    entries: [
      _Entry(
        id: 'musicfolders',
        title: 'Music folders and rescan',
        keywords: 'music folders rescan scan new songs library add folder refresh update',
        build: (c) {
          final context = c.context;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.folder_copy_outlined),
            title: const Text('Music folders and rescan'),
            subtitle: const Text(
              'The folders you added, and one tap to look for new songs in all of them.',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const MusicFoldersScreen()),
            ),
          );
        },
      ),
      _Entry(
        id: 'tagcleanup',
        title: 'Tag cleanup',
        keywords: 'tag cleanup clean fix missing artist album year auto tagging musicbrainz file names undo',
        build: (c) {
          final context = c.context;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.auto_fix_high_rounded),
            title: const Text('Tag cleanup'),
            subtitle: const Text(
              'Finds missing artists, albums and years, and fills them in from file names or MusicBrainz. You approve every change.',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const TagCleanupScreen()),
            ),
          );
        },
      ),
      _Entry(
        id: 'audiobooks',
        title: 'Audiobooks',
        keywords: 'audiobooks audiobook book spoken podcast remember place progress resume folders',
        build: (c) {
          final context = c.context;
          final ref = c.ref;
          final s = c.s;
          final repo = c.repo;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                key: const ValueKey('remember-audiobooks'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Remember my place in audiobooks'),
                subtitle: const Text(
                  'An audiobook carries on where you stopped, and Play on a list of audiobooks carries '
                  'on at the chapter you left. Music always starts at the beginning. Audiobooks live in '
                  'their own folders (Music folders and rescan > Audiobook folders), and stay out of '
                  'your music and shuffle.',
                ),
                value: s.rememberAudiobooks,
                onChanged: repo.setRememberAudiobooks,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('find-audiobooks'),
                  onPressed: () async {
                    final core = await ref.read(playerCoreProvider.future);
                    final n = await core.audiobooks?.findByTags() ?? 0;
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(
                          content: Text(n == 0
                              ? 'No more songs with an audiobook genre or in an "audiobook" folder.'
                              : 'Marked $n song${n == 1 ? '' : 's'} as audiobooks.')));
                  },
                  child: const Text('Find audiobooks by genre or folder name'),
                ),
              ),
            ],
          );
        },
      ),
      _Entry(
        id: 'artfinder',
        title: 'Find missing album art',
        keywords: 'album art cover finder musicbrainz pictures',
        build: (c) {
          final context = c.context;
          final ref = c.ref;
          final s = c.s;
          final repo = c.repo;
          final theme = c.theme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [const AlbumArtTile()],
          );
        },
      ),
      _Entry(
        id: 'tags',
        title: 'Update tags from files',
        keywords:
            'tags genre year album artist composer replay gain read files',
        build: (c) {
          final context = c.context;
          final ref = c.ref;
          final s = c.s;
          final repo = c.repo;
          final theme = c.theme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.sell_outlined),
                title: const Text('Update tags from files'),
                subtitle: const Text(
                  'Reads the genre, year and album artist of every song again, so the '
                  'Genres, Years and Album Artists lists fill in. Nothing is changed in the files.',
                ),
                onTap: () => refreshLibraryTags(context, ref),
              ),
            ],
          );
        },
      ),
      _Entry(
        id: 'rescanopen',
        title: 'Rescan when the app opens',
        keywords: 'rescan scan open start new songs folders automatic',
        build: (c) {
          final s = c.s;
          final repo = c.repo;
          return SwitchListTile(
            key: const ValueKey('rescan-on-open'),
            contentPadding: EdgeInsets.zero,
            title: const Text('Rescan when the app opens'),
            subtitle: const Text(
              'Checks your music folders for new songs each time RemoteTunes starts, quietly, '
              'and says so only if it added something. It never removes songs; a new folder is '
              'left for you to choose in Rescan music folders. Off by default.',
            ),
            value: s.rescanOnOpen,
            onChanged: repo.setRescanOnOpen,
          );
        },
      ),
      _Entry(
        id: 'leftout',
        title: 'Excluded from library',
        keywords: 'excluded exclude left out ignore folders songs hide',
        build: (c) {
          final context = c.context;
          final ref = c.ref;
          final s = c.s;
          final repo = c.repo;
          final theme = c.theme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_off_outlined),
                title: const Text('Excluded from library'),
                subtitle: const Text(
                  'Folders you unticked when adding music, and songs you removed. They are not added again.',
                ),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const LeftOutScreen(),
                  ),
                ),
              ),
            ],
          );
        },
      ),
      _Entry(
        id: 'playlog',
        title: 'Play history',
        keywords: 'play history log insights listening time record clear',
        build: (c) {
          final context = c.context;
          final ref = c.ref;
          final s = c.s;
          final repo = c.repo;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                key: const ValueKey('play-history'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Play history'),
                subtitle: const Text(
                  'Notes each song you play (when, how long you heard it, how it ended) for Insights. '
                  'It stays on this phone.',
                ),
                value: s.playHistory,
                onChanged: repo.setPlayHistory,
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton(
                  key: const ValueKey('clear-play-history'),
                  onPressed: () async {
                    final lib = ref.read(libraryRepositoryProvider);
                    final n = await lib.playEventCount();
                    if (!context.mounted) return;
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Clear the play history?'),
                        content: Text(n == 0
                            ? 'There is nothing recorded.'
                            : 'This forgets $n recorded play${n == 1 ? '' : 's'}. Play and skip counts stay as they are.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Clear')),
                        ],
                      ),
                    );
                    if (ok != true) return;
                    await lib.clearPlayEvents();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                        ..hideCurrentSnackBar()
                        ..showSnackBar(const SnackBar(content: Text('Play history cleared')));
                    }
                  },
                  child: const Text('Clear play history'),
                ),
              ),
            ],
          );
        },
      ),
      _Entry(
        id: 'reset',
        title: 'Reset play and skip counts',
        keywords: 'reset counts plays skips most played history',
        build: (c) {
          final context = c.context;
          final ref = c.ref;
          final s = c.s;
          final repo = c.repo;
          final theme = c.theme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.restart_alt_rounded),
                title: const Text('Reset play and skip counts'),
                subtitle: const Text(
                  'Starts Most played, Most skipped, Never played and Recent from zero. Your songs are not touched.',
                ),
                onTap: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Reset the counts?'),
                      content: const Text(
                        'How often each song was played and skipped, and when it was last played, will be forgotten.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                  );
                  if (ok != true) return;
                  final n = await ref
                      .read(libraryRepositoryProvider)
                      .resetListeningStats();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(
                        SnackBar(
                          content: Text(
                            'Counts reset for $n song${n == 1 ? '' : 's'}',
                          ),
                        ),
                      );
                  }
                },
              ),
            ],
          );
        },
      ),
      _Entry(
        id: 'fileaccess',
        title: 'All files access',
        keywords: 'files access permission write tags storage android 11',
        build: (c) {
          final context = c.context;
          final ref = c.ref;
          final s = c.s;
          final repo = c.repo;
          final theme = c.theme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [const FileAccessTile()],
          );
        },
      ),
    ],
  ),
  _Group(
    id: 'look',
    title: 'Look',
    icon: Icons.palette_outlined,
    summary: (s) => 'Skin: ${s.skin.name}, text size, haptics',
    entries: [
      _Entry(
        id: 'skins',
        title: 'Skins',
        keywords: 'skin theme colors look appearance dark',
        build: (c) {
          final context = c.context;
          final ref = c.ref;
          final s = c.s;
          final repo = c.repo;
          final theme = c.theme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.palette_outlined),
                title: const Text('Skins'),
                subtitle: Text('Now: ${s.skin.name}'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(AppRoutes.skins),
              ),
            ],
          );
        },
      ),
      _Entry(
        id: 'textsize',
        title: 'Song list text size',
        keywords: 'text size font small large song list',
        build: (c) {
          final context = c.context;
          final ref = c.ref;
          final s = c.s;
          final repo = c.repo;
          final theme = c.theme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Text size', style: theme.textTheme.bodyMedium),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<SongListSize>(
                  showSelectedIcon: false,
                  segments: [
                    for (final z in SongListSize.values)
                      ButtonSegment(value: z, label: Text(z.label)),
                  ],
                  selected: {s.songListSize},
                  onSelectionChanged: (v) => repo.setSongListSize(v.first),
                ),
              ),
            ],
          );
        },
      ),
      _Entry(
        id: 'haptics',
        title: 'Haptic feedback',
        keywords: 'haptic vibration vibrate feedback touch',
        build: (c) {
          final context = c.context;
          final ref = c.ref;
          final s = c.s;
          final repo = c.repo;
          final theme = c.theme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Haptic feedback'),
                subtitle: const Text(
                  'A short vibration when you tap play, skip or pick something.',
                ),
                value: s.hapticsEnabled,
                onChanged: repo.setHapticsEnabled,
              ),
            ],
          );
        },
      ),
      _Entry(
        id: 'accent',
        title: 'Colors from album art',
        keywords: 'colors accent album art cover tint',
        build: (c) {
          final context = c.context;
          final ref = c.ref;
          final s = c.s;
          final repo = c.repo;
          final theme = c.theme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Colors from album art'),
                subtitle: const Text(
                  'The Controller takes its accent color from the playing song\'s cover.',
                ),
                value: s.accentFromArt,
                onChanged: repo.setAccentFromArt,
              ),
            ],
          );
        },
      ),
    ],
  ),
  _Group(
    id: 'online',
    title: 'Lyrics and online',
    icon: Icons.public_rounded,
    summary: (s) =>
        'Lyrics ${s.lyricsEnabled ? 'on' : 'off'}, Online Library suggestions',
    entries: [
      _Entry(
        id: 'lyrics',
        title: 'Lyrics from the internet',
        keywords: 'lyrics internet lrclib words online lookup',
        build: (c) {
          final context = c.context;
          final ref = c.ref;
          final s = c.s;
          final repo = c.repo;
          final theme = c.theme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Lyrics from the internet'),
                subtitle: const Text(
                  'The Player looks up lyrics on LRCLIB (and lyrics.ovh) when you open them. '
                  'Only the song\'s title, artist, album and length are sent, and the lyrics '
                  'are kept on the Player.',
                ),
                value: s.lyricsEnabled,
                onChanged: repo.setLyricsEnabled,
              ),
            ],
          );
        },
      ),
      _Entry(
        id: 'cloud',
        title: 'Cloud Library',
        keywords: 'cloud library r2 cloudflare upload songs bucket keys storage',
        build: (c) {
          final context = c.context;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.cloud_outlined),
            title: const Text('Cloud Library'),
            subtitle: const Text('Your own songs in your own Cloudflare R2 bucket: the address, and the keys to upload.'),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const CloudSettingsScreen()),
            ),
          );
        },
      ),
      _Entry(
        id: 'suggestions',
        title: 'Suggestions in the Online Library',
        keywords: 'online library jamendo suggestions popular newest',
        build: (c) {
          final context = c.context;
          final ref = c.ref;
          final s = c.s;
          final repo = c.repo;
          final theme = c.theme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Suggestions in the Online Library'),
                subtitle: const Text(
                  'Popular and newest tracks from Jamendo are shown before you search. They are '
                  'fetched from Jamendo when the tab opens; switch off to keep it blank until you search.',
                ),
                value: s.onlineSuggestions,
                onChanged: repo.setOnlineSuggestions,
              ),
            ],
          );
        },
      ),
    ],
  ),
  _Group(
    id: 'other',
    title: 'Other phones and connection',
    icon: Icons.cast_connected_rounded,
    summary: (s) =>
        'Device name: ${s.deviceName}, when the app opens, relay, other music apps',
    entries: [
      _Entry(
        id: 'device',
        title: 'Device name',
        keywords: 'device name phone called',
        build: (c) {
          final context = c.context;
          final ref = c.ref;
          final s = c.s;
          final repo = c.repo;
          final theme = c.theme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SavedTextField(
                label: 'Device name',
                value: s.deviceName,
                maxLength: 40,
                validator: (v) =>
                    v.trim().isEmpty ? 'Name cannot be empty' : null,
                onSave: repo.setDeviceName,
              ),
            ],
          );
        },
      ),
      _Entry(
        id: 'start',
        title: 'When the app opens',
        keywords: 'start open launch reconnect last player remote playback',
        build: (c) {
          final context = c.context;
          final ref = c.ref;
          final s = c.s;
          final repo = c.repo;
          final theme = c.theme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioGroup<StartMode>(
                groupValue: s.startMode,
                onChanged: (v) {
                  if (v != null) repo.setStartMode(v);
                },
                child: Column(
                  children: [
                    for (final m in StartMode.values)
                      RadioListTile<StartMode>(
                        contentPadding: EdgeInsets.zero,
                        value: m,
                        title: Text(m.label),
                        subtitle: Text(m.description),
                      ),
                  ],
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Start remote playback when the app opens'),
                subtitle: const Text(
                  'Lets other phones control this one without pressing the button. '
                  'Uses a little battery and the network while the app runs.',
                ),
                value: s.remoteAutoStart,
                onChanged: repo.setRemoteAutoStart,
              ),
            ],
          );
        },
      ),
      _Entry(
        id: 'mode',
        title: 'Connection mode',
        keywords: 'connection mode local online auto wifi',
        build: (c) {
          final context = c.context;
          final ref = c.ref;
          final s = c.s;
          final repo = c.repo;
          final theme = c.theme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ConnectionModeSelector(
                value: s.connectionMode,
                onChanged: repo.setConnectionMode,
              ),
            ],
          );
        },
      ),
      _Entry(
        id: 'relay',
        title: 'Online relay (optional)',
        keywords: 'online relay supabase url key internet room',
        build: (c) {
          final context = c.context;
          final ref = c.ref;
          final s = c.s;
          final repo = c.repo;
          final theme = c.theme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Enable online relay'),
                subtitle: const Text(
                  'Optional. Lets a Controller on another network or mobile '
                  'data connect to the Player. Local mode never needs '
                  'internet or Supabase.',
                ),
                value: s.onlineRelayEnabled,
                onChanged: repo.setOnlineRelayEnabled,
              ),
              const SizedBox(height: 8),
              _SavedTextField(
                label: 'Supabase URL',
                value: s.supabaseUrl ?? '',
                keyboardType: TextInputType.url,
                validator: (v) {
                  final t = v.trim();
                  if (t.isEmpty) return null;
                  final uri = Uri.tryParse(t);
                  final ok =
                      uri != null &&
                      (uri.scheme == 'https' || uri.scheme == 'http') &&
                      uri.host.isNotEmpty;
                  return ok ? null : 'Enter a valid http(s) URL';
                },
                onSave: repo.setSupabaseUrl,
              ),
              const SizedBox(height: 12),
              _SavedTextField(
                label: 'Supabase anon key',
                value: s.supabaseAnonKey ?? '',
                obscure: true,
                onSave: repo.setSupabaseAnonKey,
              ),
              const SizedBox(height: 12),
              _RelayTester(settings: s),
              if (s.supabaseUrl == OnlineDefaults.supabaseUrl &&
                  s.supabaseAnonKey == OnlineDefaults.supabaseAnonKey) ...[
                const SizedBox(height: 8),
                Text(
                  "These are pre-filled with this build's own Supabase "
                  'project. Change them to use a different one.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Text(
                'Use your own free Supabase project. In its dashboard, copy the '
                'Project URL and the anon (public) key, and under Realtime '
                'settings allow public access so Broadcast works without '
                'sign-in. Only short playback commands and status messages '
                'pass through it. Music, file names and paths never do.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
        },
      ),
      _Entry(
        id: 'external',
        title: 'External app control',
        keywords: 'external spotify youtube music control notification access',
        build: (c) {
          final context = c.context;
          final ref = c.ref;
          final s = c.s;
          final repo = c.repo;
          final theme = c.theme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('External app control'),
                subtitle: const Text(
                  'Let a Controller control Spotify, YouTube Music or another '
                  'music app on the Player phone. Off by default. Takes effect '
                  'the next time you open Player mode.',
                ),
                value: s.externalAppControlEnabled,
                onChanged: (on) async {
                  // Turning it on needs the user to understand what it asks of
                  // Android first. Turning it off needs no confirmation.
                  if (on && !await _confirmExternal(context)) return;
                  await repo.setExternalAppControlEnabled(on);
                },
              ),
            ],
          );
        },
      ),
      _Entry(
        id: 'port',
        title: 'Player port',
        keywords: 'port player network',
        build: (c) {
          final context = c.context;
          final ref = c.ref;
          final s = c.s;
          final repo = c.repo;
          final theme = c.theme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SavedTextField(
                label: 'Player port',
                value: s.lastPlayerPort.toString(),
                keyboardType: TextInputType.number,
                validator: (v) {
                  final n = int.tryParse(v.trim());
                  if (n == null || n < 1024 || n > 65535) {
                    return 'Enter a port between 1024 and 65535';
                  }
                  return null;
                },
                onSave: (v) => repo.setLastPlayerPort(int.parse(v.trim())),
              ),
            ],
          );
        },
      ),
    ],
  ),
  _Group(
    id: 'about',
    title: 'Updates and about',
    icon: Icons.system_update_rounded,
    summary: (s) => 'App updates, diagnostics, what\'s new, help',
    entries: [
      _Entry(
        id: 'updates',
        title: 'App updates',
        keywords: 'updates version install download github check new',
        build: (c) {
          final context = c.context;
          final ref = c.ref;
          final s = c.s;
          final repo = c.repo;
          final theme = c.theme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [UpdateSettingsTiles(settings: s)],
          );
        },
      ),
      _Entry(
        id: 'diag',
        title: 'Diagnostics',
        keywords: 'diagnostics version network status log copy playback log',
        build: (c) {
          final context = c.context;
          final ref = c.ref;
          final s = c.s;
          final repo = c.repo;
          final theme = c.theme;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.monitor_heart_outlined),
                title: const Text('Diagnostics'),
                subtitle: const Text(
                  'Version, network and library status you can copy',
                ),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => context.push(AppRoutes.diagnostics),
              ),
            ],
          );
        },
      ),
    ],
  ),
];

/// Settings: a short list of groups and a search box. A group opens its own page.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  /// Entries that match every word typed (in the name, the words people look it up by,
  /// or the name of its group).
  List<({_Group group, _Entry entry})> _matches() {
    final words = _query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    return [
      for (final g in _groups)
        for (final e in g.entries)
          if (words.every(
            (w) =>
                '${e.title} ${e.keywords} ${g.title}'.toLowerCase().contains(w),
          ))
            (group: g, entry: e),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(settingsProvider);
    final repo = ref.read(settingsRepositoryProvider);
    final searching = _query.trim().isNotEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load settings. Please restart the app.',
                style: TextStyle(color: theme.colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          data: (s) {
            final found = searching
                ? _matches()
                : const <({_Group group, _Entry entry})>[];
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                TextField(
                  controller: _search,
                  textInputAction: TextInputAction.search,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: InputDecoration(
                    hintText: 'Search settings (try "crossfade")',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: searching
                        ? IconButton(
                            tooltip: 'Clear search',
                            icon: const Icon(Icons.close_rounded),
                            onPressed: () => setState(() {
                              _search.clear();
                              _query = '';
                            }),
                          )
                        : null,
                  ),
                ),
                const SizedBox(height: 8),
                if (!searching) ...[
                  for (final g in _groups)
                    ListTile(
                      key: ValueKey('group-${g.id}'),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: CircleAvatar(
                        backgroundColor: theme.colorScheme.primary.withValues(
                          alpha: 0.14,
                        ),
                        child: Icon(g.icon, color: theme.colorScheme.primary),
                      ),
                      title: Text(g.title, style: theme.textTheme.titleMedium),
                      subtitle: Text(
                        g.summary(s),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => _GroupPage(groupId: g.id),
                        ),
                      ),
                    ),
                  ListTile(
                    key: const ValueKey('group-backup'),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                    leading: CircleAvatar(
                      backgroundColor: theme.colorScheme.primary.withValues(
                        alpha: 0.14,
                      ),
                      child: Icon(
                        Icons.settings_backup_restore_rounded,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    title: Text(
                      'Backup and restore',
                      style: theme.textTheme.titleMedium,
                    ),
                    subtitle: const Text(
                      'Playlists, favorites, counts, lyrics and art, to a file',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const BackupScreen(),
                      ),
                    ),
                  ),
                ] else if (found.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'No setting matches that.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else
                  for (final m in found) ...[
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 4),
                      child: Text(
                        m.group.title,
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ),
                    m.entry.build(
                      _Ctx(context: context, ref: ref, s: s, repo: repo),
                    ),
                    const Divider(height: 24),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One group's page: all its settings, one under the other.
class _GroupPage extends ConsumerWidget {
  const _GroupPage({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = _groups.firstWhere((g) => g.id == groupId);
    final theme = Theme.of(context);
    final async = ref.watch(settingsProvider);
    final repo = ref.read(settingsRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(group.title)),
      body: SafeArea(
        child: async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Text(
              'Could not load settings.',
              style: TextStyle(color: theme.colorScheme.error),
            ),
          ),
          data: (s) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              for (var i = 0; i < group.entries.length; i++) ...[
                if (i > 0) const Divider(height: 32),
                group.entries[i].build(
                  _Ctx(context: context, ref: ref, s: s, repo: repo),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Explains Notification access before External App Control can be enabled.
Future<bool> _confirmExternal(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Control other music apps?'),
      content: SingleChildScrollView(child: const Text(externalConsentText)),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Turn on'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Text field that saves on submit or when focus is lost, if valid.
class _SavedTextField extends StatefulWidget {
  const _SavedTextField({
    required this.label,
    required this.value,
    required this.onSave,
    this.validator,
    this.keyboardType,
    this.obscure = false,
    this.maxLength,
  });

  final String label;
  final String value;
  final Future<void> Function(String) onSave;
  final String? Function(String)? validator;
  final TextInputType? keyboardType;
  final bool obscure;
  final int? maxLength;

  @override
  State<_SavedTextField> createState() => _SavedTextFieldState();
}

class _SavedTextFieldState extends State<_SavedTextField> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.value,
  );
  final FocusNode _focus = FocusNode();
  String? _error;
  late bool _hidden = widget.obscure;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (!_focus.hasFocus) _commit();
    });
  }

  @override
  void didUpdateWidget(covariant _SavedTextField old) {
    super.didUpdateWidget(old);
    if (!_focus.hasFocus && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _commit() async {
    final text = _controller.text;
    final err = widget.validator?.call(text);
    setState(() => _error = err);
    if (err == null && text != widget.value) {
      await widget.onSave(text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focus,
      keyboardType: widget.keyboardType,
      obscureText: _hidden,
      maxLength: widget.maxLength,
      autocorrect: false,
      enableSuggestions: !widget.obscure,
      onSubmitted: (_) => _commit(),
      decoration: InputDecoration(
        labelText: widget.label,
        errorText: _error,
        counterText: '',
        suffixIcon: widget.obscure
            ? IconButton(
                tooltip: _hidden ? 'Show' : 'Hide',
                icon: Icon(
                  _hidden
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                ),
                onPressed: () => setState(() => _hidden = !_hidden),
              )
            : null,
      ),
    );
  }
}

/// Default volume slider: stored 0.0–1.0, shown as 0–100%.
class _VolumeSetting extends StatefulWidget {
  const _VolumeSetting({required this.value, required this.onSave});

  final double value;
  final Future<void> Function(double) onSave;

  @override
  State<_VolumeSetting> createState() => _VolumeSettingState();
}

class _VolumeSettingState extends State<_VolumeSetting> {
  double? _dragging;

  @override
  Widget build(BuildContext context) {
    final v = _dragging ?? widget.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Default volume: ${(v * 100).round()}%'),
        Slider(
          value: v,
          onChanged: (x) => setState(() => _dragging = x),
          onChangeEnd: (x) async {
            await widget.onSave(x);
            if (mounted) setState(() => _dragging = null);
          },
        ),
      ],
    );
  }
}

/// "Test online relay": joins a throw-away room to check the URL and key.
class _RelayTester extends ConsumerStatefulWidget {
  const _RelayTester({required this.settings});

  final AppSettings settings;

  @override
  ConsumerState<_RelayTester> createState() => _RelayTesterState();
}

class _RelayTesterState extends ConsumerState<_RelayTester> {
  bool _busy = false;
  RelayTestResult? _result;

  Future<void> _run() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    RelayTestResult result;
    try {
      result = await ref.read(relayTesterProvider)(widget.settings);
    } catch (_) {
      result = const RelayTestResult.failed("Couldn't test the online relay.");
    }
    if (mounted) {
      setState(() {
        _busy = false;
        _result = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = _result;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(minimumSize: const Size(0, 48)),
          onPressed: _busy ? null : _run,
          icon: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.network_check_rounded),
          label: Text(_busy ? 'Testing…' : 'Test online relay'),
        ),
        if (r != null) ...[
          const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                r.success
                    ? Icons.check_circle_rounded
                    : Icons.error_outline_rounded,
                size: 18,
                color: r.success ? RtColors.teal : theme.colorScheme.error,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(r.message, style: theme.textTheme.bodySmall),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
