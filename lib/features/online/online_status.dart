enum OnlinePhase { connecting, connected, reconnecting, failed }

/// State of the Player's online relay (docs/12_PHASE_4).
class OnlineRelayInfo {
  const OnlineRelayInfo({
    required this.roomCode,
    required this.phase,
    this.error,
  });

  /// The room Controllers join. Short-lived: new for every Player session.
  final String roomCode;
  final OnlinePhase phase;

  /// Plain-language reason when [phase] is failed or reconnecting.
  final String? error;

  bool get isConnected => phase == OnlinePhase.connected;
}
