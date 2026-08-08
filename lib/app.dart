import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_theme.dart';
import 'screens/home_shell.dart';
import 'services/settings_service.dart';
import 'state/app_providers.dart';
import 'state/settings_controller.dart';

/// Rescripto root widget.
class RescriptoApp extends StatelessWidget {
  const RescriptoApp({super.key, required this.settings});

  final SettingsService settings;

  @override
  Widget build(BuildContext context) {
    return AppProviders(
      settings: settings,
      child: const _RescriptoMaterialApp(),
    );
  }
}

class _RescriptoMaterialApp extends StatelessWidget {
  const _RescriptoMaterialApp();

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();

    return MaterialApp(
      title: 'Rescripto',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeModeValue,
      home: const HomeShell(),
    );
  }
}
