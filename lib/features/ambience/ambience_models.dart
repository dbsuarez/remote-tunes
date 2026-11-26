/// Ambience Mode: calming sounds layered together. These are plain data, shared by the phone that plays
/// and the phone that controls it.
library;

import 'package:flutter/foundation.dart';

/// A sound that can be layered. It can be played once it has audio: built-in noise always has, the
/// others after a file is added on the playing phone.
class AmbienceSound {
  const AmbienceSound(
      {required this.id, required this.name, required this.category, this.available = false, this.icon, this.boost = 1});

  /// The owner's louder (above 1) or softer for this sound.
  final double boost;

  final String id;
  final String name;
  final String category;
  final bool available;

  /// The icon the owner chose (a name from the icon library), or null for the usual one.
  final String? icon;

  AmbienceSound copyWith({bool? available, String? icon, double? boost}) => AmbienceSound(
      id: id,
      name: name,
      category: category,
      available: available ?? this.available,
      icon: icon ?? this.icon,
      boost: boost ?? this.boost);

  Map<String, dynamic> toJson() =>
      {
        'id': id,
        'name': name,
        'category': category,
        'available': available,
        if (icon != null) 'icon': icon,
        if (boost != 1) 'boost': boost,
      };

  static AmbienceSound? fromJson(Object? j) {
    if (j is! Map) return null;
    final id = j['id'], name = j['name'], category = j['category'];
    if (id is! String || id.isEmpty || name is! String || category is! String) return null;
    return AmbienceSound(
        id: id,
        name: name,
        category: category,
        available: j['available'] == true,
        icon: j['icon'] is String ? j['icon'] as String : null,
        boost: j['boost'] is num ? (j['boost'] as num).toDouble() : 1);
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

  Map<String, dynamic> toJson({bool readyOnly = false}) => {
        'sounds': [
          for (final s in sounds)
            if (s.available || !readyOnly) s.toJson(),
        ],
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

/// Starting a mix by itself at a time of day.
class AmbienceSchedule {
  const AmbienceSchedule({this.enabled = false, this.hour = 20, this.minute = 0, this.mixId = 'sleep', this.timerMinutes = 60});

  final bool enabled;
  final int hour;
  final int minute;
  final String mixId;

  /// The sleep timer it starts with; null plays until stopped.
  final int? timerMinutes;

  AmbienceSchedule copyWith({bool? enabled, int? hour, int? minute, String? mixId}) => AmbienceSchedule(
      enabled: enabled ?? this.enabled,
      hour: hour ?? this.hour,
      minute: minute ?? this.minute,
      mixId: mixId ?? this.mixId,
      timerMinutes: timerMinutes);

  AmbienceSchedule withTimer(int? minutes) =>
      AmbienceSchedule(enabled: enabled, hour: hour, minute: minute, mixId: mixId, timerMinutes: minutes);

  Map<String, dynamic> toJson() =>
      {'on': enabled, 'hour': hour, 'minute': minute, 'mix': mixId, if (timerMinutes != null) 'timer': timerMinutes};

  static AmbienceSchedule fromJson(Object? j) {
    if (j is! Map) return const AmbienceSchedule();
    int part(String key, int otherwise, int max) => j[key] is num ? (j[key] as num).toInt().clamp(0, max) : otherwise;
    return AmbienceSchedule(
      enabled: j['on'] == true,
      hour: part('hour', 20, 23),
      minute: part('minute', 0, 59),
      mixId: j['mix'] is String ? j['mix'] as String : 'sleep',
      timerMinutes: j['timer'] is num ? (j['timer'] as num).toInt().clamp(1, 720) : null,
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

/// The sounds that come with a place for a file, and the noises the app makes itself. Ids never change:
/// files and mixes are kept by them.
const ambienceCatalog = [
  AmbienceSound(id: 'rain', name: 'Morning Rain', category: 'Rain'),
  AmbienceSound(id: 'umbrella', name: 'Umbrella', category: 'Rain'),
  AmbienceSound(id: 'thunder', name: 'Thunder', category: 'Rain'),
  AmbienceSound(id: 'light-rain', name: 'Light Rain', category: 'Rain'),
  AmbienceSound(id: 'heavy-rain', name: 'Heavy Rain', category: 'Rain'),
  AmbienceSound(id: 'distant-thunder', name: 'Distant Thunder', category: 'Rain'),
  AmbienceSound(id: 'tent', name: 'Tent', category: 'Rain'),
  AmbienceSound(id: 'window', name: 'Window', category: 'Rain'),
  AmbienceSound(id: 'roof', name: 'Roof', category: 'Rain'),
  AmbienceSound(id: 'urban-rain', name: 'Urban Rain', category: 'Rain'),
  AmbienceSound(id: 'rain-on-leaves', name: 'Rain on Leaves', category: 'Rain'),
  AmbienceSound(id: 'rainforest', name: 'Rainforest', category: 'Rain'),
  AmbienceSound(id: 'calm-waves', name: 'Calm Waves', category: 'Ocean'),
  AmbienceSound(id: 'ocean', name: 'Waves', category: 'Ocean'),
  AmbienceSound(id: 'seagulls', name: 'Seagulls', category: 'Ocean'),
  AmbienceSound(id: 'scuba-diver', name: 'Scuba Diver', category: 'Ocean'),
  AmbienceSound(id: 'dolphins', name: 'Dolphins', category: 'Ocean'),
  AmbienceSound(id: 'sailboat', name: 'Sailboat', category: 'Ocean'),
  AmbienceSound(id: 'whale', name: 'Whale', category: 'Ocean'),
  AmbienceSound(id: 'foghorn', name: 'Foghorn', category: 'Ocean'),
  AmbienceSound(id: 'harbor', name: 'Harbor', category: 'Ocean'),
  AmbienceSound(id: 'rough-ocean', name: 'Rough Ocean', category: 'Ocean'),
  AmbienceSound(id: 'ferry', name: 'Ferry', category: 'Ocean'),
  AmbienceSound(id: 'ship-cabin', name: 'Ship Cabin', category: 'Ocean'),
  AmbienceSound(id: 'river', name: 'River', category: 'Water'),
  AmbienceSound(id: 'stream', name: 'Brook', category: 'Water'),
  AmbienceSound(id: 'creek', name: 'Creek', category: 'Water'),
  AmbienceSound(id: 'waterfall', name: 'Waterfall', category: 'Water'),
  AmbienceSound(id: 'water-drops', name: 'Water Drops', category: 'Water'),
  AmbienceSound(id: 'canoe', name: 'Canoe', category: 'Water'),
  AmbienceSound(id: 'snowmelt', name: 'Snowmelt', category: 'Water'),
  AmbienceSound(id: 'snow', name: 'Snow', category: 'Water'),
  AmbienceSound(id: 'frozen-stream', name: 'Frozen Stream', category: 'Water'),
  AmbienceSound(id: 'wind', name: 'Light Wind', category: 'Wind and Fire'),
  AmbienceSound(id: 'strong-wind', name: 'Strong Wind', category: 'Wind and Fire'),
  AmbienceSound(id: 'mountain', name: 'Mountain', category: 'Wind and Fire'),
  AmbienceSound(id: 'under-the-door', name: 'Under the Door', category: 'Wind and Fire'),
  AmbienceSound(id: 'trees', name: 'Trees', category: 'Wind and Fire'),
  AmbienceSound(id: 'bamboo', name: 'Bamboo', category: 'Wind and Fire'),
  AmbienceSound(id: 'flag', name: 'Flag', category: 'Wind and Fire'),
  AmbienceSound(id: 'dunes', name: 'Dunes', category: 'Wind and Fire'),
  AmbienceSound(id: 'desert', name: 'Desert', category: 'Wind and Fire'),
  AmbienceSound(id: 'oil-stove', name: 'Oil Stove', category: 'Wind and Fire'),
  AmbienceSound(id: 'campfire', name: 'Campfire', category: 'Wind and Fire'),
  AmbienceSound(id: 'fireplace', name: 'Fireplace', category: 'Wind and Fire'),
  AmbienceSound(id: 'crickets', name: 'Crickets', category: 'Night'),
  AmbienceSound(id: 'grasshoppers', name: 'Grasshoppers', category: 'Night'),
  AmbienceSound(id: 'owls', name: 'Owls', category: 'Night'),
  AmbienceSound(id: 'wolves', name: 'Wolves', category: 'Night'),
  AmbienceSound(id: 'loon', name: 'Loon', category: 'Night'),
  AmbienceSound(id: 'frogs', name: 'Frogs', category: 'Night'),
  AmbienceSound(id: 'coyote', name: 'Coyote', category: 'Night'),
  AmbienceSound(id: 'coqui-frog', name: 'Coqui Frog', category: 'Night'),
  AmbienceSound(id: 'whippoorwill', name: 'Whippoorwill', category: 'Night'),
  AmbienceSound(id: 'night-forest', name: 'Night Forest', category: 'Night'),
  AmbienceSound(id: 'train-cabin', name: 'Train Cabin', category: 'Night'),
  AmbienceSound(id: 'jungle', name: 'Jungle', category: 'Night'),
  AmbienceSound(id: 'birds', name: 'Birds', category: 'Countryside'),
  AmbienceSound(id: 'blackbirds', name: 'Blackbirds', category: 'Countryside'),
  AmbienceSound(id: 'nightingale', name: 'Nightingale', category: 'Countryside'),
  AmbienceSound(id: 'swallows', name: 'Swallows', category: 'Countryside'),
  AmbienceSound(id: 'turtledove', name: 'Turtledove', category: 'Countryside'),
  AmbienceSound(id: 'eagle', name: 'Eagle', category: 'Countryside'),
  AmbienceSound(id: 'crows', name: 'Crows', category: 'Countryside'),
  AmbienceSound(id: 'farm', name: 'Farm', category: 'Countryside'),
  AmbienceSound(id: 'cowbells', name: 'Cowbells', category: 'Countryside'),
  AmbienceSound(id: 'sheep', name: 'Sheep', category: 'Countryside'),
  AmbienceSound(id: 'horse', name: 'Horse', category: 'Countryside'),
  AmbienceSound(id: 'ducks', name: 'Ducks', category: 'Countryside'),
  AmbienceSound(id: 'cicadas', name: 'Cicadas', category: 'Countryside'),
  AmbienceSound(id: 'train-horn', name: 'Train Horn', category: 'Countryside'),
  AmbienceSound(id: 'cow', name: 'Cow', category: 'Countryside'),
  AmbienceSound(id: 'musician', name: 'Musician', category: 'City'),
  AmbienceSound(id: 'coffee-shop', name: 'Coffee Shop', category: 'City'),
  AmbienceSound(id: 'fountain', name: 'Fountain', category: 'City'),
  AmbienceSound(id: 'children', name: 'Children', category: 'City'),
  AmbienceSound(id: 'traffic', name: 'Traffic', category: 'City'),
  AmbienceSound(id: 'subway', name: 'Subway', category: 'City'),
  AmbienceSound(id: 'road-work', name: 'Road Work', category: 'City'),
  AmbienceSound(id: 'train-station', name: 'Train Station', category: 'City'),
  AmbienceSound(id: 'market', name: 'Market', category: 'City'),
  AmbienceSound(id: 'fan', name: 'Fan', category: 'Home'),
  AmbienceSound(id: 'air-conditioner', name: 'Air Conditioner', category: 'Home'),
  AmbienceSound(id: 'hairdryer', name: 'Hairdryer', category: 'Home'),
  AmbienceSound(id: 'vacuum-cleaner', name: 'Vacuum Cleaner', category: 'Home'),
  AmbienceSound(id: 'cat-purring', name: 'Cat Purring', category: 'Home'),
  AmbienceSound(id: 'shower', name: 'Shower', category: 'Home'),
  AmbienceSound(id: 'washing-machine', name: 'Washing Machine', category: 'Home'),
  AmbienceSound(id: 'jacuzzi', name: 'Jacuzzi', category: 'Home'),
  AmbienceSound(id: 'fridge', name: 'Fridge', category: 'Home'),
  AmbienceSound(id: 'grandfather-clock', name: 'Grandfather Clock', category: 'Home'),
  AmbienceSound(id: 'gas-stove', name: 'Gas Stove', category: 'Home'),
  AmbienceSound(id: 'heater', name: 'Heater', category: 'Home'),
  AmbienceSound(id: 'aquarium', name: 'Aquarium', category: 'Home'),
  AmbienceSound(id: 'coffee-pot', name: 'Coffee Pot', category: 'Home'),
  AmbienceSound(id: 'pocket-watch', name: 'Pocket Watch', category: 'Home'),
  AmbienceSound(id: 'koi-pond', name: 'Koi Pond', category: 'Zen Garden'),
  AmbienceSound(id: 'tsukubai', name: 'Tsukubai', category: 'Zen Garden'),
  AmbienceSound(id: 'water-flow', name: 'Water Flow', category: 'Zen Garden'),
  AmbienceSound(id: 'broom', name: 'Broom', category: 'Zen Garden'),
  AmbienceSound(id: 'rake', name: 'Rake', category: 'Zen Garden'),
  AmbienceSound(id: 'shishi-odoshi', name: 'Shishi Odoshi', category: 'Zen Garden'),
  AmbienceSound(id: 'tea-ceremony', name: 'Tea Ceremony', category: 'Zen Garden'),
  AmbienceSound(id: 'white-noise', name: 'White Noise', category: 'Noise', available: true),
  AmbienceSound(id: 'pink-noise', name: 'Pink Noise', category: 'Noise', available: true),
  AmbienceSound(id: 'brown-noise', name: 'Brown Noise', category: 'Noise', available: true),
  AmbienceSound(id: 'green-noise', name: 'Green Noise', category: 'Noise', available: true),
  AmbienceSound(id: 'blue-noise', name: 'Blue Noise', category: 'Noise', available: true),
  AmbienceSound(id: 'gray-noise', name: 'Gray Noise', category: 'Noise', available: true),
  AmbienceSound(id: 'piano', name: 'Piano', category: 'Relaxing Music'),
  AmbienceSound(id: 'guitar', name: 'Guitar', category: 'Relaxing Music'),
  AmbienceSound(id: 'violin', name: 'Violin', category: 'Relaxing Music'),
  AmbienceSound(id: 'harp', name: 'Harp', category: 'Relaxing Music'),
  AmbienceSound(id: 'flute', name: 'Flute', category: 'Relaxing Music'),
  AmbienceSound(id: 'sax', name: 'Sax', category: 'Relaxing Music'),
  AmbienceSound(id: 'native-flute', name: 'Native Flute', category: 'Relaxing Music'),
  AmbienceSound(id: 'quiet-time', name: 'Quiet Time', category: 'Relaxing Music'),
  AmbienceSound(id: 'tranquility', name: 'Tranquility', category: 'Relaxing Music'),
  AmbienceSound(id: 'dreamy', name: 'Dreamy', category: 'Relaxing Music'),
  AmbienceSound(id: 'serenity', name: 'Serenity', category: 'Relaxing Music'),
  AmbienceSound(id: 'miracle-tone', name: 'Miracle Tone', category: 'Relaxing Music'),
  AmbienceSound(id: 'bowls', name: 'Bowls', category: 'Traditional'),
  AmbienceSound(id: 'gong', name: 'Gong', category: 'Traditional'),
  AmbienceSound(id: 'bells', name: 'Bells', category: 'Traditional'),
  AmbienceSound(id: 'om', name: 'Om', category: 'Traditional'),
  AmbienceSound(id: 'traditional-flute', name: 'Flute', category: 'Traditional'),
  AmbienceSound(id: 'didgeridoo', name: 'Didgeridoo', category: 'Traditional'),
  AmbienceSound(id: 'chimes', name: 'Chimes', category: 'Traditional'),
  AmbienceSound(id: 'guzheng', name: 'Guzheng', category: 'Traditional'),
  AmbienceSound(id: 'temple', name: 'Temple', category: 'Traditional'),
  AmbienceSound(id: 'sitar', name: 'Sitar', category: 'Traditional'),
  AmbienceSound(id: 'taiko', name: 'Taiko', category: 'Traditional'),
  AmbienceSound(id: 'shamisen', name: 'Shamisen', category: 'Traditional'),
  AmbienceSound(id: 'chalks', name: 'Chalks', category: 'ASMR'),
  AmbienceSound(id: 'paint-brush', name: 'Paint Brush', category: 'ASMR'),
  AmbienceSound(id: 'pencil', name: 'Pencil', category: 'ASMR'),
  AmbienceSound(id: 'brushing-hair', name: 'Brushing Hair', category: 'ASMR'),
  AmbienceSound(id: 'washing-hair', name: 'Washing Hair', category: 'ASMR'),
  AmbienceSound(id: 'voice', name: 'Voice', category: 'ASMR'),
  AmbienceSound(id: 'book', name: 'Book', category: 'ASMR'),
  AmbienceSound(id: 'slime', name: 'Slime', category: 'ASMR'),
  AmbienceSound(id: 'scrubbing', name: 'Scrubbing', category: 'ASMR'),
  AmbienceSound(id: 'steps-in-the-snow', name: 'Steps in the Snow', category: 'ASMR'),
  AmbienceSound(id: 'cycling-on-gravel', name: 'Cycling on Gravel', category: 'ASMR'),
  AmbienceSound(id: 'boiling-water', name: 'Boiling Water', category: 'ASMR'),
  AmbienceSound(id: 'headache-0-5-hz', name: 'Headache 0.5 Hz', category: 'Binaural Beats'),
  AmbienceSound(id: 'insomnia-1-5-hz', name: 'Insomnia 1.5 Hz', category: 'Binaural Beats'),
  AmbienceSound(id: 'relaxation-2-5-hz', name: 'Relaxation 2.5 Hz', category: 'Binaural Beats'),
  AmbienceSound(id: 'anxiety-3-5-hz', name: 'Anxiety 3.5 Hz', category: 'Binaural Beats'),
  AmbienceSound(id: 'meditation-4-5-hz', name: 'Meditation 4.5 Hz', category: 'Binaural Beats'),
  AmbienceSound(id: 'intuition-5-5-hz', name: 'Intuition 5.5 Hz', category: 'Binaural Beats'),
  AmbienceSound(id: 'creativity-7-5-hz', name: 'Creativity 7.5 Hz', category: 'Binaural Beats'),
  AmbienceSound(id: 'energy-8-hz', name: 'Energy 8 Hz', category: 'Binaural Beats'),
  AmbienceSound(id: 'love-10-5-hz', name: 'Love 10.5 Hz', category: 'Binaural Beats'),
];

/// Other names a sound's file may have (what the sound was called before, or the obvious word).
const ambienceAliases = <String, List<String>>{
  'rain': ['Rain'],
  'ocean': ['Ocean Waves'],
  'stream': ['Stream'],
  'wind': ['Wind'],
};

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
  AmbienceMix(id: 'baby-sleep', name: 'Baby Sleep', builtIn: true, layers: {'brown-noise': 0.35, 'rain': 0.25}),
  AmbienceMix(id: 'rainy-sleep', name: 'Rainy Sleep', builtIn: true, layers: {'rain': 0.5, 'thunder': 0.35, 'crickets': 0.4, 'owls': 0.3, 'frogs': 0.3}),
  AmbienceMix(id: 'rain-on-roof', name: 'Rain on the Roof', builtIn: true, layers: {'roof': 0.6, 'light-rain': 0.3}),
  AmbienceMix(id: 'window-rain', name: 'Rain at the Window', builtIn: true, layers: {'window': 0.55, 'distant-thunder': 0.2}),
  AmbienceMix(id: 'rain-in-tent', name: 'Night in the Tent', builtIn: true, layers: {'tent': 0.55, 'crickets': 0.3, 'owls': 0.2}),
  AmbienceMix(id: 'summer-night', name: 'Summer Night', builtIn: true, layers: {'crickets': 0.5, 'frogs': 0.35, 'owls': 0.25}),
  AmbienceMix(id: 'night-forest-walk', name: 'Night Forest', builtIn: true, layers: {'night-forest': 0.55, 'owls': 0.3, 'stream': 0.25}),
  AmbienceMix(id: 'cozy-cabin', name: 'Cozy Cabin', builtIn: true, layers: {'fireplace': 0.55, 'rain': 0.35, 'distant-thunder': 0.2}),
  AmbienceMix(id: 'beach-day', name: 'Beach Day', builtIn: true, layers: {'ocean': 0.6, 'seagulls': 0.25, 'wind': 0.2}),
  AmbienceMix(id: 'deep-sea', name: 'Deep Sea', builtIn: true, layers: {'calm-waves': 0.6, 'whale': 0.35}),
  AmbienceMix(id: 'mountain-stream', name: 'Mountain Stream', builtIn: true, layers: {'stream': 0.6, 'birds': 0.3, 'wind': 0.2}),
  AmbienceMix(id: 'waterfall-rest', name: 'Waterfall', builtIn: true, layers: {'waterfall': 0.55, 'birds': 0.25}),
  AmbienceMix(id: 'rainforest-walk', name: 'Rainforest Walk', builtIn: true, layers: {'rainforest': 0.5, 'waterfall': 0.25, 'birds': 0.3}),
  AmbienceMix(id: 'farm-morning', name: 'Farm Morning', builtIn: true, layers: {'birds': 0.45, 'cow': 0.2, 'sheep': 0.2, 'ducks': 0.2}),
  AmbienceMix(id: 'zen-garden', name: 'Zen Garden', builtIn: true, layers: {'water-flow': 0.5, 'koi-pond': 0.35, 'chimes': 0.2, 'birds': 0.2}),
  AmbienceMix(id: 'cat-nap', name: 'Cat Nap', builtIn: true, layers: {'cat-purring': 0.5, 'fan': 0.3}),
  AmbienceMix(id: 'fan-night', name: 'Fan Night', builtIn: true, layers: {'fan': 0.55, 'brown-noise': 0.25}),
  AmbienceMix(id: 'train-ride', name: 'Train Ride', builtIn: true, layers: {'train-cabin': 0.55, 'light-rain': 0.25}),
  AmbienceMix(id: 'car-ride-home', name: 'Sea and Rain', builtIn: true, layers: {'ocean': 0.45, 'light-rain': 0.35}),
  AmbienceMix(id: 'soft-music', name: 'Lullaby', builtIn: true, layers: {'harp': 0.4, 'brown-noise': 0.2}),
  AmbienceMix(id: 'coffee-focus', name: 'Coffee Shop', builtIn: true, layers: {'coffee-shop': 0.45, 'rain': 0.3}),
  AmbienceMix(id: 'deep-focus', name: 'Deep Focus', builtIn: true, layers: {'brown-noise': 0.45, 'green-noise': 0.2}),
  AmbienceMix(id: 'calm-noise', name: 'Calm Noise', builtIn: true, layers: {'pink-noise': 0.4, 'green-noise': 0.3}),
];
