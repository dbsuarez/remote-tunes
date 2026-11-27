import 'audiobook_tracker.dart';
import 'playback_log.dart';
import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'dart:math' as math;

import '../../core/models/enums.dart';
import '../../core/protocol/library_models.dart';
import '../../core/protocol/protocol.dart';
import '../../core/url_validation.dart';
import 'audio/audio_backend.dart';
import 'playback_engine.dart';
import 'queue/playable_song.dart';
import 'group_sync_source.dart';
import 'queue/queue_controller.dart';
import 'queue/queue_store.dart';
import 'queue_aware_engine.dart';
import 'silence_finder.dart';
import 'url_checker.dart';

/// The real Player engine: a [QueueController] driving an [AudioBackend].
///
/// All public commands run one at a time, so a burst of taps from a Controller
/// (or the notification) can never interleave half-finished track changes.
class QueuePlaybackEngine implements QueueAwareEngine, GroupSyncSource {
  QueuePlaybackEngine({
    required AudioBackend backend,
    QueueController? queue,
    double initialVolume = 0.8,
    bool Function(String path)? fileExists,
    UrlChecker? urlChecker,
    this.onSongStarted,
    this.onSongSkipped,
    this.onSongEnded,
    this.audiobooks,
    this.onStreamStarted,
    this.queueStore,
    this.formatReader,
    this.soundEnd,
  })  : _backend = backend,
        _queue = queue ?? QueueController(),
        _volume = initialVolume.clamp(0.0, 1.0),
        _fileExists = fileExists ?? ((p) => File(p).existsSync()),
        _urlChecker = urlChecker ?? HttpUrlChecker() {
    _subs.add(_backend.positionStream.listen(_onPosition));
    _subs.add(_backend.playingStream.listen(_onPlaying));
    _subs.add(_backend.durationStream.listen(_onDuration));
    _subs.add(_backend.errorStream.listen(_onError));
    _subs.add(_backend.completedStream.listen((_) {
      _serial(_onCompleted).catchError((Object _) {});
    }));
    _subs.add(_backend.advancedStream.listen((path) {
      _serial(() => _onAdvanced(path)).catchError((Object _) {});
    }));
    unawaited(_backend.setVolume(_volume));
  }

  final AudioBackend _backend;

  // ---------------------------------------------------------- skips

  /// Called with a library song's id when it was skipped: left in the first 30
  /// seconds (or the first half, for a short song) by moving on or choosing
  /// another.
  void Function(int songId)? onSongSkipped;

  /// Called when a library song stops being played, for the play log: when it started, how many
  /// seconds were really heard, and how it ended (`finished`, `skipped` or `stopped`).
  final void Function(int songId, DateTime startedAt, int heardSeconds, String outcome)? onSongEnded;

  /// Audiobooks remember where they were left, and are never faded into or lined up gaplessly
  /// (they start where they were left). Null: no audiobooks (all songs are music).
  final AudiobookTracker? audiobooks;

  bool _isBook(PlayableSong s) {
    final id = s.libraryId;
    return id != null && (audiobooks?.isAudiobook(id) ?? false);
  }

  /// The audiobook is saved about every ten seconds of listening, and when it is paused or left.
  int _bookSavedMs = 0;

  void _saveBookPlace({bool finished = false}) {
    final id = _trackedId;
    final tracker = audiobooks;
    if (id == null || tracker == null || !tracker.isAudiobook(id)) return;
    final seconds = finished ? 0 : (_lastPositionMs / 1000).round();
    _bookSavedMs = _lastPositionMs;
    unawaited(tracker.save(id, seconds, finished: finished).catchError((Object _) {}));
  }

  DateTime _trackedStart = DateTime.fromMillisecondsSinceEpoch(0);
  int? _trackedId;
  int _trackedDurationMs = 0;
  int _listenedMs = 0;
  int _lastPositionMs = 0;

  void _beginTracking(PlayableSong song) {
    _trackedId = song.libraryId;
    _trackedStart = DateTime.now();
    _bookSavedMs = 0;
    _trackedDurationMs = song.durationSeconds * 1000;
    _listenedMs = 0;
    _lastPositionMs = 0;
  }

  /// The song that was tracked has ended: [finished] when it played to its end.
  void _endTracking({required bool finished}) {
    // An audiobook remembers its place (a song that ended is forgotten, to start again).
    _saveBookPlace(finished: finished);
    final id = _trackedId;
    _trackedId = null;
    if (id == null) return;
    if (finished) {
      onSongEnded?.call(id, _trackedStart, (_listenedMs / 1000).round(), 'finished');
      return;
    }
    // Short songs count by half their length, long ones by thirty seconds.
    final limit = _trackedDurationMs > 0 ? math.min(30000, _trackedDurationMs ~/ 2) : 30000;
    if (_listenedMs < limit) {
      PlaybackLog.add('engine: skipped (heard $_listenedMs ms)');
      onSongSkipped?.call(id);
      onSongEnded?.call(id, _trackedStart, (_listenedMs / 1000).round(), 'skipped');
    } else {
      onSongEnded?.call(id, _trackedStart, (_listenedMs / 1000).round(), 'stopped');
    }
  }

  /// Adds the time that really passed while playing (a jump in the position, a
  /// seek, is not listening).
  void _trackListening(Duration position) {
    if (_trackedId == null) return;
    final ms = position.inMilliseconds;
    final delta = ms - _lastPositionMs;
    _lastPositionMs = ms;
    if (_playing && delta > 0 && delta < 1500) _listenedMs += delta;
    if (_playing && ms - _bookSavedMs >= 10000) _saveBookPlace();
  }

  /// Reads what a file is (sample rate, bitrate, type) for the Now Playing
  /// line; null: not shown.
  final Future<String?> Function(String path)? formatReader;
  String _format = '';

  // ---------------------------------------------------------- silent ends

  /// Finds where a song falls silent (null: songs play to their end).
  final Future<SoundEnd?> Function(String path)? soundEnd;

  /// A silent end longer than this is skipped, this long after the sound stops.
  static const longSilence = Duration(seconds: 5);
  static const silenceKept = Duration(seconds: 1);

  bool _skipSilence = false;

  /// Where the loaded song is to be left, in ms, if its end is silent.
  int? _cutMs;
  bool _cutDone = false;

  Future<void> setSkipSilence(bool skip) => _serial(() async {
        if (_skipSilence == skip) return;
        _skipSilence = skip;
        final current = _queue.current;
        if (current != null && current.id == _loadedEntryId) {
          _findCut(current);
        } else {
          _cutMs = null;
        }
      });

  /// Looks for the silent end of [entry], just loaded, without holding anything up. Audiobooks and
  /// internet streams are left alone.
  void _findCut(QueueEntry entry) {
    _cutMs = null;
    _cutDone = false;
    final finder = soundEnd;
    final path = entry.song.filePath;
    if (!_skipSilence || finder == null || path == null || _isBook(entry.song)) return;
    unawaited(() async {
      SoundEnd? found;
      try {
        found = await finder(path);
      } catch (_) {
        found = null;
      }
      if (found == null || _disposed || !_skipSilence || _loadedEntryId != entry.id) return;
      if (found.durationMs - found.endMs <= longSilence.inMilliseconds) return;
      _cutMs = found.endMs + silenceKept.inMilliseconds;
      PlaybackLog.add('engine: entry ${entry.id} is silent from ${found.endMs} of ${found.durationMs} ms');
    }());
  }

  /// At the cut the song counts as finished: the next one starts.
  void _maybeSkipSilence(Duration position) {
    final cut = _cutMs;
    if (cut == null) return;
    // Back before it (repeat one, or a seek): it can happen again.
    if (position.inMilliseconds < cut - 1000) _cutDone = false;
    if (_cutDone || _crossfading || !_playing || position.inMilliseconds < cut) return;
    final id = _loadedEntryId;
    if (id == null) return;
    _cutDone = true;
    _serial(() async {
      if (_loadedEntryId != id || !_playing || _crossfading) return;
      PlaybackLog.add('engine: the rest of entry $id is silence, moving on');
      await _onCompleted();
    }).catchError((Object _) {});
  }

  // --------------------------------------------------------- stop after song

  /// Waiting to pause when the song playing ends (the sleep timer's last song).
  void Function()? _stopAfter;

  /// Pauses once the song playing ends, with the next one ready, and calls [done]. False if there is
  /// no end to wait for (nothing playing, or a stream with no length).
  Future<bool> stopAfterSong(void Function() done) => _serial(() async {
        if (!_playing || _loadedEntryId == null || _durationSeconds <= 0) return false;
        _stopAfter = done;
        // Nothing is lined up behind it, so it cannot run into the next song.
        _preloadKey = null;
        _preloadIfChanged();
        return true;
      });

  void cancelStopAfterSong() {
    if (_stopAfter == null) return;
    _stopAfter = null;
    _preloadKey = null;
    _preloadIfChanged();
  }

  void _stoppedAfterSong() {
    final done = _stopAfter;
    _stopAfter = null;
    _preloadKey = null;
    PlaybackLog.add('engine: stopped after the last song (sleep timer)');
    done?.call();
  }

  /// Saves the queue so it survives a restart (null: not saved).
  final QueueStore? queueStore;
  Timer? _saveTimer;
  int _savedRevision = -1;
  int _savedIndex = -2;
  int _savedPositionSeconds = 0;

  /// After a restart: carry on from this spot when the restored song is first
  /// played.
  int _resumeSeconds = 0;
  int? _resumeEntryId;

  /// Called with the library id when a library song starts playing (used for
  /// "recently played").
  final void Function(int songId)? onSongStarted;

  /// Called when an internet track (Online Library) starts playing (used for
  /// the Online Library history).
  final void Function(PlayableSong song)? onStreamStarted;
  final QueueController _queue;
  final bool Function(String path) _fileExists;
  final UrlChecker _urlChecker;
  final List<StreamSubscription<dynamic>> _subs = [];
  final StreamController<PlaybackState> _controller =
      StreamController<PlaybackState>.broadcast();

  /// Entry whose file is loaded in the backend (null if none).
  int? _loadedEntryId;
  bool _playing = false;
  int _positionSeconds = 0;
  int _durationSeconds = 0;
  double _volume;
  double _speed = 1.0;

  /// The speed music had before an audiobook changed it (null: not in a book).
  double? _speedBeforeBook;
  bool _disposed = false;

  ReplayGainMode _replayGain = ReplayGainMode.off;

  /// How loud songs are evened out from their Replay Gain tags. It only turns
  /// loud songs down (never up, which could distort).
  Future<void> setReplayGainMode(ReplayGainMode mode) => _serial(() async {
        _replayGain = mode;
        await _backend.setVolume(_effectiveVolume());
      });

  /// The volume given to the audio player: the chosen volume times the Replay
  /// Gain adjustment of the song that is loaded.
  double _effectiveVolume() => (_volume * _replayGainFactor()).clamp(0.0, 1.0);

  double _replayGainFactor() {
    if (_replayGain == ReplayGainMode.off) return 1.0;
    final id = _loadedEntryId;
    if (id == null) return 1.0;
    final song = _queue.current?.id == id ? _queue.current?.song : null;
    if (song == null) return 1.0;
    final db = _replayGain == ReplayGainMode.album
        ? (song.albumGainDb ?? song.replayGainDb)
        : song.replayGainDb;
    if (db == null || db >= 0) return 1.0;
    return math.pow(10, db / 20).toDouble();
  }

  /// True while a track is being opened (an internet stream can take seconds).
  bool _loading = false;

  /// Plain-language playback problem for the UI; cleared when a track starts.
  String _error = '';

  Future<void> _tail = Future.value();

  /// Runs [action] after all earlier actions finished.
  Future<T> _serial<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    return completer.future;
  }

  // ------------------------------------------------------------------- state

  @override
  PlaybackState get state {
    final entry = _queue.current;
    final song = entry?.song;
    final ci = _queue.currentIndex;
    return PlaybackState(
      title: song?.title ?? '',
      artist: song?.artist ?? '',
      album: song?.album ?? '',
      positionSeconds: _positionSeconds,
      durationSeconds: _durationSeconds,
      isPlaying: _playing && _loadedEntryId != null,
      queueIndex: ci < 0 ? 0 : ci,
      queueLength: _queue.length,
      volume: _volume,
      repeatMode: _queue.repeat,
      shuffleEnabled: _queue.shuffle,
      source: song?.isUrl == true ? 'url' : 'local_file',
      songId: song?.libraryId,
      queueRevision: _queue.revision,
      isLoading: _loading,
      error: _error,
      localArtPath: song?.albumArtPath,
      speed: _speed,
      format: _format,
    );
  }

  /// Looks up what the file that just started is, without holding anything up.
  void _readFormat(QueueEntry entry) {
    _format = '';
    final reader = formatReader;
    final path = entry.song.filePath;
    if (reader == null || path == null) return;
    unawaited(() async {
      String? f;
      try {
        f = await reader(path);
      } catch (_) {
        f = null;
      }
      if (_disposed || f == null || f.isEmpty || _loadedEntryId != entry.id) return;
      _format = f;
      _emit();
    }());
  }

  @override
  Stream<PlaybackState> get states => _controller.stream;

  @override
  int? get positionMsNow {
    if (_loadedEntryId == null) return null;
    try {
      return _backend.position.inMilliseconds;
    } catch (_) {
      return _positionSeconds * 1000;
    }
  }

  @override
  int? get nextLibrarySongId {
    final next = _queue.peekNext();
    return next?.song.libraryId;
  }

  void _emit() {
    if (!_disposed && !_controller.isClosed) _controller.add(state);
    _scheduleSave();
    _preloadIfChanged();
  }

  // -------------------------------------------------------- gapless playback

  /// The queue entry whose file the backend has lined up after the loaded one.
  int? _preloadedEntryId;
  String? _preloadKey;
  Future<void> _preloadTail = Future.value();

  /// Lines up the song that follows the current one so the change is gapless.
  /// Cheap to call often: it only acts when the queue, the current song or the
  /// shuffle/repeat choice changed.
  void _preloadIfChanged() {
    if (_disposed) return;
    final key = '${_queue.revision}|${_queue.shuffle}|${_queue.repeat}|'
        '$_loadedEntryId|${_queue.current?.id}|$_crossfadeActive|${_stopAfter != null}';
    if (key == _preloadKey) return;
    _preloadKey = key;
    _preloadTail = _preloadTail.then((_) async {
      if (_disposed) return;
      QueueEntry? want;
      final cur = _queue.current;
      // With crossfade the next song is started by the fade, not lined up.
      if (!_crossfadeActive && _stopAfter == null && _loadedEntryId != null && cur != null && cur.id == _loadedEntryId) {
        final n = _queue.peekNext();
        final path = n?.song.filePath;
        if (n != null &&
            !_isBook(n.song) &&
            n.id != cur.id &&
            !n.song.isUrl &&
            path != null &&
            _fileExists(path)) {
          want = n;
        }
      }
      if (want?.id == _preloadedEntryId) return;
      _preloadedEntryId = want?.id;
      try {
        await _backend.setNext(want?.song.filePath);
      } catch (_) {
        _preloadedEntryId = null;
      }
    });
  }

  /// The backend moved on by itself to the lined-up file.
  Future<void> _onAdvanced(String? path) async {
    final fadedInto = _manualFade;
    if (fadedInto != null) {
      // Next / Previous faded into this one: the screen already shows it.
      _manualFade = null;
      _crossfading = false;
      PlaybackLog.add('engine: the fade into entry $fadedInto finished');
      if (_loadedEntryId == fadedInto) {
        if (_replayGain != ReplayGainMode.off) {
          unawaited(_backend.setVolume(_effectiveVolume()));
        }
        _emit();
        return;
      }
    }
    final expected = _preloadedEntryId;
    _preloadedEntryId = null;
    _crossfading = false;
    final next = _queue.advance(auto: true);
    PlaybackLog.add('engine: moved on by itself (expected ${expected ?? '-'}, queue gives '
        '${next?.id ?? '-'}, same file: ${next != null && next.song.filePath == path})');
    // The player is already playing the right file: take it over as it is. (It must
    // never be loaded again, which would start the song from its beginning.)
    if (next != null && path != null && next.song.filePath == path && next.id != expected) {
      PlaybackLog.add('engine: kept the song playing (the lined-up entry differed)');
    }
    if (next == null || next.song.filePath != path) {
      // Out of step with the queue (it changed just then): load it properly.
      if (next != null) {
        PlaybackLog.add('engine: loading ${next.id} again (the file differs)');
        try {
          await _startEntry(next, autoplay: true);
        } on PlaybackException {
          // Reported through state.
        }
      }
      return;
    }
    final song = next.song;
    _endTracking(finished: true);
    _loadedEntryId = next.id;
    _findCut(next);
    if (_replayGain != ReplayGainMode.off) {
      unawaited(_backend.setVolume(_effectiveVolume()));
    }
    _readFormat(next);
    _positionSeconds = 0;
    _durationSeconds = song.durationSeconds;
    _error = '';
    _loading = false;
    _playing = true;
    final id = song.libraryId;
    if (id != null) {
      onSongStarted?.call(id);
      _beginTracking(song);
    }
    // It had already run into the next song (a fade under way): that one waits at its start.
    if (_stopAfter != null) {
      await _backend.pause();
      await _backend.seek(Duration.zero);
      _playing = false;
      _stoppedAfterSong();
    }
    _emit();
  }

  /// Saves shortly after the queue or the current song changes, so a burst of
  /// changes is one write.
  void _scheduleSave() {
    if (queueStore == null || _disposed) return;
    // The spot in the song is saved every ten seconds while playing, and as soon
    // as it stops, not every second.
    final positionStale = _loadedEntryId != null &&
        (_playing
            ? (_positionSeconds - _savedPositionSeconds).abs() >= 10
            : _positionSeconds != _savedPositionSeconds);
    if (_queue.revision == _savedRevision &&
        _queue.currentIndex == _savedIndex &&
        !positionStale) {
      return;
    }
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () => unawaited(_saveQueue()));
  }

  Future<void> _saveQueue() async {
    final store = queueStore;
    if (store == null) return;
    _saveTimer?.cancel();
    _saveTimer = null;
    final revision = _queue.revision;
    final songs = [for (final e in _queue.entries) e.song];
    final currentIndex = _queue.currentIndex;
    // (Only songs with a known length can be resumed: not live internet streams.)
    final position = (_loadedEntryId != null || _resumeEntryId != null) &&
            _durationSeconds > 0
        ? _positionSeconds
        : 0;
    try {
      await store.save(songs, currentIndex < 0 ? 0 : currentIndex,
          positionSeconds: position);
      _savedRevision = revision;
      _savedIndex = currentIndex;
      _savedPositionSeconds = position;
    } catch (_) {
      // The queue just will not be remembered this time.
    }
  }

  /// Loads the saved queue (if this one is empty), paused on the song it was
  /// on. Call once, right after creating the engine.
  Future<void> restoreQueue() => _serial(() async {
        final store = queueStore;
        if (store == null || !_queue.isEmpty) return;
        final saved = await store.load();
        if (saved.songs.isEmpty) return;
        _queue.replace(saved.songs, startIndex: saved.currentIndex);
        _savedRevision = _queue.revision;
        _savedIndex = _queue.currentIndex;
        // Show where it was, and carry on from there when it is played.
        final current = _queue.current;
        if (current != null && saved.positionSeconds > 0 && current.song.durationSeconds > 0) {
          _resumeEntryId = current.id;
          _resumeSeconds = saved.positionSeconds;
          _positionSeconds = saved.positionSeconds;
          _durationSeconds = current.song.durationSeconds;
          _savedPositionSeconds = saved.positionSeconds;
        }
        _emit();
      });

  // ---------------------------------------------------------------- crossfade

  int _crossfadeSeconds = 0;
  bool _crossfading = false;

  /// The entry Next / Previous is fading into right now (the screen already shows
  /// it; the old song is still fading out under it).
  int? _manualFade;

  bool get _crossfadeActive => _crossfadeSeconds > 0 && _backend.supportsCrossfade;

  /// How long one song fades into the next (0: off). Only works when the audio
  /// backend can run two players; otherwise songs change gaplessly as before.
  Future<void> setCrossfade(int seconds) => _serial(() async {
        _crossfadeSeconds = seconds.clamp(0, 12);
        _preloadKey = null;
        _preloadIfChanged();
      });

  /// Pressing Next (or Previous) can fade too: only while a song plays, into a file on
  /// this phone, and not while another fade is running.
  bool _canFadeInto(QueueEntry entry, bool wasPlaying) {
    final path = entry.song.filePath;
    return _crossfadeActive &&
        !_isBook(entry.song) &&
        wasPlaying &&
        !_crossfading &&
        !_loading &&
        _loadedEntryId != null &&
        entry.id != _loadedEntryId &&
        !entry.song.isUrl &&
        path != null &&
        _fileExists(path);
  }

  /// Starts the fade into [entry] at once. The screen switches to it straight away;
  /// the old song fades out underneath. False if the fade could not start.
  Future<bool> _fadeInto(QueueEntry entry) async {
    final song = entry.song;
    final path = song.filePath!;
    final len = _crossfadeSeconds;
    _endTracking(finished: false);
    _manualFade = entry.id;
    _crossfading = true;
    _preloadedEntryId = null;
    PlaybackLog.add('engine: fade ${len}s into entry ${entry.id} (Next / Previous)');
    // Not awaited: the answer comes when the fade is over (the command must not hold
    // up pause / next for the whole fade).
    unawaited(() async {
      var ok = false;
      try {
        ok = await _backend.crossfadeTo(path, Duration(seconds: len), immediate: true);
      } catch (_) {
        ok = false;
      }
      if (!ok && !_disposed && _manualFade == entry.id) {
        // It could not fade: change the ordinary way.
        PlaybackLog.add('engine: the fade failed, changing without it');
        _crossfading = false;
        await _serial(() async {
          if (_manualFade != entry.id) return;
          try {
            await _startEntry(entry, autoplay: true);
          } on PlaybackException {
            // Reported through state.
          }
        });
      }
    }());
    // The screen shows the new song now.
    _loadedEntryId = entry.id;
    _findCut(entry);
    _readFormat(entry);
    _positionSeconds = 0;
    _durationSeconds = song.durationSeconds;
    _error = '';
    _loading = false;
    _playing = true;
    final id = song.libraryId;
    if (id != null) {
      onSongStarted?.call(id);
      _beginTracking(song);
    }
    _emit();
    return true;
  }

  /// Near the end of a song, starts fading into the next one.
  void _maybeCrossfade(Duration position) {
    if (_stopAfter != null || !_crossfadeActive || _crossfading || !_playing || _loadedEntryId == null) return;
    final len = _crossfadeSeconds;
    // A song with a silent end fades out where its sound stops.
    final cut = _cutMs;
    final endMs = cut ?? _durationSeconds * 1000;
    // Songs too short to fade (twice the fade, plus a little) just change.
    if (endMs < (2 * len + 6) * 1000) return;
    // Started a little early: the next song loads (a cold player is slow) and the
    // backend begins the fade at exactly the right moment.
    final remainingMs = endMs - position.inMilliseconds;
    // At a cut the backend cannot time the fade itself (the file goes on), so it starts at once.
    final early = cut == null ? 2500 : 500;
    if (remainingMs > len * 1000 + early || (cut == null && remainingMs < 0)) return;
    final cur = _queue.current;
    if (cur == null || cur.id != _loadedEntryId) return;
    final next = _queue.peekNext();
    final path = next?.song.filePath;
    if (next == null ||
        _isBook(next.song) ||
        next.id == cur.id ||
        next.song.isUrl ||
        path == null ||
        !_fileExists(path)) {
      return;
    }
    _crossfading = true;
    _preloadedEntryId = next.id;
    PlaybackLog.add('engine: fade ${len}s starts at ${position.inMilliseconds} ms of '
        '$_durationSeconds s (queue ${_queue.currentIndex} -> next ${next.id})');
    // Not through the command queue: it would hold up pause / next for the whole
    // fade. The backend ends the fade by itself when a new song is loaded.
    unawaited(() async {
      var ok = false;
      try {
        ok = await _backend.crossfadeTo(path, Duration(seconds: len), immediate: cut != null);
      } catch (_) {
        ok = false;
      }
      if (!ok && !_disposed) {
        _crossfading = false;
        _preloadedEntryId = null;
      }
    }());
  }

  void _onPosition(Duration d) {
    // The old song's positions while it fades out are not the new song's.
    if (_manualFade != null) return;
    _trackListening(d);
    _maybeCrossfade(d);
    _maybeSkipSilence(d);
    final s = d.inSeconds;
    if (s != _positionSeconds && _loadedEntryId != null) {
      _positionSeconds = s;
      _emit();
    }
  }

  void _onPlaying(bool playing) {
    if (playing != _playing) {
      _playing = playing;
      _emit();
    }
  }

  /// Streams often learn their length after loading.
  void _onDuration(Duration? d) {
    if (d == null || _loadedEntryId == null) return;
    final s = d.inSeconds;
    if (s != _durationSeconds && (_queue.current?.song.durationSeconds ?? 0) == 0) {
      _durationSeconds = s;
      _emit();
    }
  }

  /// A problem after the track loaded (e.g. the stream dropped).
  void _onError(String message) {
    if (_loadedEntryId == null) return;
    _playing = false;
    _error = message;
    _emit();
  }

  // ---------------------------------------------------------------- playback

  /// Loads [entry] and optionally starts it. If its file is missing or broken
  /// it is skipped and the next entry is tried; throws if none can play.
  Future<void> _startEntry(QueueEntry entry, {required bool autoplay}) async {
    _manualFade = null;
    _endTracking(finished: false);
    var current = entry;
    var attempts = 0;
    PlaybackException? last;

    while (true) {
      attempts++;
      final song = current.song;
      final path = song.filePath;
      if (path != null && !_fileExists(path)) {
        last = PlaybackException(
          ErrorCodes.fileNotFound,
          '"${song.title}" is missing from this phone.',
        );
      } else {
        try {
          if (song.isUrl) {
            // Opening a stream can take a few seconds: tell the UI.
            _loading = true;
            _error = '';
            _emit();
          }
          PlaybackLog.add('engine: loads entry ${current.id} (autoplay: $autoplay)');
          final duration = song.isUrl
              ? await _backend.loadUrl(song.url!)
              : await _backend.load(path!);
          _loadedEntryId = current.id;
          _findCut(current);
          if (_replayGain != ReplayGainMode.off) await _backend.setVolume(_effectiveVolume());
          // Loading cleared whatever was lined up behind the old track.
          _crossfading = false;
          _readFormat(current);
          _preloadedEntryId = null;
          _preloadKey = null;
          _positionSeconds = 0;
          _durationSeconds =
              song.durationSeconds > 0 ? song.durationSeconds : (duration?.inSeconds ?? 0);
          _error = '';
          _loading = false;
          // An audiobook keeps its own speed (per book); music gets its speed back afterwards.
          final speedBefore = _speed;
          final speedId = song.libraryId;
          if (speedId != null && (audiobooks?.isAudiobook(speedId) ?? false)) {
            final saved = await audiobooks!.speedOf(speedId);
            _speedBeforeBook ??= _speed;
            // A book with no speed of its own plays at the speed music had.
            _speed = saved ?? _speedBeforeBook!;
          } else if (_speedBeforeBook != null) {
            _speed = _speedBeforeBook!;
            _speedBeforeBook = null;
          }
          if (_speed != 1.0 || _speed != speedBefore) await _backend.setSpeed(_speed);
          // First play after a restart: carry on from the saved spot (a little
          // before the end at most, so it does not finish at once).
          if (_resumeEntryId == current.id && _resumeSeconds > 0) {
            final limit = _durationSeconds > 3 ? _durationSeconds - 2 : 0;
            final at = _resumeSeconds > limit ? limit : _resumeSeconds;
            if (at > 0) {
              await _backend.seek(Duration(seconds: at));
              _positionSeconds = at;
            }
          }
          // An audiobook carries on where it was left (unless the queue was just restored, which
          // already knows the exact spot).
          final bookId = song.libraryId;
          if (_resumeEntryId != current.id && bookId != null && (audiobooks?.isAudiobook(bookId) ?? false)) {
            final saved = await audiobooks!.placeOf(bookId);
            // Not at the very start, and not so near the end that it would finish at once.
            if (saved > 10 && (_durationSeconds == 0 || saved < _durationSeconds - 15)) {
              await _backend.seek(Duration(seconds: saved));
              _positionSeconds = saved;
              _lastPositionMs = saved * 1000;
            }
          }
          _resumeEntryId = null;
          _resumeSeconds = 0;
          if (autoplay) {
            await _backend.play();
            _playing = true;
            final id = song.libraryId;
            if (id != null) {
              onSongStarted?.call(id);
              _beginTracking(song);
              _lastPositionMs = _positionSeconds * 1000;
              _bookSavedMs = _lastPositionMs;
              unawaited(audiobooks?.started(id).catchError((Object _) {}));
            }
            if (song.isUrl) onStreamStarted?.call(song);
          }
          _emit();
          return;
        } on AudioBackendException catch (e) {
          _loading = false;
          last = PlaybackException(ErrorCodes.playbackFailed, e.message);
        }
      }

      // This entry could not play: try the next one, a bounded number of times.
      final next = _queue.advance(auto: false);
      if (next == null || attempts >= _queue.length) {
        _loadedEntryId = null;
        _playing = false;
        _loading = false;
        _positionSeconds = 0;
        _emit();
        throw last;
      }
      current = next;
    }
  }

  @override
  Future<void> play() => _serial(() async {
        if (_queue.isEmpty) {
          throw PlaybackException(
            ErrorCodes.queueEmpty,
            'The queue is empty. Add songs first.',
          );
        }
        final entry = _queue.current ?? _queue.advance(auto: false)!;
        if (entry.id != _loadedEntryId) {
          await _startEntry(entry, autoplay: true);
        } else {
          _error = '';
          await _backend.play();
          _playing = true;
          _emit();
        }
      });

  @override
  Future<void> pause() => _serial(() async {
        await _backend.pause();
        _playing = false;
        _saveBookPlace();
        _emit();
      });

  @override
  Future<void> toggle() async {
    if (_playing && _loadedEntryId != null) {
      await pause();
    } else {
      await play();
    }
  }

  @override
  Future<void> next() => _serial(() async {
        final wasPlaying = _playing;
        final next = _queue.advance(auto: false);
        if (next == null) return; // End of queue: nothing to do.
        if (_canFadeInto(next, wasPlaying) && await _fadeInto(next)) return;
        await _startEntry(next, autoplay: wasPlaying);
      });

  @override
  Future<void> previous() => _serial(() async {
        if (_queue.current == null) return;
        // Like most players: restart the track if it has played a few seconds.
        if (_positionSeconds > 3) {
          await _seekTo(0);
          return;
        }
        final before = _queue.current!.id;
        final wasPlaying = _playing;
        final target = _queue.back();
        if (target == null) return;
        if (target.id == before) {
          await _seekTo(0);
        } else if (_canFadeInto(target, wasPlaying) && await _fadeInto(target)) {
          return;
        } else {
          await _startEntry(target, autoplay: wasPlaying);
        }
      });

  @override
  Future<void> stop() => _serial(() async {
        await _backend.pause();
        if (_loadedEntryId != null) await _backend.seek(Duration.zero);
        _playing = false;
        _positionSeconds = 0;
        _emit();
      });

  Future<void> _seekTo(int seconds) async {
    await _backend.seek(Duration(seconds: seconds));
    _positionSeconds = seconds;
    _emit();
  }

  @override
  Future<void> seek(int positionSeconds) => _serial(() async {
        if (_loadedEntryId == null) {
          throw PlaybackException(
            ErrorCodes.queueEmpty,
            'Nothing is loaded to seek in.',
          );
        }
        final max = _durationSeconds;
        if (positionSeconds < 0 || (max > 0 && positionSeconds > max)) {
          throw PlaybackException(
            ErrorCodes.invalidPosition,
            'That position is outside the track (0–${max}s).',
          );
        }
        await _seekTo(positionSeconds);
      });

  @override
  Future<void> setVolume(double volume) => _serial(() async {
        if (volume.isNaN || volume < 0 || volume > 1) {
          throw PlaybackException(
            ErrorCodes.invalidAction,
            'Volume must be between 0 and 1.',
          );
        }
        _volume = volume;
        await _backend.setVolume(_effectiveVolume());
        _emit();
      });

  @override
  Future<void> setSpeed(double speed) => _serial(() async {
        if (speed.isNaN || speed < 0.5 || speed > 2.0) {
          throw PlaybackException(
            ErrorCodes.invalidAction,
            'Speed must be between 0.5 and 2.',
          );
        }
        _speed = speed;
        await _backend.setSpeed(speed);
        // In an audiobook the speed is kept for that book.
        final bookId = _queue.current?.song.libraryId;
        if (bookId != null && _loadedEntryId != null && (audiobooks?.isAudiobook(bookId) ?? false)) {
          unawaited(audiobooks!.saveSpeed(bookId, speed).catchError((Object _) {}));
        }
        _emit();
      });

  Future<void> _onCompleted() async {
    PlaybackLog.add('engine: the song ended (loaded $_loadedEntryId, position $_positionSeconds s '
        'of $_durationSeconds s)');
    // It played to its end.
    _endTracking(finished: true);
    final last = _stopAfter != null;
    final next = _queue.advance(auto: true);
    if (next == null) {
      // End of the queue: rewind and stop, staying on the last track.
      await _backend.pause();
      await _backend.seek(Duration.zero);
      _playing = false;
      _positionSeconds = 0;
      if (last) _stoppedAfterSong();
      _emit();
      return;
    }
    try {
      if (last) {
        // The next song is made ready, paused.
        if (next.id == _loadedEntryId) {
          await _backend.pause();
          await _backend.seek(Duration.zero);
          _playing = false;
          _positionSeconds = 0;
        } else {
          await _backend.pause();
          _playing = false;
          await _startEntry(next, autoplay: false);
        }
        _stoppedAfterSong();
        _emit();
        return;
      }
      if (next.id == _loadedEntryId) {
        // Repeat-one: replay the loaded track.
        _beginTracking(next.song);
        await _backend.seek(Duration.zero);
        await _backend.play();
        _positionSeconds = 0;
        _playing = true;
        _emit();
      } else {
        await _startEntry(next, autoplay: true);
      }
    } on PlaybackException {
      // _startEntry already reset the state; nothing else to play.
    }
  }

  // ------------------------------------------------------------------- queue

  final _random = Random();

  @override
  Future<void> playSongs(List<PlayableSong> songs, {int? startIndex}) =>
      _serial(() async {
        if (songs.isEmpty) {
          throw PlaybackException(
            ErrorCodes.queueEmpty,
            'There are no songs to play.',
          );
        }
        _queue.replace(songs, startIndex: startIndex ?? _startOfList(songs));
        await _startEntry(_queue.current!, autoplay: true);
      });

  /// Where a list starts when no song was picked: any song that can play with shuffle on, else the
  /// first. A list of audiobooks starts at the beginning.
  int _startOfList(List<PlayableSong> songs) {
    if (!_queue.shuffle || (audiobooks?.isAudiobook(songs.first.id) ?? false)) return 0;
    final playable = [
      for (var i = 0; i < songs.length; i++)
        if (songs[i].isUrl || _fileExists(songs[i].filePath!)) i,
    ];
    return playable.isEmpty ? 0 : playable[_random.nextInt(playable.length)];
  }

  @override
  Future<void> playNow(List<PlayableSong> songs) => _serial(() async {
        if (songs.isEmpty) {
          throw PlaybackException(
            ErrorCodes.queueEmpty,
            'There are no songs to play.',
          );
        }
        final added = _queue.add(songs, playNext: true);
        _queue.jumpTo(added.first.id);
        await _startEntry(added.first, autoplay: true);
      });

  /// Checks the link and builds the queue entry. The network check can take
  /// seconds, so it runs outside the command queue: other commands (pause,
  /// volume) stay responsive meanwhile.
  Future<PlayableSong> _prepareStream(String url, String? title, String? artist,
      String? album, String? licenseUrl, String? imageUrl) async {
    final check = validateAudioUrl(url);
    if (!check.isValid) {
      throw PlaybackException(ErrorCodes.invalidUrl, check.error!);
    }
    final uri = check.uri!;
    await _urlChecker.check(uri);

    String clean(String? v, String fallback) =>
        (v != null && v.trim().isNotEmpty) ? v.trim() : fallback;
    return PlayableSong.stream(
      url: uri.toString(),
      title: clean(title, titleFromUrl(uri)),
      artist: clean(artist, 'Internet'),
      album: clean(album, 'Web audio'),
      licenseUrl: licenseUrl,
      imageUrl: imageUrl,
    );
  }

  @override
  Future<void> playUrl(String url,
      {String? title,
      String? artist,
      String? album,
      String? licenseUrl,
      String? imageUrl}) async {
    final song = await _prepareStream(url, title, artist, album, licenseUrl, imageUrl);
    return _serial(() async {
      _queue.replace([song]);
      await _startEntry(_queue.current!, autoplay: true);
    });
  }

  @override
  Future<void> enqueueUrl(String url,
      {String? title,
      String? artist,
      String? album,
      String? licenseUrl,
      String? imageUrl}) async {
    final song = await _prepareStream(url, title, artist, album, licenseUrl, imageUrl);
    return _serial(() async {
      _queue.add([song]);
      // Show it as current if nothing was, so Play knows where to start.
      _queue.current ?? _queue.advance(auto: false);
      _emit();
    });
  }

  @override
  Future<void> enqueue(List<PlayableSong> songs, {bool playNext = false}) =>
      _serial(() async {
        if (songs.isEmpty) return;
        _queue.add(songs, playNext: playNext);
        // Show the first queued song as current so Play knows where to start.
        _queue.current ?? _queue.advance(auto: false);
        _emit();
      });

  @override
  Future<void> removeQueueItem(int queueItemId) => _serial(() async {
        final r = _queue.remove(queueItemId);
        if (!r.removed) {
          throw PlaybackException(ErrorCodes.invalidAction, 'That queue item no longer exists.');
        }
        if (r.wasCurrent) {
          final next = _queue.current;
          if (next != null) {
            try {
              await _startEntry(next, autoplay: _playing);
            } on PlaybackException {
              // Reported through state; the removal itself succeeded.
            }
          } else {
            await _backend.pause();
            _loadedEntryId = null;
            _playing = false;
            _positionSeconds = 0;
            _durationSeconds = 0;
          }
        }
        _emit();
      });

  @override
  Future<void> moveQueueItem(int queueItemId, int newIndex) => _serial(() async {
        if (!_queue.move(queueItemId, newIndex)) {
          throw PlaybackException(ErrorCodes.invalidAction, 'That queue item no longer exists.');
        }
        _emit();
      });

  @override
  Future<void> clearQueue() => _serial(() async {
        _queue.clear();
        await _backend.pause();
        _loadedEntryId = null;
        _playing = false;
        _positionSeconds = 0;
        _durationSeconds = 0;
        _emit();
      });

  @override
  Future<void> playQueueItem(int queueItemId) => _serial(() async {
        if (!_queue.jumpTo(queueItemId)) {
          throw PlaybackException(ErrorCodes.invalidAction, 'That queue item no longer exists.');
        }
        await _startEntry(_queue.current!, autoplay: true);
      });

  @override
  Future<void> setRepeatMode(RepeatMode mode) => _serial(() async {
        _queue.setRepeat(mode);
        _emit();
      });

  @override
  Future<void> setShuffle(bool enabled) => _serial(() async {
        _queue.setShuffle(enabled);
        _emit();
      });

  @override
  QueueSnapshot queueSnapshot() {
    final currentId = _queue.current?.id;
    return QueueSnapshot(
      items: [
        for (final e in _queue.entries)
          RemoteQueueItem(
            queueItemId: e.id,
            isCurrent: e.id == currentId,
            song: RemoteSong(
              id: e.song.id,
              title: e.song.title,
              artist: e.song.artist,
              album: e.song.album,
              durationSeconds: e.song.durationSeconds,
              trackNumber: e.song.trackNumber,
              available: e.song.isUrl || _fileExists(e.song.filePath!),
            ),
          ),
      ],
      currentIndex: _queue.currentIndex,
      revision: _queue.revision,
      shuffle: _queue.shuffle,
      repeat: _queue.repeat,
    );
  }

  @override
  Future<void> dispose() async {
    if (_saveTimer != null || _playing) await _saveQueue(); // keep the latest changes
    _disposed = true;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _backend.dispose();
    await _controller.close();
  }
}
