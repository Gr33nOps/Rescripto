import 'package:flutter/material.dart';

import '../screens/authoring/tone_list_screen.dart';
import '../screens/network_log_screen.dart';
import '../screens/privacy_screen.dart';
import '../screens/providers_screen.dart';

/// Route names for the screens pushed from Settings.
///
/// The app has no other navigation infrastructure — `MaterialApp(home:
/// HomeShell())`, four tabs in a bare `IndexedStack`. Deliberately not
/// `go_router`: every screen here is pushed imperatively from Settings, and
/// a routing package earns its cost once there are enough independent flows
/// to justify one, which four `Navigator.push`-reachable screens are not.
/// `providerEdit` isn't in [routes] because it always needs an argument
/// (which config to edit, or none for "add new") — it's pushed directly
/// with `MaterialPageRoute` from `providers_screen.dart` instead.
abstract final class AppRoutes {
  static const privacy = '/privacy';
  static const networkLog = '/network-log';
  static const providers = '/providers';
  static const tones = '/tones';

  static Map<String, WidgetBuilder> get routes => {
    privacy: (_) => const PrivacyScreen(),
    networkLog: (_) => const NetworkLogScreen(),
    providers: (_) => const ProvidersScreen(),
    tones: (_) => const ToneListScreen(),
  };
}
