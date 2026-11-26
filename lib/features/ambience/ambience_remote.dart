import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/protocol/protocol.dart';
import '../controller/controller_client.dart';
import 'ambience_models.dart';

/// The other phone's ambience, as a Controller sees it: asked for every couple of seconds while the
/// screen is open, and changed by commands.
class RemoteAmbience extends ChangeNotifier implements AmbienceControls {
  RemoteAmbience(this._client, {this.every = const Duration(seconds: 2)});

  final ControllerClient _client;
  final Duration every;
  AmbienceState _state = const AmbienceState();
  Timer? _poll;
  int _asked = 0;
  int _shown = 0;
  bool _gone = false;

  @override
  AmbienceState get state => _state;

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _poll ??= Timer.periodic(every, (_) => unawaited(refresh().catchError((Object _) {})));
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) {
      _poll?.cancel();
      _poll = null;
    }
  }

  /// Sends one request; the answer is the Player's ambience as it now is.
  Future<Map<String, dynamic>> _ask(String action, [Map<String, dynamic> params = const {}]) async {
    final number = ++_asked;
    final reply = await _client.sendCommandForResult(action, params);
    // An answer that arrives after a newer one is old news.
    if (!_gone && number > _shown && reply['state'] != null) {
      _shown = number;
      _state = AmbienceState.fromJson(reply['state']);
      notifyListeners();
    }
    return reply;
  }

  @override
  Future<void> refresh() async {
    try {
      await _ask(RemoteActions.getAmbience);
    } catch (e) {
      // With nothing to show yet, say why (for example an older app on the Player).
      if (!_gone && _state.sounds.isEmpty) {
        _state = AmbienceState(error: '$e');
        notifyListeners();
      }
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _do(String op, [Map<String, dynamic> params = const {}]) =>
      _ask(RemoteActions.ambience, {'op': op, ...params});

  @override
  Future<void> setActive(String soundId, bool on) => _do('toggle', {'id': soundId, 'on': on});
  @override
  Future<void> setVolume(String soundId, double volume) => _do('volume', {'id': soundId, 'volume': volume});
  @override
  Future<void> setMaster(double volume) => _do('master', {'volume': volume});
  @override
  Future<void> play() => _do('play');
  @override
  Future<void> pause() => _do('pause');
  @override
  Future<void> stop() => _do('stop');
  @override
  Future<void> setTimer(int? minutes) => _do('timer', {'minutes': minutes ?? 0});
  @override
  Future<List<String>> startMix(String mixId) async {
    final reply = await _do('mix', {'id': mixId});
    final missing = reply['missing'];
    return missing is List ? [for (final m in missing) '$m'] : const [];
  }

  @override
  Future<void> saveMix(String name) => _do('saveMix', {'name': name});
  @override
  Future<void> deleteMix(String mixId) => _do('deleteMix', {'id': mixId});

  @override
  void dispose() {
    _gone = true;
    _poll?.cancel();
    super.dispose();
  }
}
