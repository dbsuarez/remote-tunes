import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:remote_tunes/core/constants.dart';
import 'package:remote_tunes/features/group/group_models.dart';
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

  group('group play and Online Library lines', () {
    DiagnosticsInfo info({GroupStatus? group, bool mic = true}) => DiagnosticsInfo(
          appVersion: '0.1.0',
          protocolVersion: 1,
          platform: 'android 14',
          schemaVersion: 4,
          connectionMode: 'auto',
          onlineRelayEnabled: true,
          onlineKeysSet: true,
          externalControlEnabled: false,
          notificationAccess: null,
          port: 8765,
          addresses: const ['192.168.1.20'],
          songs: 12,
          favorites: 3,
          playlists: 2,
          trustedControllers: 1,
          jamendoClientIdSet: true,
          onlineHistoryEnabled: false,
          onlineHistoryCount: 7,
          savedQueueSongs: 4,
          savedQueueStreams: 2,
          outputRoute: 'bluetooth',
          outputLatencyMs: 64,
          microphonePermission: mic,
          group: group,
        );

    test('when this phone is not playing along it says so, plainly', () {
      final r = info().toReport();
      expect(r, contains('Sound output: bluetooth'));
      expect(r, contains("audio delay: 64 ms"));
      expect(r, contains('Microphone permission (Auto-align): yes'));
      expect(r, contains('Playing along: no'));
      expect(r, contains('Saved queue: 4 songs, 2 internet tracks'));
      expect(r, contains('Jamendo client ID set: yes'));
      expect(r, contains('History: off, 7 entries'));
    });

    test('while playing along it lists the numbers that matter', () {
      final r = info(
        group: const GroupStatus(
          phase: GroupPhase.playing,
          driftMs: 12.34,
          rttMs: 8.0,
          spreadMs: 1.5,
          offsetMs: -4231.7,
          nudgeMs: 37,
          route: 'speaker',
          warning: 'The Wi-Fi is uneven right now.\nMove closer.',
          calibration: 'This phone was 37.0 ms late.',
        ),
      ).toReport();
      expect(r, contains('Playing along: playing'));
      expect(r, contains('Off by (this phone vs Player): 12.3 ms'));
      expect(r, contains('Round trip: 8.0 ms'));
      expect(r, contains('Clock spread: 1.5 ms'));
      expect(r, contains('Fine-tune (speaker): 37 ms'));
      expect(r, contains('Warning: The Wi-Fi is uneven right now. Move closer.'));
      expect(r, contains('Last Auto-align: This phone was 37.0 ms late.'));
    });

    test('a refused microphone and an unknown one are shown', () {
      expect(info(mic: false).toReport(), contains('(Auto-align): no'));
      final unknown = DiagnosticsInfo(
        appVersion: '1',
        protocolVersion: 1,
        platform: 'x',
        schemaVersion: 4,
        connectionMode: 'auto',
        onlineRelayEnabled: false,
        onlineKeysSet: false,
        externalControlEnabled: false,
        notificationAccess: null,
        port: 1,
        addresses: const [],
        songs: 0,
        favorites: 0,
        playlists: 0,
        trustedControllers: 0,
      );
      expect(unknown.toReport(), contains('(Auto-align): unknown'));
      expect(unknown.toReport(), contains('not reported'));
    });

    test('the Jamendo ID itself is never in the report', () {
      const id = 'testid1234';
      final r = info().toReport();
      expect(r, isNot(contains(id)));
      expect(r, isNot(contains('client_id')));
    });
  });
}
