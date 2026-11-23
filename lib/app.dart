import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'core/constants.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';

class RemoteTunesApp extends StatefulWidget {
  const RemoteTunesApp({super.key});

  @override
  State<RemoteTunesApp> createState() => _RemoteTunesAppState();
}

class _RemoteTunesAppState extends State<RemoteTunesApp> {
  late final GoRouter _router = createRouter();

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: AppConstants.appName,
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.dark,
      routerConfig: _router,
    );
  }
}
