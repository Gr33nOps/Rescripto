import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../models/ai_model.dart';
import '../models/cloud_fallback_consent.dart';
import '../models/processing_mode.dart';
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

  ProcessingMode get processingMode {
    final raw = _p.getString(AppConstants.keyProcessingMode);
    for (final mode in ProcessingMode.values) {
      if (mode.name == raw) return mode;
    }
    return ProcessingMode.local;
  }

  Future<void> setProcessingMode(ProcessingMode mode) async {
    await _p.setString(AppConstants.keyProcessingMode, mode.name);
  }

  /// The [ProviderConfig.id] currently selected for cloud rewriting, or null
  /// if none has been chosen yet.
  String? get cloudProviderId => _p.getString(AppConstants.keyCloudProviderId);

  Future<void> setCloudProviderId(String? id) async {
    if (id == null) {
      await _p.remove(AppConstants.keyCloudProviderId);
    } else {
      await _p.setString(AppConstants.keyCloudProviderId, id);
    }
  }

  String? get cloudModelRef => _p.getString(AppConstants.keyCloudModelRef);

  Future<void> setCloudModelRef(String? modelRef) async {
    if (modelRef == null) {
      await _p.remove(AppConstants.keyCloudModelRef);
    } else {
      await _p.setString(AppConstants.keyCloudModelRef, modelRef);
    }
  }

  CloudFallbackConsent get cloudFallbackConsent {
    final raw = _p.getString(AppConstants.keyCloudFallbackConsent);
    if (raw == null) return CloudFallbackConsent.none;
    try {
      return CloudFallbackConsent.fromJson(
        jsonDecode(raw) as Map<String, Object?>,
      );
    } catch (_) {
      // Corrupt or unrecognisable stored consent must never be read as
      // "granted" — degrade to "not granted," the same way CredentialStore
      // degrades a Keystore failure to "not configured."
      return CloudFallbackConsent.none;
    }
  }

  Future<void> setCloudFallbackConsent(CloudFallbackConsent consent) async {
    await _p.setString(
      AppConstants.keyCloudFallbackConsent,
      jsonEncode(consent.toJson()),
    );
  }

  /// Which engine handles speech-to-text: `'local'`, `'cloud'`, or
  /// `'system'`. Plumbing only until `lib/speech/` reads it.
  String get speechEngine => _p.getString(AppConstants.keySpeechEngine) ?? 'local';

  Future<void> setSpeechEngine(String value) async {
    await _p.setString(AppConstants.keySpeechEngine, value);
  }
}
