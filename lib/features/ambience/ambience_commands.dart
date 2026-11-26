import '../../core/protocol/protocol.dart';
import '../player/playback_engine.dart';
import 'ambience_models.dart';

/// Does what a Controller asked of the Player's ambience ([p] with no `op`: only look), and answers
/// with the state. Throws [PlaybackException] with a plain reason.
Future<Map<String, dynamic>> runAmbienceCommand(AmbienceControls ambience, Map<String, dynamic> p) async {
  Never bad(String why) => throw PlaybackException(ErrorCodes.invalidAction, why);
  String text(String key) {
    final v = p[key];
    if (v is! String || v.isEmpty || v.length > 100) bad('That ambience request needs $key.');
    return v;
  }

  double volume() {
    final v = p['volume'];
    if (v is! num || v.isNaN) bad('That ambience request needs a volume.');
    return v.toDouble().clamp(0.0, 1.0);
  }

  var missing = const <String>[];
  try {
    await ambience.refresh();
    switch (p['op']) {
      case null:
        break;
      case 'toggle':
        if (p['on'] is! bool) bad('That ambience request needs on: true or false.');
        await ambience.setActive(text('id'), p['on'] as bool);
      case 'volume':
        await ambience.setVolume(text('id'), volume());
      case 'master':
        await ambience.setMaster(volume());
      case 'play':
        await ambience.play();
      case 'pause':
        await ambience.pause();
      case 'stop':
        await ambience.stop();
      case 'timer':
        final m = p['minutes'];
        if (m is! num || m < 0 || m > 720) bad('That ambience timer is not possible.');
        await ambience.setTimer(m.toInt() == 0 ? null : m.toInt());
      case 'mix':
        missing = await ambience.startMix(text('id'));
      case 'saveMix':
        await ambience.saveMix(text('name'));
      case 'deleteMix':
        await ambience.deleteMix(text('id'));
      default:
        bad('Unknown ambience request.');
    }
  } on PlaybackException {
    rethrow;
  } catch (e) {
    bad('$e');
  }
  return {'state': ambience.state.toJson(), if (missing.isNotEmpty) 'missing': missing};
}
