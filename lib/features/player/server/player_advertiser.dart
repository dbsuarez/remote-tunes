import 'package:bonsoir/bonsoir.dart';

import '../../../core/constants.dart';

/// Advertises the Player on the local network (mDNS/NSD) so Controllers can
/// find it without typing an IP. Hotspots often block mDNS, so manual IP/port
/// remains the fallback.
abstract class PlayerAdvertiser {
  /// [roomCode] (if online is on) is advertised too, so a Controller in Auto
  /// mode that found this Player on the network can fall back to the online
  /// relay without typing anything.
  Future<void> start({
    required String name,
    required int port,
    required List<String> addresses,
    String? roomCode,
  });
  Future<void> stop();
}

class BonsoirPlayerAdvertiser implements PlayerAdvertiser {
  BonsoirBroadcast? _broadcast;

  @override
  Future<void> start({
    required String name,
    required int port,
    required List<String> addresses,
    String? roomCode,
  }) async {
    await stop();
    final service = BonsoirService(
      name: name,
      type: AppConstants.serviceType,
      port: port,
      attributes: {
        'v': AppConstants.protocolVersion.toString(),
        // Lets Controllers use a reliable IPv4 address even if the resolver
        // reports an IPv6 or .local host name.
        if (addresses.isNotEmpty) 'ip': addresses.join(','),
        if (roomCode != null) 'room': roomCode,
      },
    );
    final broadcast = BonsoirBroadcast(service: service);
    await broadcast.initialize();
    await broadcast.start();
    _broadcast = broadcast;
  }

  @override
  Future<void> stop() async {
    final b = _broadcast;
    _broadcast = null;
    if (b != null) {
      try {
        await b.stop();
      } catch (_) {}
    }
  }
}
