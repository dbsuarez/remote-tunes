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
    if (!s.autoUpdateCheck) return;
    final last = DateTime.fromMillisecondsSinceEpoch(s.lastUpdateCheck);
    if (DateTime.now().difference(last) < autoCheckEvery) return;
    await check(quiet: true);
  }

  /// Downloads the found update and hands it to Android's installer.
  Future<void> install() async {
    final info = state.info;
    if (info == null || _busy) return;
    final native = _ref.read(updateNativeProvider);
    if (!await native.canInstall()) {
      state = state.copyWith(
        status: UpdateStatus.needsPermission,
        message: 'Allow RemoteTunes to install updates, then come back and tap Update again.',
      );
      await native.openInstallSettings();
      return;
    }
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
      // Android now shows its own install screen; stay on "available" so a
      // cancelled install can be retried.
      state = state.copyWith(status: UpdateStatus.available);
    } on UpdateException catch (e) {
      state = state.copyWith(status: UpdateStatus.failed, message: e.message);
    } finally {
      _busy = false;
    }
  }
}
