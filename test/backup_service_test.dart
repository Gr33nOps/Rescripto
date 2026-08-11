import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/models/backup_bundle.dart';
import 'package:rescripto/models/history_entry.dart';
import 'package:rescripto/models/provider_config.dart';
import 'package:rescripto/models/tone_preset.dart';
import 'package:rescripto/services/backup/backup_crypto.dart';
import 'package:rescripto/services/backup/backup_exception.dart';
import 'package:rescripto/services/backup/backup_service.dart';
import 'package:rescripto/services/config_store.dart';
import 'package:rescripto/services/credentials/credential_ref.dart';
import 'package:rescripto/services/credentials/credential_store.dart';
import 'package:rescripto/services/db/app_database.dart';
import 'package:rescripto/services/providers/provider_registry.dart';
import 'package:rescripto/services/providers/provider_store.dart';
import 'package:rescripto/services/settings_service.dart';
import 'package:rescripto/services/storage_service.dart';
import 'package:rescripto/services/workflows/workflow_registry.dart';
import 'package:rescripto/services/workflows/workflow_store.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_secure_storage.dart';

void main() {
  late Directory tempDir;
  late AppDatabase database;
  late SettingsService settings;
  late ConfigStore configStore;
  late WorkflowRegistry workflowRegistry;
  late ProviderRegistry providerRegistry;
  late CredentialStore credentialStore;
  late StorageService storage;
  late BackupService backupService;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('rescripto_backup_service');
    database = AppDatabase(path: '${tempDir.path}${Platform.pathSeparator}test.db');
    SharedPreferences.setMockInitialValues({});
    settings = SettingsService();
    await settings.init();
    configStore = ConfigStore(database);
    await configStore.load();
    workflowRegistry = WorkflowRegistry(WorkflowStore(database));
    await workflowRegistry.load();
    credentialStore = CredentialStore(database, storage: FakeSecureStorage());
    providerRegistry = ProviderRegistry(ProviderStore(database, credentialStore));
    await providerRegistry.load();
    storage = StorageService(database);
    backupService = BackupService(
      settings: settings,
      configStore: configStore,
      workflowRegistry: workflowRegistry,
      providerRegistry: providerRegistry,
      storage: storage,
      credentialStore: credentialStore,
    );
  });

  tearDown(() async {
    await database.close();
    tempDir.deleteSync(recursive: true);
  });

  group('BackupService.gather', () {
    test('captures every built-in tone and audience by default', () async {
      final bundle = await backupService.gather();
      expect(bundle.tones.length, configStore.tones.length);
      expect(bundle.audiences.length, configStore.audiences.length);
    });

    test('history is empty unless includeHistory is passed', () async {
      await storage.insertHistory(
        HistoryEntry(id: 0, original: 'a', rewritten: 'b', toneId: 'casual', createdAt: DateTime.now()),
      );

      final withoutHistory = await backupService.gather();
      expect(withoutHistory.history, isEmpty);

      final withHistory = await backupService.gather(includeHistory: true);
      expect(withHistory.history, hasLength(1));
    });

    test('credentials are empty unless includeCredentials is passed, even if configured', () async {
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
      await credentialStore.write(config.credential, 'sk-test');

      final withoutCredentials = await backupService.gather();
      expect(withoutCredentials.containsSecrets, isFalse);
      // The provider config itself (id/preset/displayName) is always
      // included — it carries no secret, only a CredentialRef.
      expect(withoutCredentials.providerConfigs, hasLength(1));

      final withCredentials = await backupService.gather(includeCredentials: true);
      expect(withCredentials.containsSecrets, isTrue);
      expect(withCredentials.credentials.single.secret, 'sk-test');
    });

    test('picks up a user-created tone', () async {
      await configStore.upsertTone(const TonePreset(
        id: 'user_1',
        name: 'Mine',
        iconToken: 'bolt_outlined',
        description: '',
        instruction: 'Be terse.',
        temperature: 0.5,
      ));

      final bundle = await backupService.gather();
      expect(bundle.tones.map((t) => t.id), contains('user_1'));
    });
  });

  group('BackupService.export / decrypt', () {
    test('round-trips a gathered bundle through encryption', () async {
      final bundle = await backupService.gather();
      final fileBytes = await backupService.export(bundle, 'a strong passphrase');

      final decrypted = await backupService.decrypt(fileBytes, 'a strong passphrase');
      expect(decrypted.dbVersion, bundle.dbVersion);
      expect(decrypted.tones.length, bundle.tones.length);
    });

    test('the wrong passphrase is rejected', () async {
      final bundle = await backupService.gather();
      final fileBytes = await backupService.export(bundle, 'correct passphrase');

      await expectLater(
        backupService.decrypt(fileBytes, 'wrong passphrase'),
        throwsA(isA<BackupWrongPassphraseException>()),
      );
    });

    test('a bundle from a newer format version is refused, not guessed at', () async {
      final bundle = await backupService.gather();
      final json = {...bundle.toJson(), 'format_version': BackupBundle.currentFormatVersion + 1};
      final fileBytes = await BackupCrypto().encrypt(
        Uint8List.fromList(utf8.encode(jsonEncode(json))),
        'passphrase',
      );

      await expectLater(
        backupService.decrypt(fileBytes, 'passphrase'),
        throwsA(isA<BackupNewerFormatException>()),
      );
    });
  });

  group('BackupService.suggestedFileName', () {
    test('is sortable by name and carries the .rescriptobackup extension', () {
      final name = BackupService.suggestedFileName(DateTime(2026, 3, 5, 9, 7));
      expect(name, 'rescripto-backup-20260305-0907.rescriptobackup');
    });
  });
}
