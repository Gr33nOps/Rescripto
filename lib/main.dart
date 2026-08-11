import 'package:flutter/material.dart';

import 'app.dart';
import 'services/backup/backup_scheduler.dart';
import 'services/backup/backup_service.dart';
import 'services/config_store.dart';
import 'services/credentials/credential_store.dart';
import 'services/db/app_database.dart';
import 'services/network/network_policy.dart';
import 'services/providers/provider_registry.dart';
import 'services/providers/provider_store.dart';
import 'services/settings_service.dart';
import 'services/storage_service.dart';
import 'services/workflows/workflow_registry.dart';
import 'services/workflows/workflow_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsService();
  await settings.init();

  // Built here rather than inside the provider tree, and awaited before
  // runApp, so ToneSelector and the audience list never render an empty
  // frame while the seed rows are still being written on a fresh install.
  final database = AppDatabase();
  final configStore = ConfigStore(database);
  await configStore.load();

  // Built here too, for the same reason: a provider screen must never
  // render an empty list on first frame while the table is still loading.
  final credentialStore = CredentialStore(database);
  final providerRegistry = ProviderRegistry(
    ProviderStore(database, credentialStore),
  );
  await providerRegistry.load();

  // Same reasoning again: the workflow list must never render empty on
  // first frame while its own table is still loading.
  final workflowRegistry = WorkflowRegistry(WorkflowStore(database));
  await workflowRegistry.load();

  // NetworkGuard checks this before every request it hands out, so it must
  // be ready before anything can download. Kept independent of AppDatabase:
  // policy has to stay readable even if the database is corrupt.
  final networkPolicy = NetworkPolicy();
  await networkPolicy.init();

  runApp(
    RescriptoApp(
      settings: settings,
      database: database,
      configStore: configStore,
      credentialStore: credentialStore,
      providerRegistry: providerRegistry,
      workflowRegistry: workflowRegistry,
      networkPolicy: networkPolicy,
    ),
  );

  // Fire-and-forget, deliberately after runApp rather than awaited before
  // it: Argon2id plus a full gather()/export() is real work, and nothing
  // about "keep a recent local copy" should be allowed to delay the first
  // frame. A failed or skipped run just means the next launch tries again.
  BackupScheduler(
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
  ).runIfDue();
}
