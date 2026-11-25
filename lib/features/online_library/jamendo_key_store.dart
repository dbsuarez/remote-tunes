import 'jamendo_home.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'jamendo_api.dart';
import 'jamendo_defaults.dart';

/// Where the user's own Jamendo client ID is kept: on this device only. It is
/// never put in the repository, never sent to the Player and never uploaded
/// anywhere except to Jamendo itself when searching.
abstract class JamendoKeyStore {
  Future<String?> load();
  Future<void> save(String clientId);
  Future<void> clear();

  /// A plain-language problem with [input], or null if it looks like a client
  /// ID (letters and digits only).
  static String? problem(String input) {
    final t = input.trim();
    if (t.isEmpty) return 'Paste your Jamendo client ID.';
    if (!RegExp(r'^[A-Za-z0-9]{4,40}$').hasMatch(t)) {
      return 'A client ID is only letters and numbers, with no spaces.';
    }
    return null;
  }
}

class PrefsJamendoKeyStore implements JamendoKeyStore {
  PrefsJamendoKeyStore([Future<SharedPreferences>? prefs, String? defaultId])
      : _prefs = prefs ?? SharedPreferences.getInstance(),
        _default = defaultId ?? JamendoDefaults.clientId;

  final Future<SharedPreferences> _prefs;

  /// The ID baked into this build, used when the user has not saved their own.
  final String _default;
  static const _key = 'rt.jamendo_client_id';

  @override
  Future<String?> load() async {
    String? saved;
    try {
      final v = (await _prefs).getString(_key)?.trim();
      saved = v == null || v.isEmpty ? null : v;
    } catch (_) {
      saved = null;
    }
    // The user's own ID wins; otherwise the one built into this app, if any.
    if (saved != null) return saved;
    final built = _default.trim();
    return JamendoKeyStore.problem(built) == null ? built : null;
  }

  @override
  Future<void> save(String clientId) async =>
      (await _prefs).setString(_key, clientId.trim());

  @override
  Future<void> clear() async => (await _prefs).remove(_key);
}

final jamendoKeyStoreProvider =
    Provider<JamendoKeyStore>((ref) => PrefsJamendoKeyStore());

/// The home screen's shelves, kept while the app runs.
final jamendoHomeProvider = Provider<JamendoHome>((ref) {
  final home = JamendoHome();
  ref.onDispose(home.dispose);
  return home;
});

final jamendoApiProvider = Provider<JamendoApi>((ref) {
  final api = JamendoApi();
  ref.onDispose(api.close);
  return api;
});
