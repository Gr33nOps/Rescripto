import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/local_llm_service.dart';
import '../services/model_manager.dart';
import '../services/settings_service.dart';
import '../services/speech_service.dart';
import '../services/storage_service.dart';
import 'history_controller.dart';
import 'models_controller.dart';
import 'rewrite_controller.dart';
import 'settings_controller.dart';
import 'speech_controller.dart';

/// Registers all services + controllers with provider.
class AppProviders extends StatelessWidget {
  const AppProviders({super.key, required this.settings, required this.child});

  final SettingsService settings;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SettingsService>(create: (_) => settings),
        Provider<StorageService>(
          create: (_) => StorageService(),
          dispose: (_, service) => service.close(),
        ),
        Provider<LocalLlmService>(
          create: (_) => LocalLlmService(),
          dispose: (_, service) => service.dispose(),
        ),
        Provider<SpeechService>(
          create: (_) => SpeechService(),
          dispose: (_, service) => service.dispose(),
        ),
        Provider<ModelManager>(
          create: (_) => ModelManager(),
          dispose: (_, manager) => manager.dispose(),
        ),
        ChangeNotifierProvider<SettingsController>(
          create: (ctx) => SettingsController(ctx.read<SettingsService>()),
        ),
        ChangeNotifierProvider<ModelsController>(
          create: (ctx) => ModelsController(
            manager: ctx.read<ModelManager>(),
            settings: ctx.read<SettingsService>(),
            llm: ctx.read<LocalLlmService>(),
          ),
        ),
        ChangeNotifierProvider<RewriteController>(
          create: (ctx) => RewriteController(
            llm: ctx.read<LocalLlmService>(),
            settings: ctx.read<SettingsService>(),
            storage: ctx.read<StorageService>(),
          ),
        ),
        ChangeNotifierProvider<HistoryController>(
          create: (ctx) => HistoryController(ctx.read<StorageService>()),
        ),
        ChangeNotifierProvider<SpeechController>(
          create: (ctx) => SpeechController(
            ctx.read<SpeechService>(),
            ctx.read<SettingsService>(),
          ),
        ),
      ],
      child: child,
    );
  }
}
