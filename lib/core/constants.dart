/// Global app constants.
abstract final class AppConstants {
  static const String appName = 'Rescripto';
  static const String tagline = 'Polished text. Private, on-device AI.';
  static const String privacyPromise =
      'No accounts · No cloud processing · Your content stays local';

  // Storage keys (shared_preferences).
  static const String keySelectedModel = 'selected_model_id';
  static const String keyThemeMode =
      'theme_mode'; // 'system' | 'light' | 'dark'
  static const String keyThreadCount = 'thread_count';
  static const String keyUseGpu = 'use_gpu';
  static const String keyContextSize = 'context_size';
  static const String keyWhisperModel = 'whisper_model';

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
