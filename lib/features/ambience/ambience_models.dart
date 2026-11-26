/// Ambience Mode: calming sounds layered together. These are plain data, shared by the phone that plays
/// and the phone that controls it.
library;

import 'package:flutter/foundation.dart';

/// A sound that can be layered. It can be played once it has audio: built-in noise always has, the
/// others after a file is added on the playing phone.
class AmbienceSound {
  const AmbienceSound({required this.id, required this.name, required this.category, this.available = false, this.icon});

  final String id;
  final String name;
  final String category;
  final bool available;

  /// The icon the owner chose (a name from the icon library), or null for the usual one.
  final String? icon;

  AmbienceSound copyWith({bool? available, String? icon}) => AmbienceSound(
      id: id, name: name, category: category, available: available ?? this.available, icon: icon ?? this.icon);

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'category': category, 'available': available, if (icon != null) 'icon': icon};

  static AmbienceSound? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'], category = j['category'];
    if (id is! String || id.isEmpty || name is! String || category is! String) return null;
    return AmbienceSound(
        id: id,
        name: name,
        category: category,
        available: j['available'] == true,
        icon: j['icon'] is String ? j['icon'] as String : null);
  }
}

/// Sounds and how loud each is, under a name.
class AmbienceMix {
  const AmbienceMix({required this.id, required this.name, required this.layers, this.builtIn = false});

  final String id;
  final String name;

  /// Sound id to its volume, 0 to 1.
  final Map<String, double> layers;

  /// A preset that came with the app (it cannot be deleted).
  final bool builtIn;

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'layers': layers, if (builtIn) 'builtIn': true};

  static AmbienceMix? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'];
    if (id is! String || id.isEmpty || name is! String || name.isEmpty) return null;
    return AmbienceMix(id: id, name: name, layers: readLayers(j['layers']), builtIn: j['builtIn'] == true);
  }
}

/// A map of sound ids to volumes read from JSON (anything wrong is skipped).
Map<String, double> readLayers(Object? j) => {
      if (j is Map)
        for (final e in j.entries)
          if (e.key is String && e.value is num) e.key as String: (e.value as num).toDouble().clamp(0.0, 1.0),
    };

/// Everything the Ambience screen shows.
class AmbienceState {
  const AmbienceState({
    this.sounds = const [],
    this.mixes = const [],
    this.active = const {},
    this.playing = false,
    this.master = 0.7,
    this.maxVolume = 1,
    this.timerMinutes,
    this.secondsLeft,
    this.mixName,
    this.error,
  });

  final List<AmbienceSound> sounds;
  final List<AmbienceMix> mixes;

  /// The sounds switched on, with their volumes.
  final Map<String, double> active;
  final bool playing;

  /// The volume of everything together, 0 to 1.
  final double master;

  /// The most [master] may be (set on the playing phone).
  final double maxVolume;

  /// The sleep timer chosen, or null for none.
  final int? timerMinutes;

  /// What is left of the timer.
  final int? secondsLeft;

  /// The mix the switched-on sounds came from, until they are changed.
  final String? mixName;

  /// Why something could not be done, if anything.
  final String? error;

  AmbienceSound? sound(String id) {
    for (final s in sounds) {
      if (s.id == id) return s;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
        'sounds': [for (final s in sounds) s.toJson()],
        'mixes': [for (final m in mixes) m.toJson()],
        'active': active,
        'playing': playing,
        'master': master,
        'max': maxVolume,
        if (timerMinutes != null) 'timer': timerMinutes,
        if (secondsLeft != null) 'left': secondsLeft,
        if (mixName != null) 'mix': mixName,
        if (error != null) 'error': error,
      };

  static AmbienceState fromJson(Object? j) {
    if (j is! Map) return const AmbienceState();
    int? whole(Object? v) => v is num ? v.toInt() : null;
    double part(Object? v, double otherwise) => v is num ? v.toDouble().clamp(0.0, 1.0) : otherwise;
    final sounds = j['sounds'], mixes = j['mixes'];
    return AmbienceState(
      sounds: [
        if (sounds is List)
          for (final e in sounds)
            if (AmbienceSound.fromJson(e) case final s?) s,
      ],
      mixes: [
        if (mixes is List)
          for (final e in mixes)
            if (AmbienceMix.fromJson(e) case final m?) m,
      ],
      active: readLayers(j['active']),
      playing: j['playing'] == true,
      master: part(j['master'], 0.7),
      maxVolume: part(j['max'], 1),
      timerMinutes: whole(j['timer']),
      secondsLeft: whole(j['left']),
      mixName: j['mix'] is String ? j['mix'] as String : null,
      error: j['error'] is String ? j['error'] as String : null,
    );
  }
}

/// What the Ambience screen can do, on the playing phone or from the other one. Listen to it to hear of
/// changes.
abstract class AmbienceControls implements Listenable {
  AmbienceState get state;

  /// Reads the state as it is now.
  Future<void> refresh();

  /// Switches a sound on (and plays) or off.
  Future<void> setActive(String soundId, bool on);
  Future<void> setVolume(String soundId, double volume);
  Future<void> setMaster(double volume);
  Future<void> play();
  Future<void> pause();

  /// Stops everything. What was switched on stays chosen for the next [play].
  Future<void> stop();

  /// The sleep timer; null for none.
  Future<void> setTimer(int? minutes);

  /// Plays a mix. Gives the names of its sounds that have no audio yet.
  Future<List<String>> startMix(String mixId);

  /// Saves the switched-on sounds under [name] (an own mix of that name is replaced).
  Future<void> saveMix(String name);
  Future<void> deleteMix(String mixId);
}

/// The timer choices, in minutes.
const ambienceTimers = [15, 30, 45, 60, 120];

/// The sounds that come with a place for a file, and the noises the app makes itself.
const ambienceCatalog = [
  AmbienceSound(id: 'rain', name: 'Rain', category: 'Rain'),
  AmbienceSound(id: 'light-rain', name: 'Light Rain', category: 'Rain'),
  AmbienceSound(id: 'thunder', name: 'Thunder', category: 'Rain'),
  AmbienceSound(id: 'distant-thunder', name: 'Distant Thunder', category: 'Rain'),
  AmbienceSound(id: 'ocean', name: 'Ocean Waves', category: 'Water'),
  AmbienceSound(id: 'seagulls', name: 'Seagulls', category: 'Water'),
  AmbienceSound(id: 'stream', name: 'Stream', category: 'Water'),
  AmbienceSound(id: 'crickets', name: 'Crickets', category: 'Night'),
  AmbienceSound(id: 'owls', name: 'Owls', category: 'Night'),
  AmbienceSound(id: 'frogs', name: 'Frogs', category: 'Night'),
  AmbienceSound(id: 'campfire', name: 'Campfire', category: 'Wind and Fire'),
  AmbienceSound(id: 'wind', name: 'Wind', category: 'Wind and Fire'),
  AmbienceSound(id: 'birds', name: 'Birds', category: 'Nature'),
  AmbienceSound(id: 'white-noise', name: 'White Noise', category: 'Noise', available: true),
  AmbienceSound(id: 'pink-noise', name: 'Pink Noise', category: 'Noise', available: true),
  AmbienceSound(id: 'brown-noise', name: 'Brown Noise', category: 'Noise', available: true),
];

/// The category of sounds the owner names themselves.
const ambienceOwnCategory = 'My sounds';

/// The category of the owner's whole soundscapes (a place with its sounds already in it).
const ambienceEnvironmentCategory = 'Environment';

/// Whether a sound was made by the owner (so it can be deleted altogether).
bool isOwnAmbienceSound(AmbienceSound s) => s.category == ambienceOwnCategory || s.category == ambienceEnvironmentCategory;

const ambiencePresets = [
  AmbienceMix(id: 'rainy-night', name: 'Rainy Night', builtIn: true, layers: {'rain': 0.6, 'distant-thunder': 0.25}),
  AmbienceMix(id: 'campfire', name: 'Campfire', builtIn: true, layers: {'campfire': 0.7, 'wind': 0.3}),
  AmbienceMix(id: 'ocean-calm', name: 'Ocean Calm', builtIn: true, layers: {'ocean': 0.7, 'birds': 0.2}),
  AmbienceMix(id: 'forest-morning', name: 'Forest Morning', builtIn: true, layers: {'birds': 0.5, 'stream': 0.3}),
  AmbienceMix(id: 'study-focus', name: 'Study Focus', builtIn: true, layers: {'white-noise': 0.5, 'light-rain': 0.3}),
  AmbienceMix(id: 'sleep', name: 'Sleep', builtIn: true, layers: {'white-noise': 0.45, 'rain': 0.35}),
];
