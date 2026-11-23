import 'package:permission_handler/permission_handler.dart';

enum PermissionOutcome { granted, denied, permanentlyDenied }

/// Runtime permissions RemoteTunes asks for. An interface so UI tests can
/// replace it (the real one needs the Android plugin).
abstract class AppPermissions {
  /// Access to the user's music files, needed to import a whole folder.
  /// (Picking individual files with the system picker needs no permission.)
  Future<PermissionOutcome> ensureMusicAccess();

  /// Android 13+ notification permission, needed to show the media
  /// notification. Playback still works without it.
  Future<PermissionOutcome> ensureNotifications();

  Future<void> openSettings();
}

class PermissionHandlerPermissions implements AppPermissions {
  PermissionOutcome _outcome(PermissionStatus s) {
    if (s.isGranted || s.isLimited) return PermissionOutcome.granted;
    if (s.isPermanentlyDenied) return PermissionOutcome.permanentlyDenied;
    return PermissionOutcome.denied;
  }

  @override
  Future<PermissionOutcome> ensureMusicAccess() async {
    // Android 13+ uses READ_MEDIA_AUDIO; older versions use READ_EXTERNAL_STORAGE.
    // permission_handler ignores `audio` on old versions and `storage` on new
    // ones, so try both in turn.
    var audio = await Permission.audio.status;
    if (audio.isGranted) return PermissionOutcome.granted;
    audio = await Permission.audio.request();
    if (audio.isGranted) return PermissionOutcome.granted;

    var storage = await Permission.storage.status;
    if (storage.isGranted) return PermissionOutcome.granted;
    storage = await Permission.storage.request();
    if (storage.isGranted) return PermissionOutcome.granted;

    return (audio.isPermanentlyDenied || storage.isPermanentlyDenied)
        ? PermissionOutcome.permanentlyDenied
        : PermissionOutcome.denied;
  }

  @override
  Future<PermissionOutcome> ensureNotifications() async {
    var s = await Permission.notification.status;
    if (s.isGranted) return PermissionOutcome.granted;
    s = await Permission.notification.request();
    return _outcome(s);
  }

  @override
  Future<void> openSettings() async {
    await openAppSettings();
  }
}
