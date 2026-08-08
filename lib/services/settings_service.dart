import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../models/ai_model.dart';

/// Thin persistence layer for app preferences (all on-device).
class SettingsService {
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
  }

  SharedPreferences get _p {
    final p = _prefs;
    if (p == null) {
      throw StateError('SettingsService.init() must be called first.');
    }
    return p;
  }

  String get selectedModelId =>
      _p.getString(AppConstants.keySelectedModel) ??
      ModelCatalog.defaultModel.id;

  Future<void> setSelectedModelId(String id) async {
    await _p.setString(AppConstants.keySelectedModel, id);
  }

  String get themeMode => _p.getString(AppConstants.keyThemeMode) ?? 'system';

  Future<void> setThemeMode(String mode) async {
    await _p.setString(AppConstants.keyThemeMode, mode);
  }

  int get threads {
    final value =
        _p.getInt(AppConstants.keyThreadCount) ?? AppConstants.defaultThreads;
    return value.clamp(1, 8);
  }

  Future<void> setThreads(int value) async {
    await _p.setInt(AppConstants.keyThreadCount, value);
  }

  bool get useGpu => _p.getBool(AppConstants.keyUseGpu) ?? true;

  Future<void> setUseGpu(bool value) async {
    await _p.setBool(AppConstants.keyUseGpu, value);
  }

  int get contextSize {
    final value =
        _p.getInt(AppConstants.keyContextSize) ??
        AppConstants.defaultContextSize;
    return value.clamp(2048, 8192);
  }

  Future<void> setContextSize(int value) async {
    await _p.setInt(AppConstants.keyContextSize, value);
  }

  String get whisperModel =>
      _p.getString(AppConstants.keyWhisperModel) ?? 'small';

  Future<void> setWhisperModel(String value) async {
    await _p.setString(AppConstants.keyWhisperModel, value);
  }
}
