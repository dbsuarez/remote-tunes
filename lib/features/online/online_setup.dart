import 'dart:async';

import '../../core/models/enums.dart';
import '../../core/online/relay.dart';
import '../../data/repositories/settings_repository.dart';

/// Whether the online relay can be used with the current settings, and if not,
/// why (in plain language, for the UI).
class OnlineAvailability {
  const OnlineAvailability.ready()
      : usable = true,
        problem = null;
  const OnlineAvailability.notReady(this.problem) : usable = false;

  final bool usable;
  final String? problem;

  /// Checks the settings entered by the user (Settings → Online relay).
  static OnlineAvailability evaluate(AppSettings s) {
    if (!s.onlineRelayEnabled) {
      return const OnlineAvailability.notReady(
        'The online relay is turned off. Turn it on in Settings → Online relay.',
      );
    }
    final url = s.supabaseUrl?.trim() ?? '';
    final key = s.supabaseAnonKey?.trim() ?? '';
    if (url.isEmpty) {
      return const OnlineAvailability.notReady(
          'Enter your Supabase URL in Settings → Online relay.');
    }
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      return const OnlineAvailability.notReady(
        'The Supabase URL should look like https://your-project.supabase.co.',
      );
    }
    if (key.isEmpty) {
      return const OnlineAvailability.notReady(
          'Enter your Supabase anon key in Settings → Online relay.');
    }
    return const OnlineAvailability.ready();
  }
}

/// What the Player should run for a connection mode and the settings.
class PlayerOnlinePlan {
  const PlayerOnlinePlan({
    required this.runLocal,
    required this.runOnline,
    this.problem,
  });

  /// Open the local network server.
  final bool runLocal;

  /// Join an online room.
  final bool runOnline;

  /// Why online was wanted but could not be started (shown to the user). Null
  /// when online is simply not wanted.
  final String? problem;

  static PlayerOnlinePlan forMode(ConnectionMode mode, AppSettings s) {
    final wantsOnline = mode != ConnectionMode.localOnly;
    final availability = OnlineAvailability.evaluate(s);
    final runOnline = wantsOnline && availability.usable;
    return PlayerOnlinePlan(
      // Online-only does not open the local network at all.
      runLocal: mode != ConnectionMode.onlineOnly,
      runOnline: runOnline,
      // Auto without setup just stays local; only Online-only must explain.
      problem: (mode == ConnectionMode.onlineOnly && !availability.usable)
          ? availability.problem
          : null,
    );
  }
}

/// A channel that can never join; used so a missing setup is reported with its
/// real reason ("Turn on the online relay…") through the normal error path.
class UnavailableRelayChannel implements RelayChannel {
  UnavailableRelayChannel(this.reason);

  final String reason;

  @override
  Future<void> join() async => throw RelayException(reason);

  @override
  Stream<RelayFrame> get frames => const Stream.empty();

  @override
  Stream<RelayStatus> get status => const Stream.empty();

  @override
  Future<void> send(RelayFrame frame) async => throw RelayException(reason);

  @override
  Future<void> leave() async {}
}

/// Result of "Test online relay" in Settings.
class RelayTestResult {
  const RelayTestResult.ok()
      : success = true,
        message = 'Connected to the online relay.';
  const RelayTestResult.failed(this.message) : success = false;

  final bool success;
  final String message;
}

/// Joins a throw-away room to check that the relay is reachable with the
/// entered keys, then leaves. Sends nothing but the join itself.
Future<RelayTestResult> testRelayConnection(
  RelayChannelFactory factory, {
  Duration timeout = const Duration(seconds: 12),
  String room = 'SELFTEST',
}) async {
  final channel = factory(room);
  try {
    await channel.join().timeout(timeout);
    return const RelayTestResult.ok();
  } on RelayException catch (e) {
    return RelayTestResult.failed(e.message);
  } on TimeoutException {
    return const RelayTestResult.failed(
      'The online relay took too long to answer. Check the internet connection.',
    );
  } catch (_) {
    return const RelayTestResult.failed("Couldn't connect to the online relay.");
  } finally {
    try {
      await channel.leave();
    } catch (_) {}
  }
}
