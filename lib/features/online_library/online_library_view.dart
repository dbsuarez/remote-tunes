import 'dart:async';

import '../../core/widgets/default_art.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/widgets/playback_widgets.dart';
import '../music/music_source.dart' show friendlyError;
import 'jamendo_api.dart';
import 'jamendo_home.dart';
import 'jamendo_key_store.dart';
import 'online_history_source.dart';
import 'online_history_view.dart';

/// Plays or queues a track on the Player. Throws on failure; the screen shows
/// the reason.
typedef TrackAction = Future<void> Function(JamendoTrack track, {required bool queue});

/// Online Library: search Jamendo's free, Creative Commons music from the
/// Controller and send a track's stream to the Player.
///
/// Searches run on THIS phone (or browser), using the user's own client ID,
/// which is kept on this device only. Nothing is downloaded or stored, and no
/// history or analytics are kept.
class OnlineLibraryView extends ConsumerStatefulWidget {
  const OnlineLibraryView({
    super.key,
    required this.onTrack,
    this.history,
    this.enabled = true,
    this.suggestions = false,
  });

  /// Shelves (popular, newest) are shown before anything is searched.
  final bool suggestions;

  final TrackAction onTrack;

  /// The history kept on the Player. When given, a History button is shown.
  final OnlineHistorySource? history;

  /// False while the Controller is reconnecting.
  final bool enabled;

  @override
  ConsumerState<OnlineLibraryView> createState() => _OnlineLibraryViewState();
}

class _OnlineLibraryViewState extends ConsumerState<OnlineLibraryView> with WidgetsBindingObserver {
  final _search = TextEditingController();
  final _keyField = TextEditingController();
  JamendoSearchMode _mode = JamendoSearchMode.keyword;
  bool _showHistory = false;

  bool _keyLoaded = false;
  String? _clientId;
  String? _keyProblem;

  final List<JamendoTrack> _tracks = [];
  bool _loading = false;
  bool _hasMore = false;
  bool _searched = false;
  JamendoException? _error;
  String _lastText = '';
  int _generation = 0;

  /// The genre whose "popular this week" shelf is shown on the home screen.
  String _weekGenre = jamendoGenres.first;

  /// While the tab is open the shelves refresh by themselves when they are old (and when the app
  /// comes back to the front), not only on a pull down.
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshTimer = Timer.periodic(const Duration(minutes: 5), (_) {
      if (mounted && !_searched) _loadHome();
    });
    _loadKey();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted && !_searched) _loadHome();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _search.dispose();
    _keyField.dispose();
    super.dispose();
  }

  Future<void> _loadKey() async {
    final id = await ref.read(jamendoKeyStoreProvider).load();
    if (!mounted) return;
    setState(() {
      _clientId = id;
      _keyLoaded = true;
    });
    _loadHome();
  }

  /// Fills the shelves on the home screen (when they are switched on).
  void _loadHome({bool refresh = false}) {
    final id = _clientId;
    if (!widget.suggestions || id == null) return;
    final home = ref.read(jamendoHomeProvider);
    final api = ref.read(jamendoApiProvider);
    // The ordinary shelves first, then the genre shelf (requests go one after another).
    home.load(api, id, refresh: refresh).then((_) {
      if (mounted) home.loadGenre(api, id, _weekGenre, refresh: refresh);
    });
  }

  void _pickWeekGenre(String genre) {
    final id = _clientId;
    setState(() => _weekGenre = genre);
    if (id != null) {
      ref.read(jamendoHomeProvider).loadGenre(ref.read(jamendoApiProvider), id, genre);
    }
  }

  Future<void> _saveKey() async {
    final problem = JamendoKeyStore.problem(_keyField.text);
    if (problem != null) {
      setState(() => _keyProblem = problem);
      return;
    }
    final id = _keyField.text.trim();
    await ref.read(jamendoKeyStoreProvider).save(id);
    if (!mounted) return;
    setState(() {
      _clientId = id;
      _keyProblem = null;
      _keyField.clear();
      _error = null;
    });
    _loadHome();
  }

  Future<void> _removeKey() async {
    await ref.read(jamendoKeyStoreProvider).clear();
    ref.read(jamendoHomeProvider).clear();
    if (!mounted) return;
    setState(() {
      _clientId = null;
      _tracks.clear();
      _searched = false;
      _error = null;
    });
  }

  Future<void> _runSearch({bool more = false, String? text}) async {
    final id = _clientId;
    final q = (text ?? (more ? _lastText : _search.text)).trim();
    if (id == null || _loading) return;
    if (q.isEmpty) {
      setState(() => _error = JamendoException('Type something to search for.'));
      return;
    }
    FocusScope.of(context).unfocus();
    final gen = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
      if (!more) {
        _tracks.clear();
        _lastText = q;
        _searched = true;
      }
    });
    try {
      final page = await ref.read(jamendoApiProvider).search(
            clientId: id,
            mode: _mode,
            text: q,
            offset: more ? _tracks.length : 0,
          );
      if (!mounted || gen != _generation) return;
      setState(() {
        _tracks.addAll(page.tracks);
        _hasMore = page.hasMore;
        _loading = false;
      });
    } on JamendoException catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = e;
        _hasMore = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = JamendoException('Something went wrong. Please try again.');
        _loading = false;
      });
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// Plays the first track and queues the rest.
  Future<void> _playAll(List<JamendoTrack> tracks) async {
    try {
      for (var i = 0; i < tracks.length; i++) {
        await widget.onTrack(tracks[i], queue: i > 0);
      }
      _snack('Playing ${tracks.length} tracks on the Player');
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  Future<void> _queueAll(List<JamendoTrack> tracks) async {
    try {
      for (final t in tracks) {
        await widget.onTrack(t, queue: true);
      }
      _snack('Added ${tracks.length} tracks to the Player\'s queue');
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  /// Top tracks of a genre (what the genre search already does, sorted by popularity).
  void _openGenre(String genre) {
    setState(() => _mode = JamendoSearchMode.genre);
    _search.text = genre;
    _runSearch(text: genre);
  }

  Future<void> _act(JamendoTrack t, {required bool queue}) async {
    try {
      await widget.onTrack(t, queue: queue);
      _snack(queue ? 'Added to the Player\'s queue' : 'Playing on the Player');
    } catch (e) {
      _snack(friendlyError(e));
    }
  }

  void _showLicense(JamendoTrack t) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(t.licenseLabel),
        content: SelectableText(
          '"${t.title}" by ${t.artist} is shared on Jamendo under a Creative '
          'Commons licence.\n\n'
          '${t.licenseUrl ?? 'See the track page on Jamendo for the licence.'}\n\n'
          'RemoteTunes streams it to the Player. It does not download or keep it.',
        ),
        actions: [
          if (t.licenseUrl != null)
            TextButton(
              onPressed: () => Clipboard.setData(ClipboardData(text: t.licenseUrl!)),
              child: const Text('Copy link'),
            ),
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
        ],
      ),
    );
  }

  // ------------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final history = widget.history;
    if (_showHistory && history != null) {
      return OnlineHistoryView(
        source: history,
        enabled: widget.enabled,
        onBack: () => setState(() => _showHistory = false),
      );
    }
    if (!_keyLoaded) return const Center(child: CircularProgressIndicator());
    if (_clientId == null) return _setup(context);
    return _browser(context);
  }

  Widget _setup(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Icon(Icons.travel_explore_rounded, size: 40, color: RtColors.violet),
        const SizedBox(height: 12),
        Text('Online Library', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'Find free, Creative Commons music on Jamendo and play it on the Player. '
          'Jamendo asks each app to use its own free client ID:\n\n'
          '1. Make a free account at developer.jamendo.com.\n'
          '2. Create an application there.\n'
          '3. Copy its client ID and paste it below.\n\n'
          'The ID is kept on this device only. Your own music works without any of this.',
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _keyField,
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: (_) => _saveKey(),
          decoration: InputDecoration(
            labelText: 'Jamendo client ID',
            errorText: _keyProblem,
          ),
        ),
        const SizedBox(height: 12),
        FilledButton(onPressed: _saveKey, child: const Text('Save client ID')),
        if (widget.history != null) ...[
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => setState(() => _showHistory = true),
            icon: const Icon(Icons.history_rounded),
            label: const Text('History'),
          ),
        ],
      ],
    );
  }

  Widget _browser(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      ignoring: !widget.enabled,
      child: Opacity(
        opacity: widget.enabled ? 1 : 0.5,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _search,
                      textInputAction: TextInputAction.search,
                      onSubmitted: (_) => _runSearch(),
                      decoration: InputDecoration(
                        hintText: _mode.hint,
                        prefixIcon: const Icon(Icons.search_rounded),
                      ),
                    ),
                  ),
                  if (widget.history != null)
                    IconButton(
                      tooltip: 'History',
                      icon: const Icon(Icons.history_rounded),
                      onPressed: () => setState(() => _showHistory = true),
                    ),
                  PopupMenuButton<String>(
                    tooltip: 'Jamendo options',
                    onSelected: (v) => v == 'change'
                        ? _removeKey()
                        : _showAbout(),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'about', child: Text('About this library')),
                      PopupMenuItem(value: 'change', child: Text('Change client ID')),
                    ],
                  ),
                ],
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  for (final m in JamendoSearchMode.values) ...[
                    ChoiceChip(
                      label: Text(m.label),
                      selected: _mode == m,
                      onSelected: (_) => setState(() => _mode = m),
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            if (_mode == JamendoSearchMode.genre)
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final g in jamendoGenres) ...[
                      ActionChip(
                        label: Text(g),
                        onPressed: () {
                          _search.text = g;
                          _runSearch(text: g);
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
            Expanded(child: _results(theme)),
          ],
        ),
      ),
    );
  }

  Widget _home(ThemeData theme) {
    final home = ref.watch(jamendoHomeProvider);
    return ListenableBuilder(
      listenable: home,
      builder: (context, _) {
        final firstError = JamendoShelf.values
            .map((s) => home.shelf(s).error)
            .whereType<JamendoException>()
            .firstOrNull;
        return RefreshIndicator(
          onRefresh: () async => _loadHome(refresh: true),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'Free Creative Commons music from Jamendo. Tap a cover to play it on the '
                  'Player, press and hold to add it to the queue.',
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ),
              // Top tracks of a genre.
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
                child: Text('Top tracks by genre', style: theme.textTheme.titleMedium),
              ),
              SizedBox(
                height: 44,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  children: [
                    for (final g in jamendoGenres) ...[
                      ActionChip(label: Text(g), onPressed: () => _openGenre(g)),
                      const SizedBox(width: 8),
                    ],
                  ],
                ),
              ),
              if (firstError != null && !home.anyLoaded)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    children: [
                      Icon(firstError.offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
                          size: 32, color: theme.colorScheme.error),
                      const SizedBox(height: 8),
                      Text(firstError.message, textAlign: TextAlign.center),
                      const SizedBox(height: 8),
                      if (firstError.badKey)
                        OutlinedButton(
                            onPressed: _removeKey, child: const Text('Change client ID'))
                      else
                        OutlinedButton(
                            onPressed: () => _loadHome(refresh: true),
                            child: const Text('Try again')),
                    ],
                  ),
                )
              else ...[
                for (final shelf in JamendoShelf.values)
                  _Shelf(
                    title: shelf.title,
                    state: home.shelf(shelf),
                    onPlay: (t) => _act(t, queue: false),
                    onQueue: (t) => _act(t, queue: true),
                    onPlayAll: () => _playAll(home.shelf(shelf).tracks),
                    onQueueAll: () => _queueAll(home.shelf(shelf).tracks),
                  ),
                // The best of the week in one genre; pick the genre.
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                  child: Text('Top this week by genre', style: theme.textTheme.titleMedium),
                ),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final g in jamendoGenres) ...[
                        ChoiceChip(
                          key: ValueKey('week-$g'),
                          label: Text(g),
                          selected: _weekGenre == g,
                          onSelected: (_) => _pickWeekGenre(g),
                        ),
                        const SizedBox(width: 8),
                      ],
                    ],
                  ),
                ),
                _Shelf(
                  title: 'Popular this week · $_weekGenre',
                  state: home.genreShelf(_weekGenre),
                  onPlay: (t) => _act(t, queue: false),
                  onQueue: (t) => _act(t, queue: true),
                  onPlayAll: () => _playAll(home.genreShelf(_weekGenre).tracks),
                  onQueueAll: () => _queueAll(home.genreShelf(_weekGenre).tracks),
                ),
              ],
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('Music from Jamendo',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAbout() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('About the Online Library'),
        content: const Text(
          'Music comes from Jamendo, a catalogue of Creative Commons music. '
          'Searches are sent from this device to Jamendo with your client ID. '
          'RemoteTunes keeps no listening history and sends nothing else '
          'anywhere. Tracks are streamed to the Player; nothing is downloaded '
          'or stored. Each track shows its licence; some licences do not allow '
          'commercial use.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Close')),
        ],
      ),
    );
  }

  Widget _results(ThemeData theme) {
    if (_tracks.isEmpty) {
      if (_loading) return const Center(child: CircularProgressIndicator());
      final e = _error;
      // Nothing searched yet: the ready-made shelves, when they are switched on.
      if (widget.suggestions && e == null && !_searched) return _home(theme);
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: e != null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(e.offline ? Icons.wifi_off_rounded : Icons.error_outline_rounded,
                        size: 36, color: theme.colorScheme.error),
                    const SizedBox(height: 12),
                    Text(e.message, textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    if (e.badKey)
                      OutlinedButton(onPressed: _removeKey, child: const Text('Change client ID'))
                    else if (_searched)
                      OutlinedButton(onPressed: () => _runSearch(), child: const Text('Try again')),
                  ],
                )
              : Text(
                  _searched
                      ? 'No tracks found. Try another search.'
                      : 'Search free Creative Commons music from Jamendo. It plays on the Player.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
        ),
      );
    }
    return ListView.builder(
      itemCount: _tracks.length + 1,
      itemBuilder: (context, i) {
        if (i < _tracks.length) {
          return _TrackTile(
            track: _tracks[i],
            onPlay: () => _act(_tracks[i], queue: false),
            onQueue: () => _act(_tracks[i], queue: true),
            onLicense: () => _showLicense(_tracks[i]),
          );
        }
        return Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: _loading
                ? const CircularProgressIndicator()
                : _error != null
                    ? Column(
                        children: [
                          Text(_error!.message, textAlign: TextAlign.center),
                          const SizedBox(height: 8),
                          OutlinedButton(
                              onPressed: () => _runSearch(more: true),
                              child: const Text('Try again')),
                        ],
                      )
                    : _hasMore
                        ? OutlinedButton(
                            onPressed: () => _runSearch(more: true),
                            child: const Text('Load more'))
                        : Text('Music from Jamendo',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant)),
          ),
        );
      },
    );
  }
}

class _TrackTile extends StatelessWidget {
  const _TrackTile({
    required this.track,
    required this.onPlay,
    required this.onQueue,
    required this.onLicense,
  });

  final JamendoTrack track;
  final VoidCallback onPlay;
  final VoidCallback onQueue;
  final VoidCallback onLicense;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final art = track.imageUrl;
    final placeholder = DefaultArt.album(size: 52, radius: 10);
    return ListTile(
      minTileHeight: 72,
      onTap: onPlay,
      leading: art == null
          ? placeholder
          : ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.network(
                art,
                width: 52,
                height: 52,
                fit: BoxFit.cover,
                cacheWidth: 156,
                // Where a picture can't be shown, a note is.
                errorBuilder: (_, __, ___) => placeholder,
                loadingBuilder: (c, child, p) => p == null ? child : placeholder,
              ),
            ),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('${track.artist} · ${track.album}',
              maxLines: 1, overflow: TextOverflow.ellipsis),
          Row(
            children: [
              if (track.durationSeconds > 0)
                Text('${formatDuration(track.durationSeconds)}  ',
                    style: theme.textTheme.bodySmall?.copyWith(color: muted)),
              Flexible(
                child: InkWell(
                  onTap: onLicense,
                  child: Text(
                    track.licenseLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                        color: RtColors.violet, decoration: TextDecoration.underline),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Play on Player',
            icon: const Icon(Icons.play_circle_fill_rounded),
            onPressed: onPlay,
          ),
          IconButton(
            tooltip: 'Add to queue',
            icon: const Icon(Icons.playlist_add_rounded),
            onPressed: onQueue,
          ),
        ],
      ),
    );
  }
}

/// One row of covers on the home screen.
class _Shelf extends StatelessWidget {
  const _Shelf({
    required this.title,
    required this.state,
    required this.onPlay,
    required this.onQueue,
    required this.onPlayAll,
    required this.onQueueAll,
  });

  final String title;
  final ShelfState state;
  final void Function(JamendoTrack) onPlay;
  final void Function(JamendoTrack) onQueue;
  final VoidCallback onPlayAll;
  final VoidCallback onQueueAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tracks = state.tracks;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 4, 0),
          child: Row(
            children: [
              Expanded(child: Text(title, style: theme.textTheme.titleMedium)),
              if (tracks.isNotEmpty) ...[
                IconButton(
                  tooltip: 'Play all of "$title"',
                  icon: const Icon(Icons.play_circle_outline_rounded),
                  onPressed: onPlayAll,
                ),
                IconButton(
                  tooltip: 'Add all of "$title" to the queue',
                  icon: const Icon(Icons.playlist_add_rounded),
                  onPressed: onQueueAll,
                ),
              ],
            ],
          ),
        ),
        SizedBox(
          height: 178,
          child: tracks.isEmpty
              ? Center(
                  child: state.error != null
                      ? Text(state.error!.message, textAlign: TextAlign.center)
                      : const CircularProgressIndicator(strokeWidth: 2),
                )
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: tracks.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 12),
                  itemBuilder: (context, i) => _Cover(
                    track: tracks[i],
                    onTap: () => onPlay(tracks[i]),
                    onLongPress: () => onQueue(tracks[i]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _Cover extends StatelessWidget {
  const _Cover({required this.track, required this.onTap, required this.onLongPress});

  final JamendoTrack track;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final art = track.imageUrl;
    final placeholder = DefaultArt.album(size: 120, radius: 12);
    return Semantics(
      label: '${track.title} by ${track.artist}',
      button: true,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        onLongPress: onLongPress,
        child: SizedBox(
          width: 120,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              art == null
                  ? placeholder
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.network(
                        art,
                        width: 120,
                        height: 120,
                        fit: BoxFit.cover,
                        cacheWidth: 240,
                        errorBuilder: (_, __, ___) => placeholder,
                        loadingBuilder: (c, child, p) => p == null ? child : placeholder,
                      ),
                    ),
              const SizedBox(height: 6),
              Text(track.title,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium),
              Text(track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}
