import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/services/backup/backup_scheduler.dart';
import 'package:rescripto/services/backup/backup_service.dart';
import 'package:rescripto/services/config_store.dart';
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
  late Directory backupsDir;
  late AppDatabase database;
  late SettingsService settings;
  late CredentialStore credentialStore;
  late BackupScheduler scheduler;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('rescripto_backup_scheduler');
    backupsDir = Directory('${tempDir.path}${Platform.pathSeparator}backups');
    database = AppDatabase(path: '${tempDir.path}${Platform.pathSeparator}test.db');
    SharedPreferences.setMockInitialValues({});
    settings = SettingsService();
    await settings.init();
    credentialStore = CredentialStore(database, storage: FakeSecureStorage());
    final configStore = ConfigStore(database);
    await configStore.load();
    final workflowRegistry = WorkflowRegistry(WorkflowStore(database));
    await workflowRegistry.load();
    final providerRegistry = ProviderRegistry(ProviderStore(database, credentialStore));
    await providerRegistry.load();

    scheduler = BackupScheduler(
      settings: settings,
      backupService: BackupService(
        settings: settings,
        configStore: configStore,
        workflowRegistry: workflowRegistry,
        providerRegistry: providerRegistry,
        storage: StorageService(database),
        credentialStore: credentialStore,
      ),
      credentialStore: credentialStore,
      backupsDirectory: () async {
        if (!await backupsDir.exists()) await backupsDir.create(recursive: true);
        return backupsDir;
      },
    );
  });

  tearDown(() async {
    await database.close();
    tempDir.deleteSync(recursive: true);
  });

  group('BackupScheduler.runIfDue', () {
    test('does nothing when scheduling is off', () async {
      await scheduler.setPassphrase('a passphrase');
      await scheduler.runIfDue();

      expect(backupsDir.existsSync(), isFalse);
      expect(settings.lastScheduledBackupAt, isNull);
    });

    test('does nothing when enabled but no passphrase has been set yet', () async {
      await settings.setScheduledBackupsEnabled(true);
      await scheduler.runIfDue();

      expect(backupsDir.existsSync(), isFalse);
    });

    test('writes an encrypted backup and records the time when due', () async {
      await settings.setScheduledBackupsEnabled(true);
      await scheduler.setPassphrase('a passphrase');

      await scheduler.runIfDue();

      final files = backupsDir.listSync().whereType<File>().toList();
      expect(files, hasLength(1));
      expect(settings.lastScheduledBackupAt, isNotNull);
    });

    test('does not run again before the interval elapses', () async {
      await settings.setScheduledBackupsEnabled(true);
      await scheduler.setPassphrase('a passphrase');
      await settings.setLastScheduledBackupAt(DateTime.now());

      await scheduler.runIfDue();

      expect(backupsDir.existsSync(), isFalse);
    });

    test('runs again once the interval has elapsed', () async {
      await settings.setScheduledBackupsEnabled(true);
      await scheduler.setPassphrase('a passphrase');
      await settings.setLastScheduledBackupAt(
        DateTime.now().subtract(BackupScheduler.interval + const Duration(days: 1)),
      );

      await scheduler.runIfDue();

      final files = backupsDir.listSync().whereType<File>().toList();
      expect(files, hasLength(1));
    });

    test('enforces the retention cap by deleting the oldest files', () async {
      await backupsDir.create(recursive: true);
      for (var i = 0; i < BackupScheduler.retentionCount + 2; i++) {
        final file = File(
          '${backupsDir.path}${Platform.pathSeparator}rescripto-backup-2026010$i-0000.rescriptobackup',
        );
        await file.writeAsBytes([0]);
      }
      await settings.setScheduledBackupsEnabled(true);
      await scheduler.setPassphrase('a passphrase');

      await scheduler.runIfDue();

      final files = backupsDir.listSync().whereType<File>().toList();
      expect(files, hasLength(BackupScheduler.retentionCount));
    });
  });

  group('BackupScheduler passphrase management', () {
    test('hasPassphrase reflects whether one has been set', () async {
      expect(await scheduler.hasPassphrase(), isFalse);
      await scheduler.setPassphrase('x');
      expect(await scheduler.hasPassphrase(), isTrue);
    });

    test('clearPassphrase removes it', () async {
      await scheduler.setPassphrase('x');
      await scheduler.clearPassphrase();
      expect(await scheduler.hasPassphrase(), isFalse);
    });
  });
}
