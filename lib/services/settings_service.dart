import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../models/ai_model.dart';
import 'settings_migrations.dart';

/// Thin persistence layer for app preferences (all on-device).
class SettingsService {
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await migrateSettings(_prefs!);
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

  /// GPU (Vulkan) offload. Off by default: bringing up a Vulkan device makes
  /// ggml compile several hundred compute pipelines, which costs minutes on
  /// many Android drivers, and on most phones the CPU backend is faster anyway
  /// for the 1B-3B models in this catalog.
  bool get useGpu => _p.getBool(AppConstants.keyUseGpu) ?? false;

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

  /// Whisper size. "base" (141 MB) is the default rather than "small"
  /// (465 MB): it is the first tap on the mic that pays for this download, and
  /// base transcribes short dictation roughly 3x faster on a phone.
  String get whisperModel =>
      _p.getString(AppConstants.keyWhisperModel) ?? 'base';

  Future<void> setWhisperModel(String value) async {
    await _p.setString(AppConstants.keyWhisperModel, value);
  }
}
