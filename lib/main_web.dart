import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/pairing_qr.dart';
import 'providers/recent_links.dart';
import 'web/web_app.dart';
import 'web/web_storage.dart';

/// Web Controller entry point (docs/17_WEB_CONTROLLER.md).
///
///   flutter run -d chrome -t lib/main_web.dart
///   flutter build web -t lib/main_web.dart
///
/// Controller only: no audio, no database, no local network. Everything here
/// must stay free of phone-only code (test/web_safety_test.dart checks it).
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Flutter on the web draws to a canvas; this also exposes the controls to
  // screen readers and browser automation.
  SemanticsBinding.instance.ensureSemantics();
  final prefs = await SharedPreferences.getInstance();
  final storage = WebStorage(prefs);
  // Opened from a Player's QR code? Read it before Flutter rewrites the address.
  final link = PairingQr.fromFragment(Uri.base.fragment);
  runApp(
    ProviderScope(
      overrides: [
        webStorageProvider.overrideWithValue(storage),
        webLaunchLinkProvider.overrideWithValue(link),
        recentLinksStoreProvider.overrideWithValue(WebRecentLinksStore(storage)),
      ],
      child: const WebControllerApp(),
    ),
  );
}
