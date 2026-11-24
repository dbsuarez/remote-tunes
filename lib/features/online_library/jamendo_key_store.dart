import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'jamendo_api.dart';

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
  PrefsJamendoKeyStore([Future<SharedPreferences>? prefs])
      : _prefs = prefs ?? SharedPreferences.getInstance();

  final Future<SharedPreferences> _prefs;
  static const _key = 'rt.jamendo_client_id';

  @override
  Future<String?> load() async {
    try {
      final v = (await _prefs).getString(_key)?.trim();
      return v == null || v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> save(String clientId) async =>
      (await _prefs).setString(_key, clientId.trim());

  @override
  Future<void> clear() async => (await _prefs).remove(_key);
}

final jamendoKeyStoreProvider =
    Provider<JamendoKeyStore>((ref) => PrefsJamendoKeyStore());

final jamendoApiProvider = Provider<JamendoApi>((ref) {
  final api = JamendoApi();
  ref.onDispose(api.close);
  return api;
});
