import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../models/ai_model.dart';

/// Thin persistence layer for app preferences (all on-device).
class SettingsService {
  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _migrate();
  }

  /// One-time cleanups for settings whose meaning changed between releases.
  Future<void> _migrate() async {
    final p = _p;
    if (!p.containsKey(AppConstants.keyGpuResetDone)) {
      // Up to 1.0.2 the GPU switch passed nGpuLayers: -1, which llama.cpp reads
      // as "offload nothing" — the toggle did nothing whichever way it was set,
      // while still paying for Vulkan device setup on every model load. Now
      // that it really offloads, an inherited "on" is a choice nobody made, so
      // start everyone from off.
      await p.remove(AppConstants.keyUseGpu);
      await p.setBool(AppConstants.keyGpuResetDone, true);
    }
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
