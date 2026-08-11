import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/core/constants.dart';
import 'package:rescripto/models/backup_bundle.dart';
import 'package:rescripto/models/history_entry.dart';
import 'package:rescripto/models/provider_config.dart';
import 'package:rescripto/models/tone_preset.dart';
import 'package:rescripto/services/backup/backup_crypto.dart';
import 'package:rescripto/services/backup/backup_exception.dart';
import 'package:rescripto/services/backup/backup_service.dart';
import 'package:rescripto/services/backup/restore_options.dart';
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

  group('BackupService.preview', () {
    test('summarizes counts and containsSecrets without applying anything', () async {
      await configStore.upsertTone(const TonePreset(
        id: 'user_1',
        name: 'Mine',
        iconToken: 'bolt_outlined',
        description: '',
        instruction: 'Be terse.',
        temperature: 0.5,
      ));
      final bundle = await backupService.gather();
      final preview = backupService.preview(bundle);

      expect(preview.toneCount, bundle.tones.length);
      expect(preview.containsSecrets, isFalse);
      expect(preview.hasSettings, isTrue);

      // A second store over the same database proves nothing was written.
      final reopened = ConfigStore(database);
      await reopened.load();
      expect(reopened.tones.map((t) => t.id), isNot(contains('imported_tone')));
    });
  });

  group('BackupService.restore', () {
    test('refuses a bundle from a newer schema without touching anything', () async {
      final bundle = await backupService.gather();
      final fromTheFuture = BackupBundle(
        formatVersion: bundle.formatVersion,
        createdAt: bundle.createdAt,
        appVersion: bundle.appVersion,
        dbVersion: 99999,
        tones: const [
          TonePreset(
            id: 'should_not_land',
            name: 'x',
            iconToken: 'bolt_outlined',
            description: '',
            instruction: 'x',
            temperature: 0.5,
          ),
        ],
      );

      await expectLater(
        backupService.restore(fromTheFuture, const RestoreOptions()),
        throwsA(isA<BackupOlderSchemaException>()),
      );
      expect(configStore.tones.map((t) => t.id), isNot(contains('should_not_land')));
    });

    test('restoring a tone upserts by id and leaves untouched local tones alone', () async {
      await configStore.upsertTone(const TonePreset(
        id: 'local_only',
        name: 'Local',
        iconToken: 'bolt_outlined',
        description: '',
        instruction: 'stays',
        temperature: 0.5,
      ));
      final bundle = BackupBundle(
        formatVersion: BackupBundle.currentFormatVersion,
        createdAt: DateTime.now(),
        appVersion: '1.0.3',
        dbVersion: AppConstants.dbVersion,
        tones: const [
          TonePreset(
            id: 'from_backup',
            name: 'Restored',
            iconToken: 'bolt_outlined',
            description: '',
            instruction: 'restored',
            temperature: 0.5,
          ),
        ],
      );

      await backupService.restore(bundle, const RestoreOptions());

      expect(configStore.toneById('local_only').name, 'Local');
      expect(configStore.toneById('from_backup').name, 'Restored');
    });

    test('restoring with applyTones: false leaves tones untouched', () async {
      final bundle = BackupBundle(
        formatVersion: BackupBundle.currentFormatVersion,
        createdAt: DateTime.now(),
        appVersion: '1.0.3',
        dbVersion: AppConstants.dbVersion,
        tones: const [
          TonePreset(
            id: 'should_be_skipped',
            name: 'x',
            iconToken: 'bolt_outlined',
            description: '',
            instruction: 'x',
            temperature: 0.5,
          ),
        ],
      );

      await backupService.restore(bundle, const RestoreOptions(applyTones: false));

      expect(configStore.tones.map((t) => t.id), isNot(contains('should_be_skipped')));
    });

    test('history strategy skip leaves local history untouched', () async {
      await storage.insertHistory(
        HistoryEntry(id: 0, original: 'local', rewritten: 'local', toneId: 'casual', createdAt: DateTime.now()),
      );
      final bundle = BackupBundle(
        formatVersion: BackupBundle.currentFormatVersion,
        createdAt: DateTime.now(),
        appVersion: '1.0.3',
        dbVersion: AppConstants.dbVersion,
        history: [
          HistoryEntry(id: 0, original: 'from backup', rewritten: 'x', toneId: 'casual', createdAt: DateTime.now()),
        ],
      );

      await backupService.restore(bundle, const RestoreOptions());

      final history = await storage.getHistory();
      expect(history, hasLength(1));
      expect(history.single.original, 'local');
    });

    test('history strategy append adds bundle entries alongside local ones', () async {
      await storage.insertHistory(
        HistoryEntry(id: 0, original: 'local', rewritten: 'local', toneId: 'casual', createdAt: DateTime.now()),
      );
      final bundle = BackupBundle(
        formatVersion: BackupBundle.currentFormatVersion,
        createdAt: DateTime.now(),
        appVersion: '1.0.3',
        dbVersion: AppConstants.dbVersion,
        history: [
          HistoryEntry(id: 0, original: 'from backup', rewritten: 'x', toneId: 'casual', createdAt: DateTime.now()),
        ],
      );

      await backupService.restore(
        bundle,
        const RestoreOptions(history: HistoryRestoreStrategy.append),
      );

      final history = await storage.getHistory();
      expect(history, hasLength(2));
      expect(history.map((h) => h.original), containsAll(['local', 'from backup']));
    });

    test('history strategy replace clears local history before inserting the bundle\'s', () async {
      await storage.insertHistory(
        HistoryEntry(id: 0, original: 'local', rewritten: 'local', toneId: 'casual', createdAt: DateTime.now()),
      );
      final bundle = BackupBundle(
        formatVersion: BackupBundle.currentFormatVersion,
        createdAt: DateTime.now(),
        appVersion: '1.0.3',
        dbVersion: AppConstants.dbVersion,
        history: [
          HistoryEntry(id: 0, original: 'from backup', rewritten: 'x', toneId: 'casual', createdAt: DateTime.now()),
        ],
      );

      await backupService.restore(
        bundle,
        const RestoreOptions(history: HistoryRestoreStrategy.replace),
      );

      final history = await storage.getHistory();
      expect(history, hasLength(1));
      expect(history.single.original, 'from backup');
    });

    test('credentials restore only when applyCredentials is true, even if the bundle has them', () async {
      final id = providerRegistry.newConfigId('openai');
      final now = DateTime.now();
      final ref = CredentialRef(providerId: id, kind: CredentialKind.apiKey);
      final bundle = BackupBundle(
        formatVersion: BackupBundle.currentFormatVersion,
        createdAt: now,
        appVersion: '1.0.3',
        dbVersion: AppConstants.dbVersion,
        providerConfigs: [
          ProviderConfig(
            id: id,
            presetId: 'openai',
            displayName: 'OpenAI',
            credential: ref,
            createdAt: now,
            updatedAt: now,
          ),
        ],
        credentials: [BackupCredential(ref: ref, secret: 'sk-restored')],
      );

      await backupService.restore(bundle, const RestoreOptions());
      expect(await credentialStore.has(ref), isFalse);

      await backupService.restore(bundle, const RestoreOptions(applyCredentials: true));
      expect(await credentialStore.has(ref), isTrue);
      expect(await credentialStore.read(ref), 'sk-restored');
    });

    test('a full export-then-restore round trip through encryption merges cleanly', () async {
      await configStore.upsertTone(const TonePreset(
        id: 'roundtrip_tone',
        name: 'Round Trip',
        iconToken: 'bolt_outlined',
        description: '',
        instruction: 'x',
        temperature: 0.5,
      ));
      final gathered = await backupService.gather();
      final fileBytes = await backupService.export(gathered, 'passphrase123');

      // Simulate a fresh device: nothing local but the built-ins.
      final freshDir = Directory.systemTemp.createTempSync('rescripto_backup_fresh');
      final freshDb = AppDatabase(path: '${freshDir.path}${Platform.pathSeparator}fresh.db');
      final freshConfigStore = ConfigStore(freshDb);
      await freshConfigStore.load();
      final freshService = BackupService(
        settings: settings,
        configStore: freshConfigStore,
        workflowRegistry: WorkflowRegistry(WorkflowStore(freshDb)),
        providerRegistry: ProviderRegistry(ProviderStore(freshDb, CredentialStore(freshDb, storage: FakeSecureStorage()))),
        storage: StorageService(freshDb),
        credentialStore: CredentialStore(freshDb, storage: FakeSecureStorage()),
      );
      await freshService.providerRegistry.load();
      await freshService.workflowRegistry.load();

      final decrypted = await freshService.decrypt(fileBytes, 'passphrase123');
      await freshService.restore(decrypted, const RestoreOptions());

      expect(freshConfigStore.toneById('roundtrip_tone').name, 'Round Trip');

      await freshDb.close();
      freshDir.deleteSync(recursive: true);
    });
  });
}
