/// Global app constants.
abstract final class AppConstants {
  static const String appName = 'Rescripto';
  static const String tagline = 'Clearer writing, on your terms.';

  /// True in every processing mode — the part of the original promise that
  /// survived Cloud/Hybrid mode existing at all.
  static const String privacyPromise =
      'No account · No tracking · You choose where your text is processed';

  /// Only true in [ProcessingMode.local] — the original, stronger claim.
  /// `AppConstants.privacyPromise` alone became false the moment a Cloud
  /// mode existed; this is what's shown instead when the mode genuinely
  /// backs it.
  static const String localModePromise =
      'No account · No cloud processing · Your content stays on this device';

  static const String sourceUrl = 'https://github.com/Gr33nOps/Rescripto';
  static const String issuesUrl =
      'https://github.com/Gr33nOps/Rescripto/issues';
  // Keep in step with `version:` in pubspec.yaml.
  static const String versionName = '1.2.7';

  // Storage keys (shared_preferences).
  static const String keySelectedModel = 'selected_model_id';
  static const String keyThemeMode =
      'theme_mode'; // 'system' | 'light' | 'dark'
  static const String keyThreadCount = 'thread_count';
  static const String keyUseGpu = 'use_gpu';
  static const String keyContextSize = 'context_size';
  static const String keyWhisperModel = 'whisper_model';
  static const String keyProcessingMode = 'processing_mode';
  static const String keyCloudProviderId = 'cloud_provider_id';
  static const String keyCloudModelRef = 'cloud_model_ref';
  static const String keyCloudFallbackConsent = 'cloud_fallback_consent';
  static const String keySpeechEngine = 'speech_engine';
  static const String keyOnboardingCompleted = 'onboarding_completed';
  static const String keyUiMode = 'ui_mode'; // 'simple' | 'pro'
  static const String keyScheduledBackupsEnabled = 'scheduled_backups_enabled';
  static const String keyLastScheduledBackupAt = 'last_scheduled_backup_at';
  static const String keyScheduledBackupIncludeHistory =
      'scheduled_backup_include_history';
  static const String keyScheduledBackupIncludeCredentials =
      'scheduled_backup_include_credentials';
  static const String keyWebdavUrl = 'webdav_url';
  static const String keyWebdavUsername = 'webdav_username';
  static const String keyLastSyncPushAt = 'last_sync_push_at';
  static const String keySyncIncludeSettings = 'sync_include_settings';
  static const String keySyncIncludePresets = 'sync_include_presets';
  static const String keySyncIncludeWorkflows = 'sync_include_workflows';
  static const String keySyncIncludeProviderConfigs =
      'sync_include_provider_configs';
  static const String keySyncIncludeHistory = 'sync_include_history';
  static const String keySyncIncludeCredentials = 'sync_include_credentials';
  static const String keySettingsSchemaVersion = 'settings_schema_version';
  // Superseded by keySettingsSchemaVersion. Still written so that downgrading
  // to 1.0.3 and upgrading again does not re-apply the GPU reset.
  static const String keyGpuResetDone = 'gpu_default_reset_v2';

  // SQLite.
  static const String dbName = 'rescripto.db';
  // 2: tone_preset + audience_tag tables, history(created_at) index.
  // 3: network_log table.
  // 4: credential_ref table.
  // 5: provider_config + provider_model tables.
  // 6: workflow + workflow_step tables.
  // 7: tone_preset gains top_p/top_k/repeat_penalty/max_output_tokens/stop_sequences.
  static const int dbVersion = 7;

  // Directories.
  static const String modelsDir = 'models';

  // Generation defaults.
  static const int defaultContextSize = 2048;
  static const int defaultMaxTokens = 1024;
  static const int defaultThreads = 4;
}
