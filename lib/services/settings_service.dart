import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants.dart';
import '../models/ai_model.dart';
import '../models/cloud_fallback_consent.dart';
import '../models/processing_mode.dart';
import '../models/ui_mode.dart';
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

  /// Whether onboarding has been shown and completed.
  ///
  /// Written only at the very end of the onboarding flow, so an interrupted
  /// run repeats — see `OnboardingScreen`. An upgrading install never sees
  /// it either, but for a different reason: `_v2MarkExistingInstallsOnboarded`
  /// (`settings_migrations.dart`) sets this to true during migration itself,
  /// before the app ever renders a frame.
  bool get onboardingCompleted =>
      _p.getBool(AppConstants.keyOnboardingCompleted) ?? false;

  Future<void> setOnboardingCompleted(bool value) async {
    await _p.setBool(AppConstants.keyOnboardingCompleted, value);
  }

  /// Simple (tone + rewrite only) or Pro (every control). Simple by
  /// default — progressive disclosure, not a value judgement about anyone's
  /// prior habits: an existing install upgrading into this build starts
  /// Simple too, since there is no stored "was already using Pro-only
  /// controls" signal to key a different default off of.
  UiMode get uiMode {
    final raw = _p.getString(AppConstants.keyUiMode);
    for (final mode in UiMode.values) {
      if (mode.name == raw) return mode;
    }
    return UiMode.simple;
  }

  Future<void> setUiMode(UiMode mode) async {
    await _p.setString(AppConstants.keyUiMode, mode.name);
  }

  /// Whether `BackupScheduler` should write an unattended local backup on
  /// app start once the interval has elapsed. Off by default — this is an
  /// opt-in convenience, not something a fresh install starts doing to a
  /// passphrase nobody has set yet.
  bool get scheduledBackupsEnabled =>
      _p.getBool(AppConstants.keyScheduledBackupsEnabled) ?? false;

  Future<void> setScheduledBackupsEnabled(bool value) async {
    await _p.setBool(AppConstants.keyScheduledBackupsEnabled, value);
  }

  /// Null until the first scheduled backup succeeds.
  DateTime? get lastScheduledBackupAt {
    final raw = _p.getString(AppConstants.keyLastScheduledBackupAt);
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> setLastScheduledBackupAt(DateTime value) async {
    await _p.setString(AppConstants.keyLastScheduledBackupAt, value.toIso8601String());
  }

  /// Mirrors the manual export screen's own toggle, off by default for the
  /// same reason: history is the most sensitive section.
  bool get scheduledBackupIncludeHistory =>
      _p.getBool(AppConstants.keyScheduledBackupIncludeHistory) ?? false;

  Future<void> setScheduledBackupIncludeHistory(bool value) async {
    await _p.setBool(AppConstants.keyScheduledBackupIncludeHistory, value);
  }

  bool get scheduledBackupIncludeCredentials =>
      _p.getBool(AppConstants.keyScheduledBackupIncludeCredentials) ?? false;

  Future<void> setScheduledBackupIncludeCredentials(bool value) async {
    await _p.setBool(AppConstants.keyScheduledBackupIncludeCredentials, value);
  }
}
