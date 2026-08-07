import 'package:flutter/material.dart';

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
}
