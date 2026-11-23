import 'dart:async';
import 'dart:io';

import '../../core/models/enums.dart';
import '../../core/protocol/library_models.dart';
import '../../core/protocol/protocol.dart';
import '../../core/url_validation.dart';
import 'audio/audio_backend.dart';
import 'playback_engine.dart';
import 'queue/playable_song.dart';
import 'queue/queue_controller.dart';
import 'queue_aware_engine.dart';
import 'url_checker.dart';

/// The real Player engine: a [QueueController] driving an [AudioBackend].
///
/// All public commands run one at a time, so a burst of taps from a Controller
/// (or the notification) can never interleave half-finished track changes.
class QueuePlaybackEngine implements QueueAwareEngine {
  QueuePlaybackEngine({
    required AudioBackend backend,
    QueueController? queue,
    double initialVolume = 0.8,
    bool Function(String path)? fileExists,
    UrlChecker? urlChecker,
    this.onSongStarted,
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
    unawaited(_backend.setVolume(_volume));
  }

  final AudioBackend _backend;

  /// Called with the library id when a library song starts playing (used for
  /// "recently played").
  final void Function(int songId)? onSongStarted;
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
  bool _disposed = false;

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
    );
  }

  @override
  Stream<PlaybackState> get states => _controller.stream;

  void _emit() {
    if (!_disposed && !_controller.isClosed) _controller.add(state);
  }

  void _onPosition(Duration d) {
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
          final duration = song.isUrl
              ? await _backend.loadUrl(song.url!)
              : await _backend.load(path!);
          _loadedEntryId = current.id;
          _positionSeconds = 0;
          _durationSeconds =
              song.durationSeconds > 0 ? song.durationSeconds : (duration?.inSeconds ?? 0);
          _error = '';
          _loading = false;
          if (_speed != 1.0) await _backend.setSpeed(_speed);
          if (autoplay) {
            await _backend.play();
            _playing = true;
            final id = song.libraryId;
            if (id != null) onSongStarted?.call(id);
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
        await _backend.setVolume(volume);
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
        _emit();
      });

  Future<void> _onCompleted() async {
    final next = _queue.advance(auto: true);
    if (next == null) {
      // End of the queue: rewind and stop, staying on the last track.
      await _backend.pause();
      await _backend.seek(Duration.zero);
      _playing = false;
      _positionSeconds = 0;
      _emit();
      return;
    }
    try {
      if (next.id == _loadedEntryId) {
        // Repeat-one: replay the loaded track.
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

  @override
  Future<void> playSongs(List<PlayableSong> songs, {int startIndex = 0}) =>
      _serial(() async {
        if (songs.isEmpty) {
          throw PlaybackException(
            ErrorCodes.queueEmpty,
            'There are no songs to play.',
          );
        }
        _queue.replace(songs, startIndex: startIndex);
        await _startEntry(_queue.current!, autoplay: true);
      });

  @override
  Future<void> playUrl(String url, {String? title}) async {
    final check = validateAudioUrl(url);
    if (!check.isValid) {
      throw PlaybackException(ErrorCodes.invalidUrl, check.error!);
    }
    final uri = check.uri!;
    // The network check can take seconds, so it runs outside the command
    // queue: other commands (pause, volume) stay responsive meanwhile.
    await _urlChecker.check(uri);

    final name = (title != null && title.trim().isNotEmpty)
        ? title.trim()
        : titleFromUrl(uri);
    return _serial(() async {
      _queue.replace([PlayableSong.stream(url: uri.toString(), title: name)]);
      await _startEntry(_queue.current!, autoplay: true);
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
    _disposed = true;
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _backend.dispose();
    await _controller.close();
  }
}
