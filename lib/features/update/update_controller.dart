import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../providers/providers.dart';
import 'update_service.dart';

enum UpdateStatus {
  idle,
  checking,
  upToDate,
  available,
  downloading,

  /// Android's install screen has been opened; waiting for the user there.
  installing,
  needsPermission,
  failed,
}

class UpdateState {
  const UpdateState({
    this.status = UpdateStatus.idle,
    this.installed,
    this.info,
    this.progress = 0,
    this.message,
  });

  final UpdateStatus status;

  /// Installed version name (null until known, or not on Android).
  final String? installed;
  final UpdateInfo? info;
  final double progress;
  final String? message;

  UpdateState copyWith({
    UpdateStatus? status,
    String? installed,
    UpdateInfo? info,
    bool clearInfo = false,
    double? progress,
    String? message,
    bool clearMessage = false,
  }) =>
      UpdateState(
        status: status ?? this.status,
        installed: installed ?? this.installed,
        info: clearInfo ? null : (info ?? this.info),
        progress: progress ?? this.progress,
        message: clearMessage ? null : (message ?? this.message),
      );
}

final updateCheckerProvider = Provider<UpdateChecker>((ref) => UpdateChecker());
final updateNativeProvider = Provider<UpdateNative>((ref) => MethodChannelUpdateNative());

/// Where the downloaded update is kept (overridden in tests).
final updateDirProvider = Provider<Future<Directory> Function()>((ref) => () async {
      final base = await getTemporaryDirectory();
      return Directory('${base.path}${Platform.pathSeparator}updates');
    });

final updateProvider =
    StateNotifierProvider<UpdateController, UpdateState>((ref) => UpdateController(ref));

class UpdateController extends StateNotifier<UpdateState> {
  UpdateController(this._ref) : super(const UpdateState());

  final Ref _ref;
  bool _busy = false;

  /// How often the quiet check at start-up may run.
  static const autoCheckEvery = Duration(hours: 20);

  /// Looks for a newer version. [quiet] (the automatic check) says nothing when
  /// there is none or when the network is down.
  Future<void> check({bool quiet = false}) async {
    if (_busy) return;
    _busy = true;
    try {
      final native = _ref.read(updateNativeProvider);
      final me = await native.info();
      if (me == null) {
        if (!quiet) {
          state = state.copyWith(
              status: UpdateStatus.failed,
              message: 'Updating works in the Android app only.');
        }
        return;
      }
      if (!quiet) {
        state = state.copyWith(
            status: UpdateStatus.checking, installed: me.version, clearMessage: true);
      } else {
        state = state.copyWith(installed: me.version);
      }
      try {
        final info = await _ref
            .read(updateCheckerProvider)
            .latest(currentVersion: me.version, abi: me.abi);
        await _ref
            .read(settingsRepositoryProvider)
            .setLastUpdateCheck(DateTime.now().millisecondsSinceEpoch);
        if (info == null) {
          state = state.copyWith(
              status: quiet ? UpdateStatus.idle : UpdateStatus.upToDate, clearInfo: true);
        } else {
          state = state.copyWith(status: UpdateStatus.available, info: info, clearMessage: true);
        }
      } on UpdateException catch (e) {
        if (!quiet) state = state.copyWith(status: UpdateStatus.failed, message: e.message);
      }
    } finally {
      _busy = false;
    }
  }

  /// Start-up check: at most about once a day, only if the user allows it.
  Future<void> autoCheck() async {
    final s = await _ref.read(settingsRepositoryProvider).load();
    if (s.pendingUpdate) {
      // The app was restarted while Android's "allow installs" switch was open:
      // carry on with the update that was wanted.
      await check(quiet: true);
      if (state.status == UpdateStatus.available && await _ref.read(updateNativeProvider).canInstall()) {
        await install();
      } else {
        await _ref.read(settingsRepositoryProvider).setPendingUpdate(false);
      }
      return;
    }
    if (!s.autoUpdateCheck) return;
    final last = DateTime.fromMillisecondsSinceEpoch(s.lastUpdateCheck);
    if (DateTime.now().difference(last) < autoCheckEvery) return;
    await check(quiet: true);
  }

  /// Called when the app comes back to the front (for example from Android's
  /// install screen or the "allow installs" switch).
  Future<void> onResumed() async {
    if (_busy) return;
    switch (state.status) {
      case UpdateStatus.installing:
        // The install screen was closed without installing: the button works
        // again, and the download is kept.
        state = state.copyWith(status: UpdateStatus.available, clearMessage: true);
      case UpdateStatus.needsPermission:
        // Allowed just now: carry on without another tap.
        if (state.info != null && await _ref.read(updateNativeProvider).canInstall()) {
          await install();
        }
      default:
        break;
    }
  }

  /// Downloads the found update and hands it to Android's installer.
  Future<void> install() async {
    final info = state.info;
    if (info == null || _busy) return;
    final native = _ref.read(updateNativeProvider);
    final repo = _ref.read(settingsRepositoryProvider);
    if (!await native.canInstall()) {
      state = state.copyWith(
        status: UpdateStatus.needsPermission,
        message: 'Allow RemoteTunes to install updates. The update continues by itself when you come back.',
      );
      // Android may restart the app when this switch is flipped: remember that an
      // update was wanted, so it carries on at the next start.
      try {
        await repo.setPendingUpdate(true);
      } catch (_) {}
      await native.openInstallSettings();
      return;
    }
    try {
      await repo.setPendingUpdate(false);
    } catch (_) {}
    _busy = true;
    try {
      state = state.copyWith(status: UpdateStatus.downloading, progress: 0, clearMessage: true);
      final dir = await _ref.read(updateDirProvider)();
      final file = await _ref.read(updateCheckerProvider).download(
            info,
            dir,
            onProgress: (p) => state = state.copyWith(progress: p),
          );
      await native.install(file.path);
      // Android now shows its own install screen. Say so (the button is off),
      // and go back to "available" when the app returns to the front, so a
      // cancelled install can be retried without downloading again.
      state = state.copyWith(
        status: UpdateStatus.installing,
        message: 'Confirm the install on the screen Android just opened.',
      );
    } on UpdateException catch (e) {
      state = state.copyWith(status: UpdateStatus.failed, message: e.message);
    } finally {
      _busy = false;
    }
  }
}
