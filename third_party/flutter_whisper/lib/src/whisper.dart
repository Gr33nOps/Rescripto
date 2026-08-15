part of 'package:flutter_whisper/flutter_whisper.dart';

/// Main entry point for Flutter Whisper.
///
/// Usage:
/// ```dart
/// final whisper = Whisper();
/// await whisper.initialize(model: WhisperModel.tiny);
/// final result = await whisper.transcribeFile('recording.wav');
/// print(result.text);
/// ```
class Whisper {
  Whisper._internal();
  static final Whisper _instance = Whisper._internal();
  factory Whisper() => _instance;

  WhisperEngine? _engine;
  WhisperModel? _loadedModel;
  bool _isInitialized = false;
  WhisperDownloader? _downloader;
  String? _downloadDir;

  // Last init params — used by resumeDownload().
  WhisperModel? _lastModel;
  WhisperOptions _lastOptions = const WhisperOptions();
  WhisperDownloadConfig _lastConfig = const WhisperDownloadConfig();
  void Function(WhisperDownloadProgress)? _lastOnProgress;

  /// Whether the engine is initialized and ready.
  bool get isInitialized => _isInitialized;

  /// Currently loaded model (if any).
  WhisperModel? get loadedModel => _loadedModel;

  /// Initialize the Whisper engine with a model.
  ///
  /// [model] - Model to load (default: tiny)
  /// [options] - Transcription options (optional)
  /// [downloadConfig] - Download behavior (resume, retries, mirror, integrity)
  /// [onProgress] - Download progress callback, fires while the model
  ///                downloads on first use.
  /// [httpClient] - Client the model download runs over. A supported
  ///                injection point, not test-only: a host app can hand in a
  ///                client that enforces its own network policy or logging
  ///                (e.g. Rescripto's `NetworkGuard`) instead of a bare
  ///                `http.Client()`.
  /// [downloadDirectory] - Overrides where the model is stored. Also a
  ///                supported injection point, for a host app that wants
  ///                control over its own storage layout.
  ///
  /// Throws [WhisperError] on failure.
  Future<void> initialize({
    WhisperModel model = WhisperModel.tiny,
    WhisperOptions options = const WhisperOptions(),
    WhisperDownloadConfig downloadConfig = const WhisperDownloadConfig(),
    void Function(WhisperDownloadProgress)? onProgress,
    http.Client? httpClient,
    String? downloadDirectory,
  }) async {
    if (_isInitialized && _loadedModel == model) return;
    if (_isInitialized) {
      await _engine?.dispose();
      _engine = null;
      _isInitialized = false;
      _loadedModel = null;
    }

    _lastModel = model;
    _lastOptions = options;
    _lastConfig = downloadConfig;
    _lastOnProgress = onProgress;
    _downloadDir ??=
        downloadDirectory ?? (await getApplicationSupportDirectory()).path;

    // Test that the bundled JNI library can be loaded before spending time
    // and storage downloading a model the device cannot use.
    _engine ??= _createEngine();
    final support = await _engine!.checkSupport();
    if (!support.supported) {
      throw WhisperError(
        support.message ?? 'On-device voice input is unavailable on this device.',
        WhisperErrorCode.nativeUnavailable,
      );
    }

    // Get model file path (downloads if not cached, resumes if partial).
    final modelPath = await _ensureModel(
      model,
      onProgress: onProgress,
      config: downloadConfig,
      httpClient: httpClient,
    );

    try {
      await _engine!.initialize(modelPath: modelPath, options: options);
      _loadedModel = model;
      _isInitialized = true;
    } catch (e) {
      _isInitialized = false;
      _loadedModel = null;
      rethrow;
    }
  }

  /// Pause an in-flight model download. Partial data is kept on disk;
  /// call [resumeDownload] to continue.
  void pauseDownload() => _downloader?.pause();

  /// Resume a paused/interrupted model download.
  Future<void> resumeDownload() async {
    if (_lastModel == null || _isInitialized) return;
    await initialize(
      model: _lastModel!,
      options: _lastOptions,
      downloadConfig: _lastConfig,
      onProgress: _lastOnProgress,
    );
  }

  /// Cancel any ongoing download or transcription.
  void cancel() {
    _downloader?.cancel();
    _engine?.cancel();
  }

  /// Transcribe an audio file.
  ///
  /// [audioPath] - Path to audio file (wav, mp3, m4a, etc.)
  /// [options] - Override options for this transcription
  /// [onProgress] - Receives 0..100 during transcription
  ///
  /// Returns [TranscriptionResult] with text, segments, language.
  /// Throws [WhisperError] on failure.
  Future<TranscriptionResult> transcribeFile(
    String audioPath, {
    WhisperOptions? options,
    void Function(int)? onProgress,
  }) async {
    _assertInitialized();
    return _engine!
        .transcribeFile(audioPath, options: options, onProgress: onProgress);
  }

  /// Start recording from the microphone (16 kHz mono WAV on disk).
  ///
  /// Combine with [stopRecording] → [transcribeFile] for record-and-transcribe.
  ///
  /// Does **not** require [initialize] to have been called first — audio
  /// capture has no dependency on a loaded model, only [transcribeFile]
  /// does. A caller that only wants the recording (to send elsewhere for
  /// transcription, say) never pays for downloading and loading a local
  /// model it will never use; the platform engine is created lazily here
  /// instead.
  Future<void> startRecording() async {
    _engine ??= _createEngine();
    await _engine!.startRecording();
  }

  /// Stop recording; returns path to the recorded WAV. See [startRecording]
  /// for why this doesn't require [initialize].
  Future<String> stopRecording() async {
    final engine = _engine;
    if (engine == null) {
      throw WhisperError(
        'No recording in progress — call startRecording() first.',
        WhisperErrorCode.engineNotInitialized,
      );
    }
    return engine.stopRecording();
  }

  /// Dispose resources.
  Future<void> dispose() async {
    _downloader?.cancel();
    await _engine?.dispose();
    _engine = null;
    _isInitialized = false;
    _loadedModel = null;
  }

  // Platform-specific engine creation
  WhisperEngine _createEngine() {
    return MethodChannelWhisperEngine();
  }

  void _assertInitialized() {
    if (!_isInitialized || _engine == null) {
      throw WhisperError(
        'Whisper not initialized. Call initialize() first.',
        WhisperErrorCode.engineNotInitialized,
      );
    }
  }

  /// Ensure model is available locally, downloading if needed.
  Future<String> _ensureModel(
    WhisperModel model, {
    required void Function(WhisperDownloadProgress)? onProgress,
    required WhisperDownloadConfig config,
    http.Client? httpClient,
  }) async {
    final dir = _downloadDir ?? (await getApplicationSupportDirectory()).path;
    final downloader = WhisperDownloader(directory: dir, client: httpClient);
    _downloader = downloader;
    try {
      return await downloader.download(model,
          config: config, onProgress: onProgress);
    } finally {
      if (identical(_downloader, downloader)) _downloader = null;
      downloader.close();
    }
  }
}
