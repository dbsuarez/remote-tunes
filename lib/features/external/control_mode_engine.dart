import 'dart:async';

import '../../core/models/enums.dart';
import '../../core/protocol/library_models.dart';
import '../../core/protocol/protocol.dart';
import '../player/playback_engine.dart';
import '../player/queue/playable_song.dart';
import '../player/queue_aware_engine.dart';
import 'external_app_engine.dart';

/// An engine that can switch what it controls (docs/13_PHASE_5).
abstract class ControlModeCapable {
  ControlMode get controlMode;
  Future<void> setControlMode(ControlMode mode);
}

/// The Player's engine: RemoteTunes' own player by default, or — when External
/// App Control is turned on — another music app on this phone.
///
/// Playback commands go to whichever is active. Queue, library and internet
/// links only exist for RemoteTunes' own player, so they are refused (with a
/// plain explanation) while another app is being controlled. Switching pauses
/// the side being left, so two apps never play at once.
class ControlModeEngine implements QueueAwareEngine, ControlModeCapable {
  ControlModeEngine({required QueueAwareEngine local, ExternalAppEngine? external})
      : _local = local,
        _external = external {
    _subs.add(_local.states.listen((s) {
      if (_mode == ControlMode.local) _emit(s);
    }));
    final ext = _external;
    if (ext != null) {
      _subs.add(ext.states.listen((s) {
        if (_mode == ControlMode.external) _emit(s);
      }));
    }
  }

  final QueueAwareEngine _local;
  final ExternalAppEngine? _external;
  final List<StreamSubscription<PlaybackState>> _subs = [];
  final StreamController<PlaybackState> _controller =
      StreamController<PlaybackState>.broadcast();
  ControlMode _mode = ControlMode.local;

  /// Whether External App Control is turned on (the user opted in).
  bool get externalAvailable => _external != null;

  ExternalAppEngine? get external => _external;
  QueueAwareEngine get local => _local;

  @override
  ControlMode get controlMode => _mode;

  PlaybackEngine get _active => _mode == ControlMode.external ? _external! : _local;

  // -------------------------------------------------------------------- state

  @override
  PlaybackState get state => _withFlags(_active.state);

  PlaybackState _withFlags(PlaybackState s) =>
      externalAvailable ? s.copyWith(externalEnabled: true) : s;

  @override
  Stream<PlaybackState> get states => _controller.stream;

  void _emit(PlaybackState s) {
    if (!_controller.isClosed) _controller.add(_withFlags(s));
  }

  // ---------------------------------------------------------------- switching

  @override
  Future<void> setControlMode(ControlMode mode) async {
    if (mode == _mode) return;
    final ext = _external;
    if (mode == ControlMode.external) {
      if (ext == null) {
        throw PlaybackException(
          ErrorCodes.permissionDenied,
          "External App Control is turned off on the Player. Turn it on in "
          "the Player's Settings first.",
        );
      }
      // Never let two apps play at once.
      try {
        await _local.pause();
      } on PlaybackException {
        // Nothing was playing.
      }
      await ext.activate(); // throws if Notification access is missing
      _mode = ControlMode.external;
    } else {
      await ext?.deactivate(); // pauses the other app
      _mode = ControlMode.local;
    }
    _emit(_active.state);
  }

  PlaybackException _unavailable() => PlaybackException(
        ErrorCodes.invalidAction,
        'This is not available while controlling '
        '${_external?.appName.isNotEmpty == true ? _external!.appName : 'another app'}. '
        'Switch back to RemoteTunes first.',
      );

  bool get _isExternal => _mode == ControlMode.external;

  // ----------------------------------------------------- transport (delegated)

  @override
  Future<void> play() => _active.play();
  @override
  Future<void> pause() => _active.pause();
  @override
  Future<void> toggle() => _active.toggle();
  @override
  Future<void> next() => _active.next();
  @override
  Future<void> previous() => _active.previous();
  @override
  Future<void> stop() => _active.stop();
  @override
  Future<void> seek(int positionSeconds) => _active.seek(positionSeconds);
  @override
  Future<void> setVolume(double volume) => _active.setVolume(volume);

  // ------------------------------------------- queue / library (own player only)

  @override
  Future<void> playSongs(List<PlayableSong> songs, {int startIndex = 0}) =>
      _isExternal ? Future.error(_unavailable()) : _local.playSongs(songs, startIndex: startIndex);

  @override
  Future<void> playUrl(String url, {String? title}) =>
      _isExternal ? Future.error(_unavailable()) : _local.playUrl(url, title: title);

  @override
  Future<void> enqueue(List<PlayableSong> songs, {bool playNext = false}) =>
      _isExternal ? Future.error(_unavailable()) : _local.enqueue(songs, playNext: playNext);

  @override
  Future<void> removeQueueItem(int queueItemId) =>
      _isExternal ? Future.error(_unavailable()) : _local.removeQueueItem(queueItemId);

  @override
  Future<void> moveQueueItem(int queueItemId, int newIndex) => _isExternal
      ? Future.error(_unavailable())
      : _local.moveQueueItem(queueItemId, newIndex);

  @override
  Future<void> clearQueue() =>
      _isExternal ? Future.error(_unavailable()) : _local.clearQueue();

  @override
  Future<void> playQueueItem(int queueItemId) =>
      _isExternal ? Future.error(_unavailable()) : _local.playQueueItem(queueItemId);

  @override
  Future<void> setRepeatMode(RepeatMode mode) =>
      _isExternal ? Future.error(_unavailable()) : _local.setRepeatMode(mode);

  @override
  Future<void> setShuffle(bool enabled) =>
      _isExternal ? Future.error(_unavailable()) : _local.setShuffle(enabled);

  @override
  QueueSnapshot queueSnapshot() =>
      _isExternal ? const QueueSnapshot() : _local.queueSnapshot();

  @override
  Future<void> dispose() async {
    for (final s in _subs) {
      await s.cancel();
    }
    _subs.clear();
    await _external?.dispose();
    await _local.dispose();
    await _controller.close();
  }
}
