import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../engine/active_request_registry.dart';
import '../engine/cloud/anthropic_protocol.dart';
import '../engine/cloud/cloud_rewrite_engine.dart';
import '../engine/cloud/gemini_protocol.dart';
import '../engine/cloud/openai_compatible_protocol.dart';
import '../engine/engine_registry.dart';
import '../engine/local/local_engine_host.dart';
import '../engine/local/local_llm_engine.dart';
import '../engine/workflow_runner.dart';
import '../services/backup/backup_scheduler.dart';
import '../services/backup/backup_service.dart';
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
import '../services/providers/provider_registry.dart';
import '../services/providers/provider_store.dart';
import '../services/routing/target_router.dart';
import '../services/settings_service.dart';
import '../services/share_intent_bridge.dart';
import '../services/speech_service.dart';
import '../services/storage_service.dart';
import '../services/sync/sync_service.dart';
import '../services/workflows/workflow_registry.dart';
import '../services/workflows/workflow_store.dart';
import '../speech/speech_engine_resolver.dart';
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
    required this.credentialStore,
    required this.providerRegistry,
    required this.workflowRegistry,
    required this.networkPolicy,
    required this.child,
  });

  final SettingsService settings;
  final AppDatabase database;
  final ConfigStore configStore;
  final CredentialStore credentialStore;
  final ProviderRegistry providerRegistry;
  final WorkflowRegistry workflowRegistry;
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
        // Built before runApp (see main.dart) so ProviderStore's deletes can
        // always reach a CredentialStore backed by the same connection.
        Provider<CredentialStore>.value(value: credentialStore),
        ChangeNotifierProvider<ProviderRegistry>.value(value: providerRegistry),
        Provider<ProviderStore>(
          create: (ctx) =>
              ProviderStore(ctx.read<AppDatabase>(), ctx.read<CredentialStore>()),
        ),
        // Built before runApp too, same reasoning as ProviderRegistry above.
        ChangeNotifierProvider<WorkflowRegistry>.value(value: workflowRegistry),
        Provider<WorkflowStore>(
          create: (ctx) => WorkflowStore(ctx.read<AppDatabase>()),
        ),
        // One instance for the whole app — every RewriteController rewrite
        // registers into it, and PanicService's kill switch cancels
        // whatever's in it.
        Provider<ActiveRequestRegistry>(create: (_) => ActiveRequestRegistry()),
        Provider<PanicService>(
          create: (ctx) => PanicService(
            ctx.read<CredentialStore>(),
            ctx.read<NetworkPolicy>(),
            ctx.read<ProviderRegistry>(),
            ctx.read<ActiveRequestRegistry>(),
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
            CloudRewriteEngine(
              'cloud.openaiCompatible',
              const OpenAiCompatibleProtocol(),
              ctx.read<ProviderRegistry>(),
              ctx.read<CredentialStore>(),
              ctx.read<NetworkGuard>(),
            ),
            CloudRewriteEngine(
              'cloud.anthropic',
              const AnthropicProtocol(),
              ctx.read<ProviderRegistry>(),
              ctx.read<CredentialStore>(),
              ctx.read<NetworkGuard>(),
            ),
            CloudRewriteEngine(
              'cloud.gemini',
              const GeminiProtocol(),
              ctx.read<ProviderRegistry>(),
              ctx.read<CredentialStore>(),
              ctx.read<NetworkGuard>(),
            ),
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
        // Shared rather than built inline per-controller: the workflow
        // editor needs "wherever a rewrite would currently route to" too,
        // for a new step's default target.
        Provider<TargetRouter>(
          create: (ctx) => TargetRouter(
            settings: ctx.read<SettingsService>(),
            providerRegistry: ctx.read<ProviderRegistry>(),
            networkPolicy: ctx.read<NetworkPolicy>(),
            isLocalModelInstalled: () => ctx
                .read<ModelsController>()
                .isInstalled(ctx.read<SettingsService>().selectedModelId),
          ),
        ),
        ChangeNotifierProvider<RewriteController>(
          create: (ctx) => RewriteController(
            registry: ctx.read<EngineRegistry>(),
            storage: ctx.read<StorageService>(),
            configStore: ctx.read<ConfigStore>(),
            router: ctx.read<TargetRouter>(),
            activeRequests: ctx.read<ActiveRequestRegistry>(),
          ),
        ),
        ChangeNotifierProvider<WorkflowRunner>(
          create: (ctx) => WorkflowRunner(
            registry: ctx.read<EngineRegistry>(),
            configStore: ctx.read<ConfigStore>(),
            storage: ctx.read<StorageService>(),
            activeRequests: ctx.read<ActiveRequestRegistry>(),
          ),
        ),
        Provider<BackupService>(
          create: (ctx) => BackupService(
            settings: ctx.read<SettingsService>(),
            configStore: ctx.read<ConfigStore>(),
            workflowRegistry: ctx.read<WorkflowRegistry>(),
            providerRegistry: ctx.read<ProviderRegistry>(),
            storage: ctx.read<StorageService>(),
            credentialStore: ctx.read<CredentialStore>(),
          ),
        ),
        Provider<BackupScheduler>(
          create: (ctx) => BackupScheduler(
            settings: ctx.read<SettingsService>(),
            backupService: ctx.read<BackupService>(),
            credentialStore: ctx.read<CredentialStore>(),
          ),
        ),
        Provider<SyncService>(
          create: (ctx) => SyncService.withGuard(
            settings: ctx.read<SettingsService>(),
            backupService: ctx.read<BackupService>(),
            credentialStore: ctx.read<CredentialStore>(),
            networkGuard: ctx.read<NetworkGuard>(),
          ),
        ),
        ChangeNotifierProvider<HistoryController>(
          create: (ctx) => HistoryController(ctx.read<StorageService>()),
        ),
        Provider<SpeechEngineResolver>(
          create: (ctx) => SpeechEngineResolver(
            settings: ctx.read<SettingsService>(),
            speechService: ctx.read<SpeechService>(),
            providerRegistry: ctx.read<ProviderRegistry>(),
            credentialStore: ctx.read<CredentialStore>(),
            networkGuard: ctx.read<NetworkGuard>(),
          ),
        ),
        ChangeNotifierProvider<SpeechController>(
          create: (ctx) => SpeechController(
            ctx.read<SpeechService>(),
            ctx.read<SettingsService>(),
            ctx.read<SpeechEngineResolver>(),
          ),
        ),
        // One instance for the app's lifetime — it starts listening for the
        // platform channel the moment it's constructed, so the very first
        // frame is never too late to catch a cold-launch PROCESS_TEXT/SEND
        // intent.
        ChangeNotifierProvider<ShareIntentBridge>(create: (_) => ShareIntentBridge()),
      ],
      child: child,
    );
  }
}
