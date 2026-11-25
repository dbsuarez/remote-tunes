import '../../../data/repositories/settings_repository.dart';
import 'equalizer_controller.dart';

/// Keeps the equalizer settings in the app's settings table.
class SettingsEqStore implements EqStore {
  SettingsEqStore(this._repo);

  final SettingsRepository _repo;

  @override
  Future<String?> read(String key) => _repo.readValue(key);

  @override
  Future<void> write(String key, String value) => _repo.writeValue(key, value);

  @override
  Future<void> remove(String key) => _repo.removeValue(key);
}
