import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:quick_actions/quick_actions.dart';

const shortcutPlayer = 'player';
const shortcutAmbience = 'ambience';

/// The choices shown when the app's icon on the home screen is held.
abstract class LauncherShortcuts {
  /// Calls [onChosen] with the shortcut the app was opened by, now or later.
  Future<void> listen(void Function(String type) onChosen);

  /// Offers the player, and Ambience under [ambienceName].
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
      ]);
    } catch (_) {}
  }
}

final launcherShortcutsProvider = Provider<LauncherShortcuts>((ref) => PhoneLauncherShortcuts());
