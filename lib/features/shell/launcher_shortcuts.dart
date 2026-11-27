import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quick_actions/quick_actions.dart';

const shortcutPlayer = 'player';
const shortcutAmbience = 'ambience';
const shortcutAudiobooks = 'audiobooks';
const shortcutCloud = 'cloud';
const shortcutOnline = 'online';

/// The choices shown when the app's icon on the home screen is held.
abstract class LauncherShortcuts {
  /// Calls [onChosen] with the shortcut the app was opened by, now or later.
  Future<void> listen(void Function(String type) onChosen);

  /// Offers the player, Ambience under [ambienceName], and the audio books, cloud and online libraries.
  /// (Some home screens show only the first four.)
  Future<void> set(String ambienceName);
}

class PhoneLauncherShortcuts implements LauncherShortcuts {
  static const _actions = QuickActions();

  @override
  Future<void> listen(void Function(String type) onChosen) async {
    try {
      await _actions.initialize(onChosen);
    } catch (_) {
      // No shortcuts here (not a phone).
    }
  }

  @override
  Future<void> set(String ambienceName) async {
    try {
      await _actions.setShortcutItems([
        const ShortcutItem(type: shortcutPlayer, localizedTitle: 'Player', icon: 'ic_shortcut_player'),
        ShortcutItem(type: shortcutAmbience, localizedTitle: ambienceName, icon: 'ic_shortcut_ambience'),
        const ShortcutItem(type: shortcutAudiobooks, localizedTitle: 'Audio Books', icon: 'ic_shortcut_audiobooks'),
        const ShortcutItem(type: shortcutCloud, localizedTitle: 'Cloud Library', icon: 'ic_shortcut_cloud'),
        const ShortcutItem(type: shortcutOnline, localizedTitle: 'Online Library', icon: 'ic_shortcut_online'),
      ]);
    } catch (_) {}
  }
}

final launcherShortcutsProvider = Provider<LauncherShortcuts>((ref) => PhoneLauncherShortcuts());
