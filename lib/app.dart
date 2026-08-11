import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'core/app_theme.dart';
import 'screens/home_shell.dart';
import 'services/config_store.dart';
import 'services/db/app_database.dart';
import 'services/settings_service.dart';
import 'state/app_providers.dart';
import 'state/settings_controller.dart';

/// Rescripto root widget.
class RescriptoApp extends StatelessWidget {
  const RescriptoApp({
    super.key,
    required this.settings,
    required this.database,
    required this.configStore,
  });

  final SettingsService settings;
  final AppDatabase database;
  final ConfigStore configStore;

  @override
  Widget build(BuildContext context) {
    return AppProviders(
      settings: settings,
      database: database,
      configStore: configStore,
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
