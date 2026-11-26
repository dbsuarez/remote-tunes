/// Importing a folder of sounds: working out which file belongs to which sound, by its name.
library;

import 'ambience_controller.dart' show ambienceExtensions;
import 'ambience_models.dart';

/// One file and where it should go.
class AmbienceImportRow {
  AmbienceImportRow({required this.path, required this.fileName, required this.newName, this.target = newSound});

  /// Make a sound of the owner's own for it.
  static const newSound = '+new';

  /// Leave it out.
  static const skip = '+skip';

  final String path;
  final String fileName;

  /// The name it gets as a new sound.
  final String newName;

  /// A sound's id, [newSound] or [skip].
  String target;
}

/// The sounds a file can be given to: all but the built-in noises.
List<AmbienceSound> importTargets(List<AmbienceSound> sounds) {
  final noise = {for (final s in ambienceCatalog) if (s.available) s.id};
  return [for (final s in sounds) if (!noise.contains(s.id)) s];
}

List<String> _words(String text) => text.toLowerCase().split(RegExp(r'[^a-z0-9]+')).where((w) => w.isNotEmpty).toList();

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
    // Pack files often carry the pack's name first: what follows the last underscore says what it is.
    if (name.length > 30 && name.contains('_') && name.split('_').last.trim().length >= 3) name = name.split('_').last.trim();
    name = name.replaceAll('_', ' ').trim();
    rows.add(AmbienceImportRow(path: path, fileName: file, newName: name.length > 30 ? name.substring(0, 30).trim() : name));
  }

  final targets = importTargets(sounds)..sort((a, b) => _words(b.name).length.compareTo(_words(a.name).length));
  final taken = <String>{};
  void give(bool Function(AmbienceImportRow row, AmbienceSound sound) matches) {
    for (final sound in targets) {
      if (taken.contains(sound.id)) continue;
      for (final row in rows) {
        if (row.target == AmbienceImportRow.newSound && matches(row, sound)) {
          row.target = sound.id;
          taken.add(sound.id);
          break;
        }
      }
    }
  }

  String bare(String file) => _words(file.substring(0, file.lastIndexOf('.'))).join(' ');
  give((row, sound) => bare(row.fileName) == _words(sound.name).join(' '));
  give((row, sound) {
    final have = _words(bare(row.fileName)).toSet();
    return _words(sound.name).every(have.contains);
  });
  // A new sound named like one of the owner's own would be a second copy: it replaces that one.
  give((row, sound) => sound.category == ambienceOwnCategory && sound.name.toLowerCase() == row.newName.toLowerCase());
  return rows;
}
