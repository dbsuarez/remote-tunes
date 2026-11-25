import '../../core/widgets/haptic_button.dart';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../update/update_controller.dart';
import '../update/update_widgets.dart';
import '../player/visualizer.dart';
import '../library/tag_writer.dart';
import '../../core/constants.dart';
import '../../core/haptics.dart';
import '../../core/models/enums.dart';
import '../../core/protocol/protocol.dart';
import '../../core/router/app_router.dart';
import '../../core/song_list_style.dart';
import '../../core/theme/app_theme.dart';
import '../../data/repositories/settings_repository.dart';
import '../../providers/connection_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/providers.dart';
import '../../providers/shell_providers.dart';
import '../controller/controller_client.dart';
import '../controller/remote_session.dart';
import '../group/group_card.dart';
import '../library/import_actions.dart';
import 'app_drawer.dart';
import '../player/player_screen.dart' show showPairingDialog;
import '../music/folder_tree.dart';
import '../music/library_search.dart';
import '../music/music_browser.dart';
import '../music/music_source.dart';
import '../music/now_playing_view.dart';
import '../music/queue_view.dart';
import '../music/url_player_view.dart';
import '../online_library/online_history_source.dart';
import '../online_library/online_library_view.dart';
import '../player/local_now_playing.dart';
import '../player/player_core.dart';
import '../music/local_music_source.dart';
import '../controller/controller_views.dart' show ExternalModeSwitch;

/// The music player: Now Playing, Library, Search and Queue, with a mini player
/// under every tab but the first. It plays this phone's own music, or (after
/// "Control another phone") another phone's player: the same screens either way.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  int _tab = 0;

  /// Changes every time the Queue tab is opened (so it can scroll to the song
  /// playing).
  int _queueToken = 0;

  /// Asks Now Playing to show the lyrics (the menu's Lyrics shortcut).
  final ValueNotifier<int> _lyricsRequests = ValueNotifier(0);

  /// Changes to reopen the Library (the menu's Playlists shortcut).
  int _libraryNonce = 0;
  bool _libraryOnPlaylists = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final settings = await ref.read(settingsRepositoryProvider).load();
      if (!mounted) return;
      if (settings.remoteAutoStart) {
        ref.read(remotePlaybackProvider.notifier).state = true;
      }
      if (settings.startMode == StartMode.lastPlayer) unawaited(_reconnectLastPlayer());
      // Android 13+ needs permission to show the media notification. Playback
      // works without it, so a "no" is fine.
      try {
        await ref.read(permissionsProvider).ensureNotifications();
      } catch (_) {}
    });
  }

  /// Opens the connection to the Player used last, without pairing again.
  Future<void> _reconnectLastPlayer() async {
    try {
      final trusted = await ref.read(trustedPlayersStoreProvider).load();
      if (trusted.isEmpty || !mounted) return;
      final client = ref.read(controllerClientProvider);
      if (client.current.status != ControllerStatus.disconnected) return;
      final settings = ref.read(settingsProvider).valueOrNull ?? const AppSettings();
      ref.read(controlRemoteProvider.notifier).state = true;
      client.resumeTrusted(
        player: trusted.first,
        deviceName: settings.deviceName,
        mode: settings.connectionMode,
      );
    } catch (_) {
      // Stays on this phone's music.
    }
  }

  void _openSource() => showSourceSheet(context, ref);

  @override
  void dispose() {
    _lyricsRequests.dispose();
    super.dispose();
  }

  bool _pairingOpen = false;

  @override
  Widget build(BuildContext context) {
    // While remote playback is on, the Player server is kept alive.
    if (ref.watch(remotePlaybackProvider)) ref.watch(playerHostProvider);

    // Another phone asks to pair: show it over whatever is open.
    ref.listen(playerServerStateProvider, (prev, next) {
      final pending = next.valueOrNull?.pending;
      if (pending != null && !_pairingOpen) {
        _pairingOpen = true;
        showPairingDialog(context).whenComplete(() => _pairingOpen = false);
      }
    });

    final wantRemote = ref.watch(controlRemoteProvider);
    final client = ref.watch(controllerClientProvider);
    final conn = ref.watch(controllerStateProvider).valueOrNull ?? client.current;
    final remoteLive = conn.status == ControllerStatus.connected ||
        conn.status == ControllerStatus.reconnecting;
    final remote = wantRemote && remoteLive;

    // Controlling a phone that went away: back to this phone's own music.
    if (wantRemote && !remoteLive && conn.status == ControllerStatus.disconnected) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            ref.read(controlRemoteProvider) &&
            ref.read(controllerClientProvider).current.status == ControllerStatus.disconnected) {
          ref.read(controlRemoteProvider.notifier).state = false;
        }
      });
    }

    final _Active? active;
    if (remote) {
      active = _Active.remote(ref, client, conn,
          goLibrary: () => setState(() => _tab = 1),
          lyricsRequests: _lyricsRequests,
          suggestions: ref.watch(settingsProvider).valueOrNull?.onlineSuggestions ?? true);
    } else {
      final core = ref.watch(playerCoreProvider);
      active = core.valueOrNull == null
          ? null
          : _Active.local(ref, core.value!,
              goLibrary: () => setState(() => _tab = 1),
              lyricsRequests: _lyricsRequests,
              visualizer: ref.watch(settingsProvider).valueOrNull?.visualizerEnabled ?? false,
              suggestions: ref.watch(settingsProvider).valueOrNull?.onlineSuggestions ?? true);
    }

    final size = ref.watch(songListSizeProvider);
    final title = remote ? (conn.playerName ?? 'Player') : 'RemoteTunes';

    return Scaffold(
      // The menu opens with its button only: a swipe in from the left edge opens the
      // Library on Now Playing.
      drawerEnableOpenDragGesture: false,
      drawer: AppDrawer(
        version: ref.watch(installedAppProvider).valueOrNull?.label,
        updateAvailable: ref.watch(updateProvider).status == UpdateStatus.available,
        showEqualizer: !remote,
        onNowPlaying: () => setState(() => _tab = 0),
        onLyrics: () {
          setState(() => _tab = 0);
          // After the page has switched, so the lyrics button is there to answer.
          WidgetsBinding.instance.addPostFrameCallback((_) => _lyricsRequests.value++);
        },
        onLibrary: () => setState(() {
          _tab = 1;
          _libraryOnPlaylists = false;
          _libraryNonce++;
        }),
        onPlaylists: () => setState(() {
          _tab = 1;
          _libraryOnPlaylists = true;
          _libraryNonce++;
        }),
        onSearch: () => setState(() => _tab = 2),
        onQueue: () => setState(() {
          _tab = 3;
          _queueToken++;
        }),
        onEqualizer: () => context.push(AppRoutes.equalizer),
        onRemotePlayback: () => context.push(AppRoutes.remotePlayback),
        onSettings: () => context.push(AppRoutes.settings),
        onChangelog: () => context.push(AppRoutes.changelog),
        onHelp: () => context.push(AppRoutes.help),
        onSkins: () => context.push(AppRoutes.skins),
      ),
      appBar: AppBar(
        titleSpacing: 12,
        title: _SourceChip(
          remote: remote,
          reconnecting: conn.status == ControllerStatus.reconnecting && remote,
          name: title,
          remotePlaybackOn: ref.watch(remotePlaybackProvider),
          onTap: _openSource,
        ),
        actions: [
          if (!remote && _tab == 1)
            PopupMenuButton<String>(
              tooltip: 'Add music',
              icon: const Icon(Icons.library_add_rounded),
              onSelected: (v) {
                if (v == 'files') pickAndImportFiles(context, ref);
                if (v == 'folder') pickAndImportFolder(context, ref);
                if (v == 'rescan') rescanMusicFolders(context, ref);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rescan', child: Text('Rescan music folders')),
                PopupMenuItem(value: 'folder', child: Text('Add folder')),
                PopupMenuItem(value: 'files', child: Text('Add songs')),
              ],
            ),
          if (!remote)
            IconButton(
              tooltip: 'Equalizer',
              icon: const Icon(Icons.equalizer_rounded),
              onPressed: () => context.push(AppRoutes.equalizer),
            ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_rounded),
            onPressed: () => context.push(AppRoutes.settings),
          ),
        ],
      ),
      body: SafeArea(
        child: active == null
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // A card appears when a newer version is out (it also does the quiet
                  // check, about once a day).
                  const UpdateBanner(),
                  Expanded(
                    child: IndexedStack(
                      index: _tab,
                      children: [
                        active.nowPlaying(),
                        _LibraryTab(
                          key: ValueKey('library-$_libraryNonce'),
                          active: active,
                          size: size,
                          startOnPlaylists: _libraryOnPlaylists,
                          onSearch: () => setState(() => _tab = 2),
                        ),
                        LibrarySearchScreen(source: active.source, size: size, embedded: true),
                        QueueView(
                          source: active.source,
                          revision: active.playback.queueRevision,
                          currentIndex:
                              active.playback.queueLength > 0 ? active.playback.queueIndex : -1,
                          shuffle: active.playback.shuffleEnabled,
                          repeat: active.playback.repeatMode,
                          enabled: active.enabled,
                          scrollToCurrent:
                              ref.watch(settingsProvider).valueOrNull?.queueScrollToCurrent ?? true,
                          scrollToken: _queueToken,
                        ),
                      ],
                    ),
                  ),
                  if (_tab != 0) _MiniPlayer(active: active, onOpen: () => setState(() => _tab = 0)),
                ],
              ),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          Haptics.selection();
          setState(() {
            _tab = i;
            if (i == 3) _queueToken++;
          });
        },
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.play_circle_outline_rounded),
              selectedIcon: Icon(Icons.play_circle_rounded),
              label: 'Now Playing'),
          NavigationDestination(
              icon: Icon(Icons.library_music_outlined),
              selectedIcon: Icon(Icons.library_music_rounded),
              label: 'Library'),
          NavigationDestination(
              icon: Icon(Icons.search_rounded), selectedIcon: Icon(Icons.search_rounded), label: 'Search'),
          NavigationDestination(
              icon: Icon(Icons.queue_music_outlined),
              selectedIcon: Icon(Icons.queue_music_rounded),
              label: 'Queue'),
        ],
      ),
    );
  }
}

/// What the player is showing right now: this phone's music, or a remote
/// Player's, with the same few things the tabs need.
class _Active {
  _Active({
    required this.playback,
    required this.source,
    required this.enabled,
    required this.nowPlaying,
    required this.toggle,
    required this.next,
    required this.previous,
    required this.extraCategories,
  });

  final PlaybackState playback;
  final MusicSource source;
  final bool enabled;
  final Widget Function() nowPlaying;
  final Future<void> Function() toggle;
  final Future<void> Function() next;
  final Future<void> Function() previous;
  final List<LibraryExtra> extraCategories;

  factory _Active.remote(
    WidgetRef ref,
    ControllerClient client,
    ControllerClientState conn, {
    required VoidCallback goLibrary,
    Listenable? lyricsRequests,
    bool suggestions = true,
  }) {
    final session = RemoteSession(client: client, connection: conn);
    final enabled = conn.isConnected;
    final p = conn.playback;
    return _Active(
      playback: p,
      source: session.source,
      enabled: enabled,
      toggle: session.toggle,
      next: session.next,
      previous: session.previous,
      nowPlaying: () => Builder(
        builder: (context) => NowPlayingView(
          session: session,
          // Only offered when the Player turned External App Control on.
          header: p.externalEnabled
              ? ExternalModeSwitch(
                  external: p.isExternal,
                  enabled: enabled,
                  onChanged: (mode) async {
                    try {
                      await client.setControlMode(mode);
                    } on ControllerException catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context)
                          ..hideCurrentSnackBar()
                          ..showSnackBar(SnackBar(content: Text(e.message)));
                      }
                    }
                  },
                )
              : null,
          // This phone can play the same song, in sync.
          extras: GroupCard(enabled: enabled),
          onOpenLibrary: goLibrary,
          lyricsRequests: lyricsRequests,
        ),
      ),
      extraCategories: [
        LibraryExtra(
          title: 'Online Library',
          icon: Icons.public_rounded,
          color: RtColors.violet,
          builder: (_) => OnlineLibraryView(
            suggestions: suggestions,
            enabled: enabled,
            history: ClientHistorySource(client),
            // The Player streams the track itself: only the link and the title
            // go to it.
            onTrack: (t, {required queue}) => client.playUrl(
              t.audioUrl,
              title: t.title,
              artist: t.artist,
              album: t.album,
              licenseUrl: t.licenseUrl,
              imageUrl: t.imageUrl,
              queue: queue,
            ),
          ),
        ),
        LibraryExtra(
          title: 'Folder tree',
          icon: Icons.account_tree_rounded,
          color: const Color(0xFF90A4AE),
          builder: (_) => FolderTreeView(source: session.source),
        ),
        LibraryExtra(
          title: 'Play a link',
          icon: Icons.link_rounded,
          color: const Color(0xFF4FC3F7),
          builder: (_) => UrlPlayerView(
            enabled: enabled,
            target: 'the Player',
            initialUrl: AppConstants.sampleAudioUrl,
            onPlay: (url, title) => client.playUrl(url, title: title),
          ),
        ),
      ],
    );
  }

  factory _Active.local(WidgetRef ref, PlayerCore core,
      {required VoidCallback goLibrary,
      Listenable? lyricsRequests,
      bool visualizer = false,
      bool suggestions = true}) {
    final playback = ref.watch(playerPlaybackProvider).valueOrNull ?? core.engine.state;
    final source = LocalMusicSource(core.library, core.engine);
    return _Active(
      playback: playback,
      source: source,
      enabled: true,
      toggle: core.engine.toggle,
      next: core.engine.next,
      previous: core.engine.previous,
      nowPlaying: () => LocalNowPlaying(
        engine: core.engine,
        library: core.library,
        sleepTimer: core.sleepTimer,
        onOpenLibrary: goLibrary,
        lyricsRequests: lyricsRequests,
        // Shows or hides the visualizer without going to Settings.
        visualizerButton: Builder(
          builder: (context) => HapticButton(
            kind: HapticKind.selection,
            tooltip: visualizer ? 'Hide the visualizer' : 'Show the visualizer',
            onPressed: () =>
                switchVisualizer(context, ref.read(settingsRepositoryProvider), !visualizer),
            icon: Icon(Icons.graphic_eq_rounded,
                color: visualizer ? Theme.of(context).colorScheme.primary : null),
          ),
        ),
        visualizer: visualizer
            ? (playing) => VisualizerStrip(
                  isPlaying: playing,
                  style: VisualizerStyle.byName(
                      ref.read(settingsProvider).valueOrNull?.visualizerStyle),
                  // A tap moves to the next style (and it is remembered).
                  onCycle: () {
                    final now = VisualizerStyle.byName(
                        ref.read(settingsProvider).valueOrNull?.visualizerStyle);
                    ref.read(settingsRepositoryProvider).setVisualizerStyle(now.next.name);
                  },
                )
            : null,
      ),
      extraCategories: [
        LibraryExtra(
          title: 'Online Library',
          icon: Icons.public_rounded,
          color: RtColors.violet,
          builder: (_) => OnlineLibraryView(
            suggestions: suggestions,
            onTrack: (t, {required queue}) async {
              if (queue) {
                await core.engine.enqueueUrl(t.audioUrl,
                    title: t.title,
                    artist: t.artist,
                    album: t.album,
                    licenseUrl: t.licenseUrl,
                    imageUrl: t.imageUrl);
              } else {
                await core.engine.playUrl(t.audioUrl,
                    title: t.title,
                    artist: t.artist,
                    album: t.album,
                    licenseUrl: t.licenseUrl,
                    imageUrl: t.imageUrl);
              }
            },
          ),
        ),
        LibraryExtra(
          title: 'Folder tree',
          icon: Icons.account_tree_rounded,
          color: const Color(0xFF90A4AE),
          builder: (_) => FolderTreeView(source: source),
        ),
        LibraryExtra(
          title: 'Play a link',
          icon: Icons.link_rounded,
          color: const Color(0xFF4FC3F7),
          builder: (_) => UrlPlayerView(
            target: 'this phone',
            initialUrl: AppConstants.sampleAudioUrl,
            onPlay: (url, title) => core.engine.playUrl(url, title: title),
          ),
        ),
      ],
    );
  }
}

class _LibraryTab extends ConsumerWidget {
  const _LibraryTab({
    super.key,
    required this.active,
    required this.size,
    required this.onSearch,
    this.startOnPlaylists = false,
  });

  final bool startOnPlaylists;
  final _Active active;
  final SongListSize size;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = active.source is LocalMusicSource;
    return MusicBrowser(
      source: active.source,
      size: size,
      enabled: active.enabled,
      homeList: true,
      startOnPlaylists: startOnPlaylists,
      onSearch: onSearch,
      extraCategories: active.extraCategories,
      emptyMessage: local
          ? 'Your library is empty.\nUse the + button to add songs or a whole folder.'
          : "The Player's library is empty.\nOn the Player, add songs or a folder.",
      // Only on this phone's own library.
      onRemoveSong: local
          ? (song) async {
              final service = await ref.read(importServiceProvider.future);
              await service.removeSong(song.id);
            }
          : null,
      canWriteTags: local,
      onEditSong: local
          ? (song, e) async {
              final library = ref.read(libraryRepositoryProvider);
              final saved = await library.updateSongInfo(
                song.id,
                title: e.title,
                artist: e.artist,
                album: e.album,
                trackNumber: e.trackNumber,
              );
              if (saved && e.writeToFile) {
                final row = await library.songById(song.id);
                final path = row?.filePath;
                if (path != null) {
                  e.fileNote = TagWriter.message(const TagWriter().write(path,
                      title: e.title.trim(),
                      artist: e.artist.trim().isEmpty ? 'Unknown artist' : e.artist.trim(),
                      album: e.album.trim().isEmpty ? 'Unknown album' : e.album.trim(),
                      trackNumber: e.trackNumber));
                }
              }
              return saved;
            }
          : null,
    );
  }
}

/// Title, previous / play-pause / next and a thin progress line, shown under
/// every tab except Now Playing.
class _MiniPlayer extends StatelessWidget {
  const _MiniPlayer({required this.active, required this.onOpen});

  final _Active active;
  final VoidCallback onOpen;

  Future<void> _run(BuildContext context, Future<void> Function() f) async {
    try {
      await f();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = active.playback;
    final progress = p.durationSeconds > 0
        ? (p.positionSeconds / p.durationSeconds).clamp(0.0, 1.0)
        : 0.0;
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onOpen,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(p.hasTrack ? p.title : 'Nothing playing',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall
                                ?.copyWith(color: theme.colorScheme.primary)),
                        if (p.artist.isNotEmpty)
                          Text(p.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Previous',
                    onPressed: active.enabled && p.canSkip
                        ? () => _run(context, active.previous)
                        : null,
                    icon: const Icon(Icons.skip_previous_rounded),
                  ),
                  IconButton(
                    tooltip: p.isPlaying ? 'Pause' : 'Play',
                    onPressed: active.enabled ? () => _run(context, active.toggle) : null,
                    icon: Icon(p.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                  ),
                  IconButton(
                    tooltip: 'Next',
                    onPressed: active.enabled && p.canSkip
                        ? () => _run(context, active.next)
                        : null,
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                ],
              ),
            ),
          ),
          LinearProgressIndicator(value: progress, minHeight: 2),
        ],
      ),
    );
  }
}

/// The pill in the top bar: whose music this is. Tap to change.
class _SourceChip extends StatelessWidget {
  const _SourceChip({
    required this.remote,
    required this.reconnecting,
    required this.name,
    required this.remotePlaybackOn,
    required this.onTap,
  });

  final bool remote;
  final bool reconnecting;
  final String name;
  final bool remotePlaybackOn;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = reconnecting
        ? RtColors.warning
        : remote
            ? RtColors.violet
            : RtColors.teal;
    final label = reconnecting
        ? 'Reconnecting to $name…'
        : remote
            ? 'Controlling $name'
            : 'This phone';
    return Align(
      alignment: Alignment.centerLeft,
      child: Tooltip(
        message: 'Change what you are playing on',
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: color.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                    reconnecting
                        ? Icons.sync_rounded
                        : remote
                            ? Icons.settings_remote_rounded
                            : Icons.smartphone_rounded,
                    size: 18,
                    color: color),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(label,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(color: color)),
                ),
                if (remotePlaybackOn && !remote) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.cast_connected_rounded, size: 16, color: color),
                ],
                const SizedBox(width: 4),
                Icon(Icons.arrow_drop_down_rounded, color: color),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// What to play on: this phone, another phone, and letting others control this
/// one.
Future<void> showSourceSheet(BuildContext context, WidgetRef ref) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (ctx) => Consumer(
      builder: (ctx, ref, _) {
        final remoteWanted = ref.watch(controlRemoteProvider);
        final client = ref.watch(controllerClientProvider);
        final conn = ref.watch(controllerStateProvider).valueOrNull ?? client.current;
        final connected = conn.status == ControllerStatus.connected ||
            conn.status == ControllerStatus.reconnecting;
        final serving = ref.watch(remotePlaybackProvider);
        void close() => Navigator.of(ctx).pop();
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.smartphone_rounded),
                title: const Text('This phone'),
                subtitle: const Text("Play the music that is on this phone"),
                trailing: !(remoteWanted && connected) ? const Icon(Icons.check_rounded) : null,
                onTap: () {
                  ref.read(controlRemoteProvider.notifier).state = false;
                  close();
                },
              ),
              if (connected)
                ListTile(
                  leading: const Icon(Icons.settings_remote_rounded),
                  title: Text('Controlling ${conn.playerName ?? 'a Player'}'),
                  subtitle: const Text('Use this phone as the remote'),
                  trailing: remoteWanted ? const Icon(Icons.check_rounded) : null,
                  onTap: () {
                    ref.read(controlRemoteProvider.notifier).state = true;
                    close();
                  },
                ),
              if (connected)
                ListTile(
                  leading: const Icon(Icons.link_off_rounded),
                  title: const Text('Disconnect'),
                  onTap: () {
                    ref.read(controlRemoteProvider.notifier).state = false;
                    client.disconnect();
                    close();
                  },
                )
              else
                ListTile(
                  leading: const Icon(Icons.settings_remote_rounded),
                  title: const Text('Control another phone'),
                  subtitle: const Text('Find a Player and use this phone as its remote'),
                  onTap: () {
                    close();
                    ref.read(controlRemoteProvider.notifier).state = true;
                    GoRouter.of(context).push(AppRoutes.connect);
                  },
                ),
              const Divider(height: 1),
              ListTile(
                leading: Icon(serving ? Icons.cast_connected_rounded : Icons.cast_rounded),
                title: Text(serving ? 'Remote playback is on' : 'Start remote playback'),
                subtitle: Text(serving
                    ? 'Other phones can control this one. Tap for the pairing code.'
                    : 'Let another phone control the music on this one'),
                trailing: serving
                    ? TextButton(
                        onPressed: () {
                          ref.read(remotePlaybackProvider.notifier).state = false;
                        },
                        child: const Text('Stop'),
                      )
                    : null,
                onTap: () {
                  if (!serving) ref.read(remotePlaybackProvider.notifier).state = true;
                  close();
                  GoRouter.of(context).push(AppRoutes.remotePlayback);
                },
              ),
            ],
          ),
        );
      },
    ),
  );
}
