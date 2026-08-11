import 'package:flutter/material.dart';

import 'app.dart';
import 'services/config_store.dart';
import 'services/db/app_database.dart';
import 'services/settings_service.dart';

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

  runApp(
    RescriptoApp(settings: settings, database: database, configStore: configStore),
  );
}
