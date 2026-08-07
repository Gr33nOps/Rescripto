/// Global app constants.
abstract final class AppConstants {
  static const String appName = 'Rescripto';
  static const String tagline = 'Polished text. 100% offline.';
  static const String privacyPromise =
      'Completely free · Completely offline · Completely private';

  // Storage keys (shared_preferences).
  static const String keySelectedModel = 'selected_model_id';
  static const String keyThemeMode = 'theme_mode'; // 'system' | 'light' | 'dark'
  static const String keyThreadCount = 'thread_count';
  static const String keyUseGpu = 'use_gpu';
  static const String keyContextSize = 'context_size';
  static const String keyOnboarded = 'onboarded';
  static const String keyWhisperModel = 'whisper_model';
  static const String keyIsDownloading = 'model_downloading_';

  // SQLite.
  static const String dbName = 'rescripto.db';
  static const int dbVersion = 1;

  // Directories.
  static const String modelsDir = 'models';
  static const String audioDir = 'audio';

  // Generation defaults.
  static const int defaultContextSize = 2048;
  static const int defaultMaxTokens = 1024;
  static const int defaultThreads = 4;

  /// Tokens reserved for the output; prompt is truncated to context - this.
  static const int outputReserve = 512;
}
