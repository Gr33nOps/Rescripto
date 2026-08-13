import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/engine/active_request_registry.dart';
import 'package:rescripto/engine/engine_capabilities.dart';
import 'package:rescripto/engine/engine_exception.dart';
import 'package:rescripto/engine/engine_registry.dart';
import 'package:rescripto/engine/engine_stage.dart';
import 'package:rescripto/engine/engine_target.dart';
import 'package:rescripto/engine/generation_handle.dart';
import 'package:rescripto/models/audience_tag.dart';
import 'package:rescripto/models/processing_mode.dart';
import 'package:rescripto/models/provider_config.dart';
import 'package:rescripto/models/rewrite_output.dart';
import 'package:rescripto/models/rewrite_request.dart';
import 'package:rescripto/services/config_store.dart';
import 'package:rescripto/services/credentials/credential_ref.dart';
import 'package:rescripto/services/credentials/credential_store.dart';
import 'package:rescripto/services/db/app_database.dart';
import 'package:rescripto/services/network/network_feature.dart';
import 'package:rescripto/services/network/network_log.dart';
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
  late ActiveRequestRegistry activeRequests;
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
    activeRequests = ActiveRequestRegistry();
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
      activeRequests: activeRequests,
      networkLog: NetworkLog(database),
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
        activeRequests: ActiveRequestRegistry(),
        networkLog: NetworkLog(database),
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
        activeRequests: ActiveRequestRegistry(),
        networkLog: NetworkLog(database),
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

    test('the prompt carries the audience\'s current label, resolved from the id — the id/label bug fix', () async {
      // Renaming a built-in after it's been selected must not orphan the
      // selection: RewriteRequest.audience holds ids, and the label is
      // resolved fresh at rewrite time via ConfigStore.audienceById.
      await configStore.upsertAudience(
        const AudienceTag(id: 'coworkers', label: 'my new team name'),
      );
      controller.toggleAudience('coworkers');

      final future = controller.rewrite();
      await Future<void>.delayed(Duration.zero);
      localEngine.lastHandle!.complete(const RewriteOutput(text: 'done'));
      await future;

      final promptSystem = localEngine.lastRequest!.prompt.system;
      expect(promptSystem, contains('my new team name'));
      expect(promptSystem, isNot(contains('coworkers')));
    });
  });

  group('RewriteController — ActiveRequestRegistry', () {
    test('registers the handle while running and unregisters once done', () async {
      final future = controller.rewrite();
      await Future<void>.delayed(Duration.zero);

      expect(activeRequests.activeCount, 1);

      localEngine.lastHandle!.complete(const RewriteOutput(text: 'done'));
      await future;

      expect(activeRequests.activeCount, 0);
    });

    test('cancelling through the registry reaches the handle, the way the kill switch needs to', () async {
      final future = controller.rewrite();
      await Future<void>.delayed(Duration.zero);
      expect(activeRequests.activeCount, 1);
      final handle = localEngine.lastHandle!;

      await activeRequests.cancelAll();

      expect(handle.isCancelled, isTrue);
      expect(localEngine.cancelRequested, isTrue);

      // A real engine notices isCancelled and completes the handle itself
      // (see LocalLlmEngine._run); the fake needs the same nudge to let the
      // rewrite() future — and this test — finish cleanly.
      handle.completeError(const GenerationCancelledException());
      final result = await future;
      expect(result.outputs, isEmpty);
      expect(activeRequests.activeCount, 0);
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

  group('RewriteController — Simple/Pro pinning', () {
    test('enterSimpleMode pins Pro-surface fields to their defaults', () {
      controller.setIntensity(RewriteIntensity.full);
      controller.setLength(RewriteLength.longer);
      controller.toggleAudience('coworkers');
      controller.setCustomInstruction('be terse');
      controller.setVariantCount(3);

      controller.enterSimpleMode();

      expect(controller.intensity, RewriteIntensity.moderate);
      expect(controller.length, RewriteLength.same);
      expect(controller.audience, isEmpty);
      expect(controller.customInstruction, '');
      expect(controller.variantCount, 1);
    });

    test('enterProMode restores exactly what enterSimpleMode pinned over', () {
      controller.setIntensity(RewriteIntensity.full);
      controller.setLength(RewriteLength.longer);
      controller.toggleAudience('coworkers');
      controller.setCustomInstruction('be terse');
      controller.setVariantCount(3);

      controller.enterSimpleMode();
      controller.enterProMode();

      expect(controller.intensity, RewriteIntensity.full);
      expect(controller.length, RewriteLength.longer);
      expect(controller.audience, ['coworkers']);
      expect(controller.customInstruction, 'be terse');
      expect(controller.variantCount, 3);
    });

    test('enterProMode with nothing pinned is a harmless no-op', () {
      controller.enterProMode();
      expect(controller.intensity, RewriteIntensity.moderate);
      expect(controller.variantCount, 1);
    });

    test('a value set while in Simple mode does not leak into the restored Pro values', () {
      controller.setVariantCount(3);
      controller.enterSimpleMode();

      // Simple mode's own controls (tone, source text) stay live; nothing
      // pinned should react to them.
      controller.setTone('casual');

      controller.enterProMode();
      expect(controller.variantCount, 3);
      expect(controller.toneId, 'casual');
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
