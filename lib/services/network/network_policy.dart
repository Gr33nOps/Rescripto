import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'network_feature.dart';

/// Whether each [NetworkFeature] — and network access as a whole — is
/// currently allowed.
///
/// Backed by `SharedPreferences`, not SQLite: this must stay readable even if
/// the database is corrupt or mid-migration, and it must be checkable before
/// [NetworkGuard] hands out a single client. Follows the same init-gate
/// shape as `SettingsService`.
class NetworkPolicy extends ChangeNotifier {
  SharedPreferences? _prefs;

  static const _killSwitchKey = 'net.kill_switch';
  static const _featureKeyPrefix = 'net.feature.';

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  SharedPreferences get _p {
    final p = _prefs;
    if (p == null) {
      throw StateError('NetworkPolicy.init() must be called first.');
    }
    return p;
  }

  /// When true, every feature is blocked regardless of its own setting.
  bool get killSwitch => _p.getBool(_killSwitchKey) ?? false;

  Future<void> setKillSwitch(bool value) async {
    await _p.setBool(_killSwitchKey, value);
    notifyListeners();
  }

  bool isAllowed(NetworkFeature feature) {
    if (killSwitch) return false;
    return _p.getBool('$_featureKeyPrefix${feature.name}') ??
        _defaultAllowed(feature);
  }

  Future<void> setFeatureEnabled(NetworkFeature feature, bool value) async {
    await _p.setBool('$_featureKeyPrefix${feature.name}', value);
    notifyListeners();
  }

  /// Model and voice-model downloads are what the app already did before
  /// this guard existed, so they default on. Everything else — cloud
  /// providers, sync, update checks — is new surface with no built-in
  /// justification for reaching the network, so it starts off until the
  /// user turns it on.
  bool _defaultAllowed(NetworkFeature feature) => switch (feature) {
    NetworkFeature.modelDownload => true,
    NetworkFeature.voiceModelDownload => true,
    NetworkFeature.cloudRewrite => false,
    NetworkFeature.cloudSpeech => false,
    NetworkFeature.sync => false,
    NetworkFeature.updateCheck => false,
  };
}
