import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/engine/engine_capabilities.dart';
import 'package:rescripto/engine/engine_exception.dart';
import 'package:rescripto/engine/engine_registry.dart';
import 'package:rescripto/engine/engine_stage.dart';
import 'package:rescripto/engine/engine_target.dart';
import 'package:rescripto/engine/generation_handle.dart';
import 'package:rescripto/models/processing_mode.dart';
import 'package:rescripto/models/provider_config.dart';
import 'package:rescripto/models/rewrite_output.dart';
import 'package:rescripto/services/config_store.dart';
import 'package:rescripto/services/credentials/credential_ref.dart';
import 'package:rescripto/services/credentials/credential_store.dart';
import 'package:rescripto/services/db/app_database.dart';
import 'package:rescripto/services/network/network_feature.dart';
import 'package:rescripto/services/network/network_policy.dart';
import 'package:rescripto/services/providers/provider_registry.dart';
import 'package:rescripto/services/providers/provider_store.dart';
import 'package:rescripto/services/routing/target_router.dart';
import 'package:rescripto/services/settings_service.dart';
import 'package:rescripto/services/storage_service.dart';
import 'package:rescripto/state/rewrite_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_rewrite_engine.dart';
import 'support/fake_secure_storage.dart';

void main() {
  late Directory tempDir;
  late AppDatabase database;
  late SettingsService settings;
  late StorageService storage;
  late ConfigStore configStore;
  late ProviderRegistry providerRegistry;
  late NetworkPolicy networkPolicy;
  late FakeRewriteEngine localEngine;
  late FakeRewriteEngine cloudEngine;
  late RewriteController controller;
  bool localInstalled = true;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync(
      'rescripto_rewrite_controller',
    );
    database = AppDatabase(
      path: '${tempDir.path}${Platform.pathSeparator}test.db',
    );
    SharedPreferences.setMockInitialValues({});
    settings = SettingsService();
    await settings.init();
    storage = StorageService(database);
    configStore = ConfigStore(database);
    await configStore.load();
    providerRegistry = ProviderRegistry(
      ProviderStore(database, CredentialStore(database, storage: FakeSecureStorage())),
    );
    await providerRegistry.load();
    networkPolicy = NetworkPolicy();
    await networkPolicy.init();
    localInstalled = true;

    // emitStagesSynchronously reproduces LocalLlmEngine's real timing: stage
    // events land before start() returns, before anything has subscribed.
    localEngine = FakeRewriteEngine(id: 'local.llama', emitStagesSynchronously: true);
    cloudEngine = FakeRewriteEngine(
      id: 'cloud.openaiCompatible',
      capabilities: const EngineCapabilities(needsLocalInstall: false, requiresNetwork: true),
    );
    controller = RewriteController(
      registry: EngineRegistry([localEngine, cloudEngine]),
      storage: storage,
      configStore: configStore,
      router: TargetRouter(
        settings: settings,
        providerRegistry: providerRegistry,
        networkPolicy: networkPolicy,
        isLocalModelInstalled: () => localInstalled,
      ),
    );
    controller.setSource('please rewrite this');
  });

  tearDown(() async {
    await database.close();
    tempDir.deleteSync(recursive: true);
  });

  Future<ProviderConfig> configureCloudProvider() async {
    final id = providerRegistry.newConfigId('openai');
    final now = DateTime.now();
    final config = ProviderConfig(
      id: id,
      presetId: 'openai',
      displayName: 'OpenAI',
      credential: CredentialRef(providerId: id, kind: CredentialKind.apiKey),
      createdAt: now,
      updatedAt: now,
    );
    await providerRegistry.save(config);
    await settings.setCloudProviderId(id);
    await settings.setCloudModelRef('gpt-4o');
    await networkPolicy.setFeatureEnabled(NetworkFeature.cloudRewrite, true);
    return config;
  }

  group('StreamGenerationHandle', () {
    test('events emitted before the caller subscribes are still delivered', () async {
      final handle = StreamGenerationHandle(onCancel: () async {});
      handle.emitStage(EngineStage.submitting);
      handle.emitStage(EngineStage.streaming);

      final received = <EngineStage>[];
      final sub = handle.events.listen((event) {
        if (event is StageChanged) received.add(event.stage);
      });

      // Buffered pre-listen events are flushed as scheduled microtasks, one
      // per turn — give that queue a chance to drain before closing the
      // stream, or `complete()` would race its own `close()` ahead of
      // events that were already queued.
      await Future<void>.delayed(Duration.zero);

      handle.complete(const RewriteOutput(text: 'done'));
      await handle.done;
      await sub.cancel();

      expect(received, [EngineStage.submitting, EngineStage.streaming]);
    });
  });

  group('RewriteController.rewrite', () {
    test(
      'stage reaches streaming while running instead of sticking on preparing',
      () async {
        final future = controller.rewrite();

        // A single macrotask boundary flushes every microtask hop in
        // between: engine.prepare()'s await, start()'s synchronous
        // pre-subscribe emits, and the buffered-event delivery to the
        // subscription set up right after. If this were still backed by a
        // broadcast StreamController, those events would already be gone
        // and stage would still read `preparing`.
        await Future<void>.delayed(Duration.zero);

        expect(controller.isRunning, isTrue);
        expect(controller.stage, EngineStage.streaming);

        localEngine.lastHandle!.emitDelta('hello');
        await Future<void>.delayed(Duration.zero);
        expect(controller.streamingText, 'hello');

        localEngine.lastHandle!.complete(const RewriteOutput(text: 'hello there'));
        final result = await future;

        expect(result.primary.text, 'hello there');
        expect(controller.isRunning, isFalse);
      },
    );

    test('surfaces EngineNotAvailableException for an unregistered engine target', () async {
      final orphanController = RewriteController(
        registry: EngineRegistry(const []),
        storage: storage,
        configStore: configStore,
        router: TargetRouter(
          settings: settings,
          providerRegistry: providerRegistry,
          networkPolicy: networkPolicy,
          isLocalModelInstalled: () => true,
        ),
      );
      orphanController.setSource('text');

      await expectLater(
        orphanController.rewrite(),
        throwsA(isA<EngineNotAvailableException>()),
      );
      expect(orphanController.lastError, isNotNull);
    });

    test('capabilities falls back safely instead of throwing during build', () {
      final orphanController = RewriteController(
        registry: EngineRegistry(const []),
        storage: storage,
        configStore: configStore,
        router: TargetRouter(
          settings: settings,
          providerRegistry: providerRegistry,
          networkPolicy: networkPolicy,
          isLocalModelInstalled: () => true,
        ),
      );
      expect(
        orphanController.capabilities,
        const EngineCapabilities(needsLocalInstall: false, requiresNetwork: false),
      );
    });

    test('throws EngineNotAvailableException immediately when routing is blocked', () async {
      localInstalled = false; // local mode (the default), nothing installed
      await expectLater(controller.rewrite(), throwsA(isA<EngineNotAvailableException>()));
    });
  });

  group('RewriteController — Hybrid fallback', () {
    test('a local failure before any text offers a cloud fallback that needs consent', () async {
      await settings.setProcessingMode(ProcessingMode.hybrid);
      await configureCloudProvider();
      controller.setSource('short input, routes to local first');

      localEngine.prepareError = const ModelLoadFailedException('boom');
      await expectLater(controller.rewrite(), throwsA(isA<ModelLoadFailedException>()));

      expect(controller.pendingFallback, isNotNull);
      expect(controller.pendingFallback!.engineId, 'cloud.openaiCompatible');
      expect(controller.pendingFallbackNeedsConsent, isTrue);
    });

    test('retryWithFallback runs the same request against the fallback target', () async {
      await settings.setProcessingMode(ProcessingMode.hybrid);
      await configureCloudProvider();
      controller.setSource('short input, routes to local first');

      localEngine.prepareError = const ModelLoadFailedException('boom');
      await expectLater(controller.rewrite(), throwsA(isA<ModelLoadFailedException>()));

      final future = controller.retryWithFallback();
      await Future<void>.delayed(Duration.zero);
      cloudEngine.lastHandle!.complete(const RewriteOutput(text: 'from the cloud'));
      final result = await future;

      expect(result.primary.text, 'from the cloud');
      expect(controller.pendingFallback, isNull);
    });

    test('a cloud failure before any text falls back to local without needing consent', () async {
      await settings.setProcessingMode(ProcessingMode.hybrid);
      await configureCloudProvider();
      // Long input routes to cloud first in Hybrid mode.
      controller.setSource('x' * (TargetRouter.hybridLengthThreshold + 10));

      cloudEngine.prepareError = const ProviderUnavailableException(503);
      await expectLater(controller.rewrite(), throwsA(isA<ProviderUnavailableException>()));

      expect(controller.pendingFallback, isNotNull);
      expect(controller.pendingFallback!.engineId, 'local.llama');
      expect(controller.pendingFallbackNeedsConsent, isFalse);
    });

    test('no fallback is offered once a token has already streamed to the screen', () async {
      await settings.setProcessingMode(ProcessingMode.hybrid);
      await configureCloudProvider();
      controller.setSource('short input, routes to local first');

      final future = controller.rewrite();
      await Future<void>.delayed(Duration.zero);
      localEngine.lastHandle!.emitDelta('partial');
      await Future<void>.delayed(Duration.zero);
      localEngine.lastHandle!.completeError(const UnknownEngineException());

      await expectLater(future, throwsA(isA<UnknownEngineException>()));
      expect(controller.pendingFallback, isNull);
    });

    test('no fallback is offered for a provider auth failure', () async {
      await settings.setProcessingMode(ProcessingMode.hybrid);
      final config = await configureCloudProvider();
      controller.setSource('x' * (TargetRouter.hybridLengthThreshold + 10));

      cloudEngine.prepareError = ProviderAuthException(config.id);
      await expectLater(controller.rewrite(), throwsA(isA<ProviderAuthException>()));

      expect(controller.pendingFallback, isNull);
    });

    test('dismissFallback clears the pending offer without running anything', () async {
      await settings.setProcessingMode(ProcessingMode.hybrid);
      await configureCloudProvider();
      controller.setSource('short input, routes to local first');

      localEngine.prepareError = const ModelLoadFailedException('boom');
      await expectLater(controller.rewrite(), throwsA(isA<ModelLoadFailedException>()));
      expect(controller.pendingFallback, isNotNull);

      controller.dismissFallback();
      expect(controller.pendingFallback, isNull);

      await expectLater(
        controller.retryWithFallback(),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('EngineTarget', () {
    test('equality and hashCode include providerId', () {
      const a = EngineTarget(engineId: 'cloud.openaiCompatible', modelRef: 'gpt', providerId: 'openai');
      const b = EngineTarget(engineId: 'cloud.openaiCompatible', modelRef: 'gpt', providerId: 'openai');
      const c = EngineTarget(engineId: 'cloud.openaiCompatible', modelRef: 'gpt', providerId: 'groq');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}
