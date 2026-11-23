import 'dart:async';

import 'package:bonsoir/bonsoir.dart';

import '../../core/constants.dart';
import '../../core/online/room_code.dart';

class DiscoveredPlayer {
  const DiscoveredPlayer({
    required this.name,
    required this.host,
    required this.port,
    this.roomCode,
  });

  final String name;
  final String host;
  final int port;

  /// The Player's online room, if it advertises one. Lets a Controller in
  /// Auto mode fall back to the online relay without typing anything.
  final String? roomCode;

  @override
  bool operator ==(Object other) =>
      other is DiscoveredPlayer &&
      other.name == name &&
      other.host == host &&
      other.port == port &&
      other.roomCode == roomCode;

  @override
  int get hashCode => Object.hash(name, host, port, roomCode);
}

/// Finds Players on the local network. Cancel the stream subscription to stop.
abstract class PlayerDiscovery {
  Stream<List<DiscoveredPlayer>> discover();
}

bool _isIpv4(String s) => RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(s);

class BonsoirPlayerDiscovery implements PlayerDiscovery {
  @override
  Stream<List<DiscoveredPlayer>> discover() {
    late final StreamController<List<DiscoveredPlayer>> controller;
    BonsoirDiscovery? discovery;
    StreamSubscription<BonsoirDiscoveryEvent>? sub;
    final found = <String, DiscoveredPlayer>{};

    void publish() {
      if (!controller.isClosed) {
        controller.add(found.values.toList()..sort((a, b) => a.name.compareTo(b.name)));
      }
    }

    controller = StreamController<List<DiscoveredPlayer>>(
      onListen: () async {
        controller.add(const []);
        try {
          final d = BonsoirDiscovery(type: AppConstants.serviceType);
          discovery = d;
          await d.initialize();
          sub = d.eventStream!.listen((event) {
            final service = event.service;
            if (event is BonsoirDiscoveryServiceFoundEvent) {
              service?.resolve(d.serviceResolver);
            } else if (event is BonsoirDiscoveryServiceResolvedEvent ||
                event is BonsoirDiscoveryServiceUpdatedEvent) {
              if (service == null) return;
              // Prefer the IPv4 address the Player advertised itself.
              final advertised = (service.attributes['ip'] ?? '')
                  .split(',')
                  .where(_isIpv4)
                  .toList();
              final resolved = service.host;
              final host = advertised.isNotEmpty
                  ? advertised.first
                  : (resolved != null && _isIpv4(resolved) ? resolved : null);
              if (host == null) return;
              final advertisedRoom =
                  RoomCode.normalize(service.attributes['room'] ?? '');
              found[service.name] = DiscoveredPlayer(
                name: service.name,
                host: host,
                port: service.port,
                roomCode:
                    RoomCode.isValid(advertisedRoom) ? advertisedRoom : null,
              );
              publish();
            } else if (event is BonsoirDiscoveryServiceLostEvent) {
              if (service != null && found.remove(service.name) != null) {
                publish();
              }
            }
          });
          await d.start();
        } catch (e, st) {
          if (!controller.isClosed) controller.addError(e, st);
        }
      },
      onCancel: () async {
        await sub?.cancel();
        try {
          await discovery?.stop();
        } catch (_) {}
        await controller.close();
      },
    );
    return controller.stream;
  }
}
