import 'package:flutter/material.dart';

import 'app.dart';
import 'services/settings_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final settings = SettingsService();
  await settings.init();
  runApp(RescriptoApp(settings: settings));
}
