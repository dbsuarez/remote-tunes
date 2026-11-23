import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/constants.dart';
import 'package:remote_tunes/features/settings/diagnostics_screen.dart';

void main() {
  test('the app version constant matches pubspec.yaml', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    final version = line.split(':')[1].trim().split('+').first;
    expect(AppConstants.appVersion, version);
  });

  test('the report lists status and contains no secrets', () {
    const info = DiagnosticsInfo(
      appVersion: '0.1.0',
      protocolVersion: 1,
      platform: 'android 14',
      schemaVersion: 3,
      connectionMode: 'auto',
      onlineRelayEnabled: true,
      onlineKeysSet: true,
      externalControlEnabled: true,
      notificationAccess: false,
      port: 8765,
      addresses: ['192.168.1.20'],
      songs: 12,
      favorites: 3,
      playlists: 2,
      trustedControllers: 1,
    );
    final r = info.toReport();
    expect(r, contains('Version: 0.1.0'));
    expect(r, contains('Database schema: 3'));
    expect(r, contains('Relay keys set: yes'));
    expect(r, contains('Notification access: no'));
    expect(r, contains('192.168.1.20'));
    expect(r, contains('Songs: 12'));
    expect(r.toLowerCase(), isNot(contains('token')));
    expect(r.toLowerCase(), isNot(contains('sb_publishable')));
  });
}
