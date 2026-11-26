/// Importing a folder of sounds: working out which file belongs to which sound, by its name.
library;

import 'ambience_controller.dart' show ambienceExtensions;
import 'ambience_models.dart';

/// One file and where it should go.
class AmbienceImportRow {
  AmbienceImportRow({required this.path, required this.fileName, required this.newName, this.target = newSound});

  /// Make a sound of the owner's own for it.
  static const newSound = '+new';

  /// Make it one of the owner's environments.
  static const newEnvironment = '+env';

  /// Leave it out.
  static const skip = '+skip';

  final String path;
  final String fileName;

  /// The name it gets as a new sound.
  final String newName;

  /// A sound's id, [newSound], [newEnvironment] or [skip].
  String target;
}

/// The sounds a file can be given to: all but the built-in noises.
List<AmbienceSound> importTargets(List<AmbienceSound> sounds) {
  final noise = {for (final s in ambienceCatalog) if (s.available) s.id};
  return [for (final s in sounds) if (!noise.contains(s.id)) s];
}

List<String> _words(String text) => text.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty).toList();

/// Words in a file name that say it is a whole environment (some packs misspell it).
const _environmentWords = {'env', 'environment', 'environments', 'enviroment', 'enviroments'};

/// The name of an environment file: what follows the word that marks it ("water_env_peaceful_lake" is
/// "Peaceful Lake"). Null if the name has no such word.
String? _environmentName(String bareName) {
  final parts = bareName.split(RegExp(r'[_\s-]+')).where((w) => w.isNotEmpty).toList();
  final at = parts.indexWhere((w) => _environmentWords.contains(w.toLowerCase()));
  if (at < 0) return null;
  final rest = parts.sublist(at + 1);
  final named = rest.isEmpty ? parts.sublist(0, at) : rest;
  return [for (final w in named) w[0].toUpperCase() + w.substring(1)].join(' ');
}

/// The audio files among [paths], each matched to a sound by its name. A file named like the sound wins
/// ("Light Rain.wav"); otherwise one whose name holds all the sound's words ("weather_light_rain"), the
/// longest sound name first. Two files never get the same sound; the rest become new sounds.
List<AmbienceImportRow> planImport(List<String> paths, List<AmbienceSound> sounds) {
  final rows = <AmbienceImportRow>[];
  for (final path in paths) {
    final file = path.split(RegExp(r'[\\/]')).last;
    final dot = file.lastIndexOf('.');
    if (dot <= 0 || !ambienceExtensions.contains(file.substring(dot + 1).toLowerCase())) continue;
    var name = file.substring(0, dot).trim();
    final environment = _environmentName(name);
    if (environment != null && environment.isNotEmpty) {
      rows.add(AmbienceImportRow(
        path: path,
        fileName: file,
        newName: environment.length > 30 ? environment.substring(0, 30).trim() : environment,
        target: AmbienceImportRow.newEnvironment,
      ));
      continue;
    }
    // Pack files often carry the pack's name first: what follows the last underscore says what it is.
    if (name.length > 30 && name.contains('_') && name.split('_').last.trim().length >= 3) name = name.split('_').last.trim();
    name = name.replaceAll('_', ' ').trim();
    rows.add(AmbienceImportRow(path: path, fileName: file, newName: name.length > 30 ? name.substring(0, 30).trim() : name));
  }

  final targets = importTargets(sounds);
  // Every name a sound answers to, the longest first: "light rain" must be tried before "rain".
  final names = [
    for (final sound in targets)
      for (final name in [sound.name, ...?ambienceAliases[sound.id]]) (sound: sound, words: _words(name)),
  ]..sort((a, b) => b.words.length.compareTo(a.words.length));
  final taken = <String>{};
  // Environments are whole places: they never fill a single sound's slot.
  void give(AmbienceSound sound, bool Function(AmbienceImportRow row) matches, {String of = AmbienceImportRow.newSound}) {
    if (taken.contains(sound.id)) return;
    for (final row in rows) {
      if (row.target == of && matches(row)) {
        row.target = sound.id;
        taken.add(sound.id);
        return;
      }
    }
  }

  String bare(String file) => _words(file.substring(0, file.lastIndexOf('.'))).join(' ');
  for (final n in names) {
    give(n.sound, (row) => bare(row.fileName) == n.words.join(' '));
  }
  for (final n in names) {
    give(n.sound, (row) => n.words.every(_words(bare(row.fileName)).toSet().contains));
  }
  // A new sound named like one of the owner's own would be a second copy: it replaces that one.
  bool sameName(AmbienceImportRow row, AmbienceSound sound) => sound.name.toLowerCase() == row.newName.toLowerCase();
  for (final sound in targets) {
    if (sound.category == ambienceOwnCategory) give(sound, (row) => sameName(row, sound));
    if (sound.category == ambienceEnvironmentCategory) {
      give(sound, (row) => sameName(row, sound), of: AmbienceImportRow.newEnvironment);
    }
  }
  return rows;
}
