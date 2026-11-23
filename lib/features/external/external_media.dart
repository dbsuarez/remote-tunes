import 'dart:async';

import 'package:flutter/services.dart';

/// A music app on this phone that currently has a media session (Spotify,
/// YouTube Music, …).
class ExternalSession {
  const ExternalSession({
    required this.package,
    required this.label,
    this.isPlaying = false,
    this.title = '',
  });

  final String package;

  /// The app's name as shown to the user (e.g. "Spotify").
  final String label;
  final bool isPlaying;
  final String title;

  static ExternalSession? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final package = raw['package'];
    if (package is! String || package.isEmpty) return null;
    final label = raw['label'];
    return ExternalSession(
      package: package,
      label: label is String && label.isNotEmpty ? label : package,
      isPlaying: raw['isPlaying'] == true,
      title: raw['title'] is String ? raw['title'] as String : '',
    );
  }
}

/// What the controlled app is playing now.
class ExternalTrack {
  const ExternalTrack({
    required this.package,
    required this.label,
    this.title = '',
    this.artist = '',
    this.album = '',
    this.durationMs = 0,
    this.positionMs = 0,
    this.isPlaying = false,
    this.isBuffering = false,
    this.canSeek = false,
    this.canNext = false,
    this.canPrevious = false,
  });

  final String package;
  final String label;
  final String title;
  final String artist;
  final String album;
  final int durationMs;
  final int positionMs;
  final bool isPlaying;
  final bool isBuffering;
  final bool canSeek;
  final bool canNext;
  final bool canPrevious;

  static ExternalTrack? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final package = raw['package'];
    if (package is! String || package.isEmpty) return null;
    String s(String k) => raw[k] is String ? raw[k] as String : '';
    int n(String k) => raw[k] is num ? (raw[k] as num).toInt() : 0;
    final label = s('label');
    return ExternalTrack(
      package: package,
      label: label.isEmpty ? package : label,
      title: s('title'),
      artist: s('artist'),
      album: s('album'),
      durationMs: n('durationMs'),
      positionMs: n('positionMs'),
      isPlaying: raw['isPlaying'] == true,
      isBuffering: raw['isBuffering'] == true,
      canSeek: raw['canSeek'] == true,
      canNext: raw['canNext'] == true,
      canPrevious: raw['canPrevious'] == true,
    );
  }
}

/// Everything the Player knows about other music apps right now.
class ExternalMediaSnapshot {
  const ExternalMediaSnapshot({
    this.accessGranted = false,
    this.sessions = const [],
    this.current,
    this.volume = 0.5,
  });

  /// The user allowed Notification access (needed to see media sessions).
  final bool accessGranted;
  final List<ExternalSession> sessions;
  final ExternalTrack? current;

  /// Phone media volume, 0.0–1.0.
  final double volume;

  static const empty = ExternalMediaSnapshot();

  static ExternalMediaSnapshot fromMap(Object? raw) {
    if (raw is! Map) return empty;
    final rawSessions = raw['sessions'];
    return ExternalMediaSnapshot(
      accessGranted: raw['accessGranted'] == true,
      sessions: rawSessions is List
          ? [
              for (final e in rawSessions)
                if (ExternalSession.fromMap(e) != null) ExternalSession.fromMap(e)!,
            ]
          : const [],
      current: ExternalTrack.fromMap(raw['current']),
      volume: raw['volume'] is num
          ? (raw['volume'] as num).toDouble().clamp(0.0, 1.0)
          : 0.5,
    );
  }
}

/// A failure the UI can show as is.
class ExternalMediaException implements Exception {
  ExternalMediaException(this.message, {this.noAccess = false, this.noSession = false});

  final String message;

  /// Notification access has not been granted.
  final bool noAccess;

  /// No music app has a session to control.
  final bool noSession;

  @override
  String toString() => message;
}

/// Link to the Android side that sees and controls other apps' media sessions.
/// An interface so the engine and UI can be tested without Android.
abstract class ExternalMediaBridge {
  /// Live updates while listening (see [start]).
  Stream<ExternalMediaSnapshot> get snapshots;

  /// Whether Notification access is currently allowed.
  Future<bool> isAccessGranted();

  /// Starts watching media sessions. Returns the current state (with
  /// `accessGranted: false` if the user has not allowed access).
  Future<ExternalMediaSnapshot> start();
  Future<void> stop();

  /// Opens Android's Notification access screen for RemoteTunes.
  Future<void> openAccessSettings();

  /// Opens RemoteTunes' App info (where Android 13+ has "Allow restricted
  /// settings" for apps installed outside the Play Store).
  Future<void> openAppInfo();

  /// Android version (SDK int), to explain the "restricted settings" step.
  Future<int> sdkInt();

  /// Choose which app to control when several have sessions; null = automatic.
  Future<void> selectSession(String? package);

  Future<void> play();
  Future<void> pause();
  Future<void> next();
  Future<void> previous();
  Future<void> seekTo(Duration position);

  /// Phone media volume, 0.0–1.0.
  Future<void> setVolume(double volume);
}

/// The real bridge: talks to `ExternalMediaBridge.kt` over platform channels.
class MethodChannelExternalMediaBridge implements ExternalMediaBridge {
  static const _method = MethodChannel('remotetunes/external_media');
  static const _events = EventChannel('remotetunes/external_media/events');

  Stream<ExternalMediaSnapshot>? _stream;

  @override
  Stream<ExternalMediaSnapshot> get snapshots => _stream ??= _events
      .receiveBroadcastStream()
      .map(ExternalMediaSnapshot.fromMap)
      .asBroadcastStream();

  Future<T?> _call<T>(String method, [Map<String, dynamic>? args]) async {
    try {
      return await _method.invokeMethod<T>(method, args);
    } on PlatformException catch (e) {
      switch (e.code) {
        case 'NO_ACCESS':
          throw ExternalMediaException(
            'Notification access is not allowed on the Player. Open the '
            'Player and allow it under External App Control.',
            noAccess: true,
          );
        case 'NO_SESSION':
          throw ExternalMediaException(
            'No music app is playing on the Player phone. Start Spotify or '
            'YouTube Music there first.',
            noSession: true,
          );
        default:
          throw ExternalMediaException(
              "The Player couldn't control that app right now.");
      }
    } on MissingPluginException {
      throw ExternalMediaException(
          'Controlling other apps is not available on this device.');
    }
  }

  @override
  Future<bool> isAccessGranted() async =>
      (await _call<bool>('isAccessGranted')) ?? false;

  @override
  Future<ExternalMediaSnapshot> start() async =>
      ExternalMediaSnapshot.fromMap(await _call<Object>('start'));

  @override
  Future<void> stop() => _call<void>('stop');

  @override
  Future<void> openAccessSettings() => _call<void>('openAccessSettings');

  @override
  Future<void> openAppInfo() => _call<void>('openAppInfo');

  @override
  Future<int> sdkInt() async => (await _call<int>('sdkInt')) ?? 0;

  @override
  Future<void> selectSession(String? package) =>
      _call<void>('selectSession', {'package': package});

  @override
  Future<void> play() => _call<void>('play');

  @override
  Future<void> pause() => _call<void>('pause');

  @override
  Future<void> next() => _call<void>('next');

  @override
  Future<void> previous() => _call<void>('previous');

  @override
  Future<void> seekTo(Duration position) =>
      _call<void>('seekTo', {'positionMs': position.inMilliseconds});

  @override
  Future<void> setVolume(double volume) =>
      _call<void>('setVolume', {'volume': volume});
}
