import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/features/ambience/ambience_import.dart';
import 'package:remote_tunes/features/ambience/ambience_models.dart';

void main() {
  Map<String, String> plan(List<String> files, [List<AmbienceSound> sounds = ambienceCatalog]) =>
      {for (final r in planImport([for (final f in files) '/f/$f'], sounds)) r.fileName: r.target};
  const fresh = AmbienceImportRow.newSound;

  test('files named like the sounds go to them', () {
    expect(
      plan(['Rain.wav', 'Light Rain.wav', 'Distant Thunder.mp3', 'Ocean Waves.wav', 'Stream.wav', 'Crickets.wav', 'Frogs.mp3',
          'Campfire.mp3', 'Wind.wav', 'Birds.wav']),
      {
        'Rain.wav': 'rain',
        'Light Rain.wav': 'light-rain',
        'Distant Thunder.mp3': 'distant-thunder',
        'Ocean Waves.wav': 'ocean',
        'Stream.wav': 'stream',
        'Crickets.wav': 'crickets',
        'Frogs.mp3': 'frogs',
        'Campfire.mp3': 'campfire',
        'Wind.wav': 'wind',
        'Birds.wav': 'birds',
      },
    );
  });

  test('names that hold the words match, the more exact sound first', () {
    expect(
      plan(['weather_light_rain.mp3', 'water_ocean_waves.mp3', 'fire_campfire.mp3', 'weather_winter_wind.mp3', 'nature_birds.mp3']),
      {
        'weather_light_rain.mp3': 'light-rain',
        'water_ocean_waves.mp3': 'ocean',
        'fire_campfire.mp3': 'campfire',
        'weather_winter_wind.mp3': 'wind',
        'nature_birds.mp3': 'birds',
      },
    );
  });

  test('part of a word is not a match, and the rest become new sounds', () {
    expect(plan(['weather_heavy_thunderstorm.mp3', 'Rainforest Canopy.mp3', 'envelope.mp3']),
        {'weather_heavy_thunderstorm.mp3': fresh, 'Rainforest Canopy.mp3': fresh, 'envelope.mp3': fresh});
  });

  test('files marked "env" are environments, named after what follows, and take no slot', () {
    final rows = planImport([
      for (final f in [
        'water_env_mountain_stream.mp3',
        'water_env_ocean_waves.mp3',
        'water_env_peaceful_lake .mp3',
        'water_env_swamp.mp3',
        'water_env_underground_river .mp3',
        'AMB_Nature Pack Vol 1_Forest Enviroments_Forest Night.mp3',
      ])
        '/f/$f',
    ], ambienceCatalog);
    expect({for (final r in rows) r.target}, {AmbienceImportRow.newEnvironment});
    expect([for (final r in rows) r.newName],
        ['Mountain Stream', 'Ocean Waves', 'Peaceful Lake', 'Swamp', 'Underground River', 'Forest Night']);
  });

  test('importing an environment again replaces it, and not a sound of your own with that name', () {
    const mine = AmbienceSound(id: 'own-1', name: 'Swamp', category: ambienceOwnCategory, available: true);
    const place = AmbienceSound(id: 'own-2', name: 'Swamp', category: ambienceEnvironmentCategory, available: true);
    expect(plan(['water_env_swamp.mp3'], [...ambienceCatalog, mine, place]), {'water_env_swamp.mp3': 'own-2'});
  });

  test('two files never share a sound; the one named exactly wins', () {
    expect(plan(['weather_wind.mp3', 'Wind.wav', 'desert wind.mp3']), {'weather_wind.mp3': fresh, 'Wind.wav': 'wind', 'desert wind.mp3': fresh});
  });

  test('only files that can be looped are listed, and the noises are never replaced', () {
    expect(plan(['rain.m4a', 'readme.txt', '.mp3', 'White Noise.wav']), {'White Noise.wav': fresh});
    expect(importTargets(ambienceCatalog).map((s) => s.id), isNot(contains('white-noise')));
  });

  test('long pack names are shortened to what they are', () {
    final rows = planImport(['/f/AMB_Nature Pack Vol 1_Water Enviroments_Peaceful Lake .mp3', '/f/a_very_long_name_that_goes_on_and_on_x.wav'], ambienceCatalog);
    expect(rows.first.newName, 'Peaceful Lake');
    expect(rows.last.newName.length, lessThanOrEqualTo(30));
  });

  test('importing again replaces your own sound of that name', () {
    const own = AmbienceSound(id: 'own-1', name: 'Peaceful Lake', category: ambienceOwnCategory, available: true);
    expect(plan(['Peaceful Lake.mp3'], [...ambienceCatalog, own]), {'Peaceful Lake.mp3': 'own-1'});
  });
}
