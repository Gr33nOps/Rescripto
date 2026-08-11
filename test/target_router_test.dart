import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/models/processing_mode.dart';
import 'package:rescripto/models/provider_config.dart';
import 'package:rescripto/services/credentials/credential_ref.dart';
import 'package:rescripto/services/credentials/credential_store.dart';
import 'package:rescripto/services/db/app_database.dart';
import 'package:rescripto/services/network/network_feature.dart';
import 'package:rescripto/services/network/network_policy.dart';
import 'package:rescripto/services/providers/provider_registry.dart';
import 'package:rescripto/services/providers/provider_store.dart';
import 'package:rescripto/services/routing/target_router.dart';
import 'package:rescripto/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_secure_storage.dart';

void main() {
  late Directory tempDir;
  late AppDatabase database;
  late SettingsService settings;
  late ProviderRegistry providerRegistry;
  late NetworkPolicy networkPolicy;
  bool localInstalled = true;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('rescripto_target_router');
    database = AppDatabase(path: '${tempDir.path}${Platform.pathSeparator}test.db');
    SharedPreferences.setMockInitialValues({});
    settings = SettingsService();
    await settings.init();
    providerRegistry = ProviderRegistry(
      ProviderStore(database, CredentialStore(database, storage: FakeSecureStorage())),
    );
    await providerRegistry.load();
    networkPolicy = NetworkPolicy();
    await networkPolicy.init();
    localInstalled = true;
  });

  tearDown(() async {
    await database.close();
    tempDir.deleteSync(recursive: true);
  });

  TargetRouter router() => TargetRouter(
    settings: settings,
    providerRegistry: providerRegistry,
    networkPolicy: networkPolicy,
    isLocalModelInstalled: () => localInstalled,
  );

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
    return config;
  }

  group('TargetRouter — Local mode', () {
    test('routes to the local engine when the model is installed', () async {
      await settings.setProcessingMode(ProcessingMode.local);
      final decision = router().route(inputLength: 10);
      expect(decision.isBlocked, isFalse);
      expect(decision.target!.engineId, 'local.llama');
      expect(decision.fallback, isNull);
    });

    test('blocks with noLocalModel when nothing is installed', () async {
      await settings.setProcessingMode(ProcessingMode.local);
      localInstalled = false;
      final decision = router().route(inputLength: 10);
      expect(decision.isBlocked, isTrue);
      expect(decision.blocker, RoutingBlocker.noLocalModel);
    });
  });

  group('TargetRouter — Cloud mode', () {
    test('blocks with noCloudProvider when policy allows cloud but nothing is configured', () async {
      await settings.setProcessingMode(ProcessingMode.cloud);
      await networkPolicy.setFeatureEnabled(NetworkFeature.cloudRewrite, true);
      final decision = router().route(inputLength: 10);
      expect(decision.isBlocked, isTrue);
      expect(decision.blocker, RoutingBlocker.noCloudProvider);
    });

    test('blocks with cloudDisabledByPolicy when nothing is configured and policy is off', () async {
      await settings.setProcessingMode(ProcessingMode.cloud);
      // cloudRewrite defaults to false — never explicitly enabled here.
      final decision = router().route(inputLength: 10);
      expect(decision.isBlocked, isTrue);
      expect(decision.blocker, RoutingBlocker.cloudDisabledByPolicy);
    });

    test('routes to the configured provider once one exists', () async {
      await settings.setProcessingMode(ProcessingMode.cloud);
      await networkPolicy.setFeatureEnabled(NetworkFeature.cloudRewrite, true);
      final config = await configureCloudProvider();

      final decision = router().route(inputLength: 10);
      expect(decision.isBlocked, isFalse);
      expect(decision.target!.providerId, config.id);
      expect(decision.target!.engineId, 'cloud.openaiCompatible');
    });

    test('blocks with cloudDisabledByPolicy when a provider exists but policy forbids it', () async {
      await settings.setProcessingMode(ProcessingMode.cloud);
      await configureCloudProvider();
      // cloudRewrite defaults to false — never explicitly enabled here.

      final decision = router().route(inputLength: 10);
      expect(decision.isBlocked, isTrue);
      expect(decision.blocker, RoutingBlocker.cloudDisabledByPolicy);
    });

    test('the kill switch blocks cloud mode even with a configured provider', () async {
      await settings.setProcessingMode(ProcessingMode.cloud);
      await networkPolicy.setFeatureEnabled(NetworkFeature.cloudRewrite, true);
      await configureCloudProvider();
      await networkPolicy.setKillSwitch(true);

      final decision = router().route(inputLength: 10);
      expect(decision.isBlocked, isTrue);
      expect(decision.blocker, RoutingBlocker.cloudDisabledByPolicy);
    });

    test('a disabled provider config does not count as configured', () async {
      await settings.setProcessingMode(ProcessingMode.cloud);
      await networkPolicy.setFeatureEnabled(NetworkFeature.cloudRewrite, true);
      final config = await configureCloudProvider();
      await providerRegistry.setEnabled(config.id, false);

      final decision = router().route(inputLength: 10);
      expect(decision.isBlocked, isTrue);
      expect(decision.blocker, RoutingBlocker.noCloudProvider);
    });
  });

  group('TargetRouter — Hybrid mode', () {
    test('short input prefers local when both are available', () async {
      await settings.setProcessingMode(ProcessingMode.hybrid);
      await networkPolicy.setFeatureEnabled(NetworkFeature.cloudRewrite, true);
      await configureCloudProvider();

      final decision = router().route(inputLength: 100);
      expect(decision.target!.engineId, 'local.llama');
      expect(decision.fallback, isNotNull);
      expect(decision.fallback!.engineId, 'cloud.openaiCompatible');
      expect(decision.reason, contains('local'));
    });

    test('long input prefers cloud when both are available', () async {
      await settings.setProcessingMode(ProcessingMode.hybrid);
      await networkPolicy.setFeatureEnabled(NetworkFeature.cloudRewrite, true);
      await configureCloudProvider();

      final decision = router().route(inputLength: TargetRouter.hybridLengthThreshold + 1);
      expect(decision.target!.engineId, 'cloud.openaiCompatible');
      expect(decision.fallback, isNotNull);
      expect(decision.fallback!.engineId, 'local.llama');
      expect(decision.reason, contains('cloud'));
    });

    test('falls back to local for long input when cloud is not configured', () async {
      await settings.setProcessingMode(ProcessingMode.hybrid);
      final decision = router().route(inputLength: TargetRouter.hybridLengthThreshold + 1);
      expect(decision.target!.engineId, 'local.llama');
      expect(decision.fallback, isNull);
    });

    test('falls back to cloud when local is not installed, regardless of length', () async {
      await settings.setProcessingMode(ProcessingMode.hybrid);
      await networkPolicy.setFeatureEnabled(NetworkFeature.cloudRewrite, true);
      await configureCloudProvider();
      localInstalled = false;

      final decision = router().route(inputLength: 10);
      expect(decision.target!.engineId, 'cloud.openaiCompatible');
      expect(decision.fallback, isNull);
    });

    test('blocks when neither side is available', () async {
      await settings.setProcessingMode(ProcessingMode.hybrid);
      localInstalled = false;

      final decision = router().route(inputLength: 10);
      expect(decision.isBlocked, isTrue);
    });

    test('every decision names which side and why in the reason string', () async {
      await settings.setProcessingMode(ProcessingMode.hybrid);
      final decision = router().route(inputLength: 10);
      expect(decision.reason, isNot('Hybrid'));
      expect(decision.reason.length, greaterThan(8));
    });
  });
}
