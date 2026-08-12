import 'package:flutter/material.dart';

import '../models/processing_mode.dart';
import '../models/ui_mode.dart';
import '../services/settings_service.dart';

/// App-level settings exposed to the UI.
class SettingsController extends ChangeNotifier {
  SettingsController(this._service);

  final SettingsService _service;

  String get selectedModelId => _service.selectedModelId;
  String get themeMode => _service.themeMode;
  int get threads => _service.threads;
  bool get useGpu => _service.useGpu;
  int get contextSize => _service.contextSize;
  String get whisperModel => _service.whisperModel;
  ProcessingMode get processingMode => _service.processingMode;
  bool get onboardingCompleted => _service.onboardingCompleted;
  UiMode get uiMode => _service.uiMode;
  String? get cloudProviderId => _service.cloudProviderId;
  String? get cloudModelRef => _service.cloudModelRef;
  String get speechEngine => _service.speechEngine;
  bool get scheduledBackupsEnabled => _service.scheduledBackupsEnabled;
  DateTime? get lastScheduledBackupAt => _service.lastScheduledBackupAt;
  bool get scheduledBackupIncludeHistory => _service.scheduledBackupIncludeHistory;
  bool get scheduledBackupIncludeCredentials => _service.scheduledBackupIncludeCredentials;
  String? get webdavUrl => _service.webdavUrl;
  String? get webdavUsername => _service.webdavUsername;
  DateTime? get lastSyncPushAt => _service.lastSyncPushAt;
  bool get syncIncludeSettings => _service.syncIncludeSettings;
  bool get syncIncludePresets => _service.syncIncludePresets;
  bool get syncIncludeWorkflows => _service.syncIncludeWorkflows;
  bool get syncIncludeProviderConfigs => _service.syncIncludeProviderConfigs;
  bool get syncIncludeHistory => _service.syncIncludeHistory;
  bool get syncIncludeCredentials => _service.syncIncludeCredentials;

  ThemeMode get themeModeValue => switch (_service.themeMode) {
    'light' => ThemeMode.light,
    'dark' => ThemeMode.dark,
    _ => ThemeMode.system,
  };

  Future<void> setSelectedModelId(String id) async {
    await _service.setSelectedModelId(id);
    notifyListeners();
  }

  Future<void> setThemeMode(String mode) async {
    await _service.setThemeMode(mode);
    notifyListeners();
  }

  Future<void> setThreads(int value) async {
    await _service.setThreads(value);
    notifyListeners();
  }

  Future<void> setUseGpu(bool value) async {
    await _service.setUseGpu(value);
    notifyListeners();
  }

  Future<void> setContextSize(int value) async {
    await _service.setContextSize(value);
    notifyListeners();
  }

  Future<void> setWhisperModel(String value) async {
    await _service.setWhisperModel(value);
    notifyListeners();
  }

  Future<void> setProcessingMode(ProcessingMode mode) async {
    await _service.setProcessingMode(mode);
    notifyListeners();
  }

  /// Written only at the very end of onboarding — see `OnboardingScreen`.
  Future<void> setOnboardingCompleted(bool value) async {
    await _service.setOnboardingCompleted(value);
    notifyListeners();
  }

  /// Persists the mode only. Pinning/restoring `RewriteController`'s editor
  /// state on a Simple↔Pro transition is a separate, explicit step the
  /// caller does alongside this — see `RewriteController.enterSimpleMode`/
  /// `enterProMode` — rather than something this setter reaches into
  /// another controller to do itself.
  Future<void> setUiMode(UiMode mode) async {
    await _service.setUiMode(mode);
    notifyListeners();
  }

  Future<void> setScheduledBackupsEnabled(bool value) async {
    await _service.setScheduledBackupsEnabled(value);
    notifyListeners();
  }

  Future<void> setScheduledBackupIncludeHistory(bool value) async {
    await _service.setScheduledBackupIncludeHistory(value);
    notifyListeners();
  }

  Future<void> setScheduledBackupIncludeCredentials(bool value) async {
    await _service.setScheduledBackupIncludeCredentials(value);
    notifyListeners();
  }

  /// Which configured provider cloud rewrites go to. `TargetRouter` falls
  /// back to the first enabled provider when this is unset, so setting it is
  /// a preference rather than a prerequisite — see that class's own doc for
  /// why routing must never depend on a setting nothing forces the user to
  /// fill in.
  Future<void> setCloudProviderId(String? id) async {
    await _service.setCloudProviderId(id);
    notifyListeners();
  }

  Future<void> setCloudModelRef(String? modelRef) async {
    await _service.setCloudModelRef(modelRef);
    notifyListeners();
  }

  /// `'local'` or `'cloud'` — see `SpeechEngineResolver`, which is what
  /// actually reads this. It was written and backed up but read by nothing
  /// before that resolver existed, so choosing Cloud transcribed on-device
  /// anyway.
  Future<void> setSpeechEngine(String value) async {
    await _service.setSpeechEngine(value);
    notifyListeners();
  }

  Future<void> setWebdavUrl(String? value) async {
    await _service.setWebdavUrl(value);
    notifyListeners();
  }

  Future<void> setWebdavUsername(String? value) async {
    await _service.setWebdavUsername(value);
    notifyListeners();
  }

  Future<void> setSyncIncludeSettings(bool value) async {
    await _service.setSyncIncludeSettings(value);
    notifyListeners();
  }

  Future<void> setSyncIncludePresets(bool value) async {
    await _service.setSyncIncludePresets(value);
    notifyListeners();
  }

  Future<void> setSyncIncludeWorkflows(bool value) async {
    await _service.setSyncIncludeWorkflows(value);
    notifyListeners();
  }

  Future<void> setSyncIncludeProviderConfigs(bool value) async {
    await _service.setSyncIncludeProviderConfigs(value);
    notifyListeners();
  }

  Future<void> setSyncIncludeHistory(bool value) async {
    await _service.setSyncIncludeHistory(value);
    notifyListeners();
  }

  Future<void> setSyncIncludeCredentials(bool value) async {
    await _service.setSyncIncludeCredentials(value);
    notifyListeners();
  }

  /// Re-notifies listeners without changing anything itself. Every getter
  /// above already reads straight through to [SettingsService], so this
  /// exists only for a caller that wrote to the service directly —
  /// `BackupService.restore`, which cannot depend on this class (`services/`
  /// never depends on `state/`) and so cannot notify it any other way.
  void refreshFromService() => notifyListeners();
}
