/// Global app constants.
abstract final class AppConstants {
  static const String appName = 'Rescripto';
  static const String tagline = 'Polished text. Private, on-device AI.';
  static const String privacyPromise =
      'No accounts · No cloud processing · Your content stays local';
  static const String sourceUrl = 'https://github.com/Gr33nOps/Rescripto';
  static const String issuesUrl =
      'https://github.com/Gr33nOps/Rescripto/issues';
  // Keep in step with `version:` in pubspec.yaml.
  static const String versionName = '1.0.3';

  // Storage keys (shared_preferences).
  static const String keySelectedModel = 'selected_model_id';
  static const String keyThemeMode =
      'theme_mode'; // 'system' | 'light' | 'dark'
  static const String keyThreadCount = 'thread_count';
  static const String keyUseGpu = 'use_gpu';
  static const String keyContextSize = 'context_size';
  static const String keyWhisperModel = 'whisper_model';
  static const String keySettingsSchemaVersion = 'settings_schema_version';
  // Superseded by keySettingsSchemaVersion. Still written so that downgrading
  // to 1.0.3 and upgrading again does not re-apply the GPU reset.
  static const String keyGpuResetDone = 'gpu_default_reset_v2';

  // SQLite.
  static const String dbName = 'rescripto.db';
  static const int dbVersion = 1;

  // Directories.
  static const String modelsDir = 'models';

  // Generation defaults.
  static const int defaultContextSize = 2048;
  static const int defaultMaxTokens = 1024;
  static const int defaultThreads = 4;
}
