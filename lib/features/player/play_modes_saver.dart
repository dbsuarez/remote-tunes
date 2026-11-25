import 'dart:async';

import '../../core/models/enums.dart';
import '../../data/repositories/settings_repository.dart';
import 'queue_aware_engine.dart';

/// Saves shuffle and repeat whenever they change, so the player starts with them
/// as they were left.
class PlayModesSaver {
  PlayModesSaver({
    required this.engine,
    required this.store,
    required bool shuffle,
    required RepeatMode repeat,
  })  : _shuffle = shuffle,
        _repeat = repeat;

  final QueueAwareEngine engine;
  final SettingsRepository store;

  bool _shuffle;
  RepeatMode _repeat;
  StreamSubscription<dynamic>? _sub;

  void start() {
    _sub ??= engine.states.listen((s) {
      if (s.shuffleEnabled != _shuffle) {
        _shuffle = s.shuffleEnabled;
        unawaited(store.setShuffleEnabled(_shuffle).catchError((Object _) {}));
      }
      if (s.repeatMode != _repeat) {
        _repeat = s.repeatMode;
        unawaited(store.setRepeatMode(_repeat).catchError((Object _) {}));
      }
    });
  }

  void dispose() {
    _sub?.cancel();
    _sub = null;
  }
}
