import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/models/provider_config.dart';
import 'package:rescripto/services/credentials/credential_ref.dart';
import 'package:rescripto/services/credentials/credential_store.dart';
import 'package:rescripto/services/db/app_database.dart';
import 'package:rescripto/services/providers/provider_registry.dart';
import 'package:rescripto/services/providers/provider_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_secure_storage.dart';

void main() {
  late Directory tempDir;
  late AppDatabase database;
  late FakeSecureStorage secureStorage;
  late CredentialStore credentialStore;
  late ProviderRegistry registry;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('rescripto_provider_registry');
    database = AppDatabase(path: '${tempDir.path}${Platform.pathSeparator}test.db');
    secureStorage = FakeSecureStorage();
    credentialStore = CredentialStore(database, storage: secureStorage);
    registry = ProviderRegistry(ProviderStore(database, credentialStore));
    await registry.load();
  });

  tearDown(() async {
    await database.close();
    tempDir.deleteSync(recursive: true);
  });

  ProviderConfig buildConfig(String presetId) {
    final id = registry.newConfigId(presetId);
    final now = DateTime.now();
    return ProviderConfig(
      id: id,
      presetId: presetId,
      displayName: presetId,
      credential: CredentialRef(providerId: id, kind: CredentialKind.apiKey),
      createdAt: now,
      updatedAt: now,
    );
  }

  group('ProviderRegistry.load', () {
    test('starts empty and marks isLoaded', () {
      expect(registry.configs, isEmpty);
      expect(registry.isLoaded, isTrue);
    });
  });

  group('ProviderRegistry.save', () {
    test('persists a config and reflects it immediately in the cache', () async {
      final config = buildConfig('openai');
      await registry.save(config);

      expect(registry.configs, hasLength(1));
      expect(registry.byId(config.id)?.displayName, 'openai');
    });

    test('survives a reload from a fresh registry over the same database', () async {
      final config = buildConfig('anthropic');
      await registry.save(config);

      final reopened = ProviderRegistry(ProviderStore(database, credentialStore));
      await reopened.load();

      expect(reopened.configs, hasLength(1));
      expect(reopened.byId(config.id)?.presetId, 'anthropic');
    });

    test('round-trips the model list through provider_model', () async {
      final config = buildConfig('ollama').copyWith(
        models: const [ProviderModelEntry(modelRef: 'llama3.3', displayName: 'Llama 3.3')],
      );
      await registry.save(config);

      final reloaded = registry.byId(config.id)!;
      expect(reloaded.models, [
        const ProviderModelEntry(modelRef: 'llama3.3', displayName: 'Llama 3.3'),
      ]);
    });

    test('rejects extra headers that look like credentials before writing anything', () async {
      final config = buildConfig('openrouter').copyWith(
        extraHeaders: const {'Authorization': 'Bearer nope'},
      );
      await expectLater(registry.save(config), throwsArgumentError);
      expect(registry.configs, isEmpty);
    });
  });

  group('ProviderRegistry.delete', () {
    test('removes the config and its credential together', () async {
      final config = buildConfig('openai');
      await registry.save(config);
      await credentialStore.write(config.credential, 'sk-test-key');
      expect(await credentialStore.has(config.credential), isTrue);

      await registry.delete(config.id);

      expect(registry.byId(config.id), isNull);
      expect(
        await credentialStore.has(config.credential),
        isFalse,
        reason: 'SQLite CASCADE cannot reach the Keystore — ProviderStore.delete must',
      );
    });

    test('a delete for an unknown id is a harmless no-op', () async {
      await registry.delete('does-not-exist');
      expect(registry.configs, isEmpty);
    });
  });

  group('ProviderRegistry.setEnabled / disableAll', () {
    test('setEnabled toggles a single provider without touching others', () async {
      final a = buildConfig('openai');
      final b = buildConfig('anthropic');
      await registry.save(a);
      await registry.save(b);

      await registry.setEnabled(a.id, false);

      expect(registry.byId(a.id)!.enabled, isFalse);
      expect(registry.byId(b.id)!.enabled, isTrue);
      expect(registry.enabledConfigs.map((c) => c.id), [b.id]);
    });

    test('disableAll turns off every enabled provider and leaves credentials intact', () async {
      final a = buildConfig('openai');
      final b = buildConfig('anthropic');
      await registry.save(a);
      await registry.save(b);
      await credentialStore.write(a.credential, 'sk-a');
      await credentialStore.write(b.credential, 'sk-b');

      await registry.disableAll();

      expect(registry.enabledConfigs, isEmpty);
      expect(await credentialStore.has(a.credential), isTrue);
      expect(await credentialStore.has(b.credential), isTrue);
    });
  });
}
