import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// The web Controller (lib/main_web.dart) must compile for the browser. Code
/// that only exists on phones (database, audio, Wi‑Fi discovery, dart:ffi, the
/// local network server) must never end up in its import graph. A browser
/// build is the real proof (`flutter build web -t lib/main_web.dart`); this
/// test catches the mistake in seconds, before anyone builds.
void main() {
  const forbidden = <String>[
    'dart:ffi',
    'package:drift/',
    'package:sqlite3',
    'package:bonsoir',
    'package:just_audio',
    'package:audio_service',
    'package:file_picker',
    'package:permission_handler',
    'package:path_provider',
    'package:shelf',
    'package:audio_metadata_reader',
    'package:web_socket_channel/io.dart',
  ];

  // Phone-only project files that must not be reachable from the web app.
  const forbiddenProjectFiles = <String>[
    'data/database/',
    'providers/providers.dart',
    'providers/connection_providers.dart',
    'providers/library_providers.dart',
    'features/player/server/',
    'features/player/audio/',
    'features/library/import_service.dart',
    'features/library/metadata_extractor.dart',
    'features/controller/discovery.dart',
    'core/transport/local_websocket_transport.dart',
    'core/permissions.dart',
  ];

  final libDir = Directory('lib');
  final importRe = RegExp(r'''^\s*(?:import|export)\s+['"]([^'"]+)['"]''', multiLine: true);

  /// Walks imports from [entry]; returns (file -> its imports).
  Map<String, List<String>> graph(String entry) {
    final seen = <String, List<String>>{};
    void visit(String file) {
      if (seen.containsKey(file)) return;
      final text = File(file).readAsStringSync();
      final imports = [for (final m in importRe.allMatches(text)) m.group(1)!];
      seen[file] = imports;
      for (final i in imports) {
        String? next;
        if (i.startsWith('package:remote_tunes/')) {
          next = p.join('lib', i.substring('package:remote_tunes/'.length));
        } else if (!i.contains(':')) {
          next = p.normalize(p.join(p.dirname(file), i));
        }
        if (next != null && File(next).existsSync()) visit(next);
      }
    }

    visit(entry);
    return seen;
  }

  test('the web entry point exists', () {
    expect(File('lib/main_web.dart').existsSync(), isTrue);
    expect(libDir.existsSync(), isTrue);
  });

  test('lib/main_web.dart pulls in no phone-only packages', () {
    final g = graph('lib/main_web.dart');
    expect(g.length, greaterThan(20), reason: 'the walk should reach the shared screens');
    final problems = <String>[];
    g.forEach((file, imports) {
      for (final i in imports) {
        for (final bad in forbidden) {
          if (i.startsWith(bad)) problems.add('$file imports $i');
        }
      }
    });
    expect(problems, isEmpty,
        reason: 'These files would break the web build:\n${problems.join('\n')}');
  });

  test('lib/main_web.dart reaches none of the phone-only project files', () {
    final g = graph('lib/main_web.dart');
    final problems = <String>[];
    for (final file in g.keys) {
      final normalized = file.replaceAll('\\', '/');
      for (final bad in forbiddenProjectFiles) {
        if (normalized.contains('lib/$bad')) problems.add(normalized);
      }
    }
    expect(problems, isEmpty,
        reason: 'Phone-only files are reachable from the web app:\n${problems.join('\n')}');
  });

  test('dart:io is only used where it is known to be harmless on the web', () {
    // dart:io compiles for the web but throws if the code runs, so each use
    // must be a place that never runs there.
    const allowed = <String>{
      // Image.file is only reached when an album-art path exists, and the
      // Controller never receives art paths.
      'lib/core/widgets/playback_widgets.dart',
    };
    final g = graph('lib/main_web.dart');
    final offenders = [
      for (final e in g.entries)
        if (e.value.contains('dart:io') &&
            !allowed.contains(e.key.replaceAll('\\', '/')))
          e.key.replaceAll('\\', '/'),
    ];
    expect(offenders, isEmpty,
        reason: 'New dart:io use in the web app. Check it cannot run in a '
            'browser, then add it to the allow-list:\n${offenders.join('\n')}');
  });

  test('the shared Controller screens file stays phone-free too', () {
    final g = graph('lib/features/controller/controller_views.dart');
    for (final e in g.entries) {
      for (final i in e.value) {
        for (final bad in forbidden) {
          expect(i.startsWith(bad), isFalse, reason: '${e.key} imports $i');
        }
      }
    }
  });

  test('the phone app is allowed to use phone-only code (sanity check of the '
      'checker itself)', () {
    final g = graph('lib/main.dart');
    final all = g.values.expand((e) => e).toList();
    expect(all.any((i) => i.startsWith('package:drift/')), isTrue,
        reason: 'if this fails the walk is not following imports');
  });
}
