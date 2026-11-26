import 'package:flutter/material.dart';

import 'ambience_models.dart';

/// The icons a sound can be given. Kept by name, so the choice reads the same on the other phone.
const ambienceIconLibrary = <String, IconData>{
  // weather and sky
  'drop': Icons.water_drop_rounded,
  'drizzle': Icons.grain_rounded,
  'storm': Icons.thunderstorm_rounded,
  'bolt': Icons.bolt_rounded,
  'cloud': Icons.cloud_rounded,
  'umbrella': Icons.umbrella_rounded,
  'snow': Icons.ac_unit_rounded,
  'wind': Icons.air_rounded,
  'windmill': Icons.wind_power_rounded,
  'sun': Icons.wb_sunny_rounded,
  'sunset': Icons.wb_twilight_rounded,
  'moon': Icons.nightlight_round,
  'night': Icons.dark_mode_rounded,
  'stars': Icons.auto_awesome_rounded,
  // water
  'waves': Icons.waves_rounded,
  'river': Icons.water_rounded,
  'pool': Icons.pool_rounded,
  'boat': Icons.sailing_rounded,
  'ship': Icons.directions_boat_rounded,
  'beach': Icons.beach_access_rounded,
  'shower': Icons.shower_rounded,
  // land and living things
  'landscape': Icons.landscape_rounded,
  'mountain': Icons.terrain_rounded,
  'tree': Icons.park_rounded,
  'forest': Icons.forest_rounded,
  'grass': Icons.grass_rounded,
  'flower': Icons.local_florist_rounded,
  'leaf': Icons.eco_rounded,
  'nature': Icons.emoji_nature_rounded,
  'paw': Icons.pets_rounded,
  'rabbit': Icons.cruelty_free_rounded,
  'bird': Icons.flutter_dash,
  'bug': Icons.bug_report_rounded,
  // fire and places
  'fire': Icons.local_fire_department_rounded,
  'fireplace': Icons.fireplace_rounded,
  'home': Icons.home_rounded,
  'cabin': Icons.cabin_rounded,
  'castle': Icons.castle_rounded,
  'city': Icons.location_city_rounded,
  'cafe': Icons.local_cafe_rounded,
  // travel
  'car': Icons.directions_car_rounded,
  'train': Icons.train_rounded,
  'plane': Icons.flight_rounded,
  // rest and play
  'bed': Icons.bed_rounded,
  'baby': Icons.child_care_rounded,
  'toy': Icons.toys_rounded,
  'heart': Icons.favorite_rounded,
  'spa': Icons.spa_rounded,
  'calm': Icons.self_improvement_rounded,
  'bell': Icons.notifications_rounded,
  'note': Icons.music_note_rounded,
  'piano': Icons.piano_rounded,
  'noise': Icons.graphic_eq_rounded,
};

const _usual = {
  'rain': 'drop',
  'light-rain': 'drizzle',
  'thunder': 'storm',
  'distant-thunder': 'bolt',
  'ocean': 'waves',
  'seagulls': 'bird',
  'stream': 'river',
  'crickets': 'moon',
  'owls': 'night',
  'frogs': 'paw',
  'campfire': 'fire',
  'wind': 'wind',
  'birds': 'tree',
  'white-noise': 'noise',
  'pink-noise': 'noise',
  'brown-noise': 'noise',
};

/// The name of the icon a sound shows: the one chosen, else its usual one.
String ambienceIconName(AmbienceSound s) {
  final chosen = s.icon;
  if (chosen != null && ambienceIconLibrary.containsKey(chosen)) return chosen;
  return _usual[s.id] ?? (s.category == ambienceEnvironmentCategory ? 'landscape' : 'note');
}

IconData ambienceIcon(AmbienceSound s) => ambienceIconLibrary[ambienceIconName(s)]!;
