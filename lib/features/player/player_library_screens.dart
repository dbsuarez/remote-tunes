import 'package:flutter/material.dart';
import '../music/library_search.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../providers/connection_providers.dart';
import '../../core/song_list_style.dart';
import '../../providers/library_providers.dart';
import '../library/import_actions.dart';
import '../music/music_browser.dart';
import '../music/local_music_source.dart';
import '../music/queue_view.dart';
import '../music/url_player_view.dart';
import 'server/player_library.dart';

enum _AddAction { songs, folder }

/// The Player's own library: browse, search, play, queue, remove, and add music.
class PlayerLibraryScreen extends ConsumerStatefulWidget {
  const PlayerLibraryScreen({super.key});

  @override
  ConsumerState<PlayerLibraryScreen> createState() => _PlayerLibraryScreenState();
}

class _PlayerLibraryScreenState extends ConsumerState<PlayerLibraryScreen> {
  int _refresh = 0;

  Future<void> _add(_AddAction action) async {
    final bool added;
    if (action == _AddAction.songs) {
      added = await pickAndImportFiles(context, ref);
    } else {
      added = await pickAndImportFolder(context, ref);
    }
    if (added && mounted) setState(() => _refresh++);
  }

  @override
  Widget build(BuildContext context) {
    final host = ref.watch(playerHostProvider).valueOrNull;
    final engine = host?.queueEngine;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Library'),
        actions: [
          PopupMenuButton<_AddAction>(
            tooltip: 'Add music',
            icon: const Icon(Icons.add_rounded),
            onSelected: _add,
            itemBuilder: (_) => const [
              PopupMenuItem(value: _AddAction.songs, child: Text('Add songs')),
              PopupMenuItem(value: _AddAction.folder, child: Text('Add folder')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: engine == null
            ? const Center(child: Text('The Player is starting…'))
            : MusicBrowser(
                size: ref.watch(songListSizeProvider),
                homeList: true,
                onSearch: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => LibrarySearchScreen(
                      size: ref.read(songListSizeProvider),
                      source: LocalMusicSource(
                        RepositoryPlayerLibrary(ref.read(libraryRepositoryProvider)),
                        engine,
                      ),
                    ),
                  ),
                ),
                source: LocalMusicSource(
                  RepositoryPlayerLibrary(ref.read(libraryRepositoryProvider)),
                  engine,
                ),
                refreshToken: _refresh,
                emptyMessage:
                    'Your library is empty.\nTap + to add songs or a whole folder.',
                onEditSong: (song, e) => ref.read(libraryRepositoryProvider).updateSongInfo(
                      song.id,
                      title: e.title,
                      artist: e.artist,
                      album: e.album,
                      trackNumber: e.trackNumber,
                    ),
                onRemoveSong: (song) async {
                  final service = await ref.read(importServiceProvider.future);
                  await service.removeSong(song.id);
                },
              ),
      ),
    );
  }
}

/// Play an internet audio link directly on this phone.
class PlayerUrlScreen extends ConsumerWidget {
  const PlayerUrlScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final engine = ref.watch(playerHostProvider).valueOrNull?.queueEngine;

    return Scaffold(
      appBar: AppBar(title: const Text('Play a link')),
      body: SafeArea(
        child: engine == null
            ? const Center(child: Text('The Player is starting…'))
            : UrlPlayerView(
                target: 'this phone',
                initialUrl: AppConstants.sampleAudioUrl,
                onPlay: (url, title) => engine.playUrl(url, title: title),
              ),
      ),
    );
  }
}

/// The Player's own queue.
class PlayerQueueScreen extends ConsumerWidget {
  const PlayerQueueScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final host = ref.watch(playerHostProvider).valueOrNull;
    final engine = host?.queueEngine;
    final playback = ref.watch(playerPlaybackProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Queue')),
      body: SafeArea(
        child: (engine == null || playback == null)
            ? const Center(child: Text('The Player is starting…'))
            : QueueView(
                source: LocalMusicSource(
                  RepositoryPlayerLibrary(ref.read(libraryRepositoryProvider)),
                  engine,
                ),
                revision: playback.queueRevision,
                currentIndex: playback.queueLength > 0 ? playback.queueIndex : -1,
                shuffle: playback.shuffleEnabled,
                repeat: playback.repeatMode,
              ),
      ),
    );
  }
}
