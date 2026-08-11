import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/engine_registry.dart';
import '../engine/local/local_engine_host.dart';
import '../engine/local/local_llm_engine.dart';
import '../services/config_store.dart';
import '../services/credentials/credential_store.dart';
import '../services/db/app_database.dart';
import '../services/local_llm_service.dart';
import '../services/model_manager.dart';
import '../services/network/network_feature.dart';
import '../services/network/network_guard.dart';
import '../services/network/network_log.dart';
import '../services/network/network_policy.dart';
import '../services/panic_service.dart';
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
  const AppProviders({
    super.key,
    required this.settings,
    required this.database,
    required this.configStore,
    required this.networkPolicy,
    required this.child,
  });

  final SettingsService settings;
  final AppDatabase database;
  final ConfigStore configStore;
  final NetworkPolicy networkPolicy;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<SettingsService>(create: (_) => settings),
        // Built and loaded before runApp (see main.dart) so every store
        // below shares the one connection, and ConfigStore never renders an
        // empty frame while its seed rows are still being written.
        Provider<AppDatabase>(
          create: (_) => database,
          dispose: (_, database) => database.close(),
        ),
        ChangeNotifierProvider<ConfigStore>.value(value: configStore),
        Provider<StorageService>(
          create: (ctx) => StorageService(ctx.read<AppDatabase>()),
        ),
        ChangeNotifierProvider<NetworkPolicy>.value(value: networkPolicy),
        Provider<NetworkLog>(
          create: (ctx) => NetworkLog(ctx.read<AppDatabase>()),
        ),
        // The only sanctioned way to obtain a network client anywhere in the
        // app — see NetworkGuard's own doc comment for what that does and
        // does not guarantee.
        Provider<NetworkGuard>(
          create: (ctx) =>
              NetworkGuard(ctx.read<NetworkPolicy>(), ctx.read<NetworkLog>()),
        ),
        Provider<CredentialStore>(
          create: (ctx) => CredentialStore(ctx.read<AppDatabase>()),
        ),
        Provider<PanicService>(
          create: (ctx) => PanicService(
            ctx.read<CredentialStore>(),
            ctx.read<NetworkPolicy>(),
          ),
        ),
        // Sole owner of the native llama.cpp singleton — every mutating call
        // to it, from either controller below, is routed through here.
        Provider<LocalEngineHost>(
          create: (_) => LocalEngineHost(LocalLlmService()),
        ),
        Provider<EngineRegistry>(
          create: (ctx) => EngineRegistry([
            LocalLlmEngine(ctx.read<LocalEngineHost>(), ctx.read<SettingsService>()),
          ]),
          dispose: (_, registry) => registry.dispose(),
        ),
        Provider<SpeechService>(
          create: (_) => SpeechService(),
          dispose: (_, service) => service.dispose(),
        ),
        Provider<ModelManager>(
          create: (ctx) => ModelManager(
            dio: ctx.read<NetworkGuard>().dioFor(
              NetworkFeature.modelDownload,
              purpose: 'Download AI model',
            ),
          ),
          dispose: (_, manager) => manager.dispose(),
        ),
        ChangeNotifierProvider<SettingsController>(
          create: (ctx) => SettingsController(ctx.read<SettingsService>()),
        ),
        ChangeNotifierProvider<ModelsController>(
          create: (ctx) => ModelsController(
            manager: ctx.read<ModelManager>(),
            settings: ctx.read<SettingsService>(),
            host: ctx.read<LocalEngineHost>(),
          ),
        ),
        ChangeNotifierProvider<RewriteController>(
          create: (ctx) => RewriteController(
            registry: ctx.read<EngineRegistry>(),
            settings: ctx.read<SettingsService>(),
            storage: ctx.read<StorageService>(),
            configStore: ctx.read<ConfigStore>(),
          ),
        ),
        ChangeNotifierProvider<HistoryController>(
          create: (ctx) => HistoryController(ctx.read<StorageService>()),
        ),
        ChangeNotifierProvider<SpeechController>(
          create: (ctx) => SpeechController(
            ctx.read<SpeechService>(),
            ctx.read<SettingsService>(),
            ctx.read<NetworkGuard>(),
          ),
        ),
      ],
      child: child,
    );
  }
}
