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
  bool get scheduledBackupsEnabled => _service.scheduledBackupsEnabled;
  DateTime? get lastScheduledBackupAt => _service.lastScheduledBackupAt;
  bool get scheduledBackupIncludeHistory => _service.scheduledBackupIncludeHistory;
  bool get scheduledBackupIncludeCredentials => _service.scheduledBackupIncludeCredentials;

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

  /// Re-notifies listeners without changing anything itself. Every getter
  /// above already reads straight through to [SettingsService], so this
  /// exists only for a caller that wrote to the service directly —
  /// `BackupService.restore`, which cannot depend on this class (`services/`
  /// never depends on `state/`) and so cannot notify it any other way.
  void refreshFromService() => notifyListeners();
}
