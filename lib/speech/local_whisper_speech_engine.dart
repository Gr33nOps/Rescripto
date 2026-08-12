import '../models/speech_result.dart';
import '../services/network/network_feature.dart';
import '../services/network/network_guard.dart';
import '../services/settings_service.dart';
import '../services/speech_service.dart';
import 'speech_engine.dart';

/// [SpeechEngine] over the existing on-device whisper.cpp pipeline.
///
/// A thin wrapper — [SpeechService] and `SpeechController`'s error-mapping
/// are unchanged and untouched by this. This class exists so local speech
/// can be selected through the same [SpeechEngine] surface cloud and system
/// speech use, once something picks between them by id rather than always
/// reaching for [SpeechService] directly.
class LocalWhisperSpeechEngine implements SpeechEngine {
  LocalWhisperSpeechEngine(this._service, this._settings, this._networkGuard);

  final SpeechService _service;
  final SettingsService _settings;
  final NetworkGuard _networkGuard;

  @override
  String get id => 'local.whisper';

  @override
  SpeechCapabilities get capabilities => const SpeechCapabilities(
    requiresNetwork: false,
    auditableEgress: true,
    needsLocalModel: true,
  );

  @override
  Future<void> prepare({void Function(double fraction)? onProgress}) {
    return _service.initialize(
      model: _settings.whisperModel,
      onDownloadProgress: (download) => onProgress?.call(download.fraction),
      httpClient: _networkGuard.httpClientFor(
        NetworkFeature.voiceModelDownload,
        purpose: 'Download voice model (${_settings.whisperModel})',
      ),
    );
  }

  @override
  Future<void> startRecording() => _service.startRecording();

  @override
  Future<SpeechResult> stopAndTranscribe({void Function(double fraction)? onProgress}) {
    return _service.stopAndTranscribe(
      onProgress: onProgress == null ? null : (percent) => onProgress(percent / 100),
    );
  }

  /// Ends whichever stage is in flight. Both underlying calls are already
  /// guarded against being made at the wrong time — `cancelRecording`
  /// returns early when nothing is recording, `cancelTranscription` is
  /// null-aware — so this doesn't need to know which stage it's in, and the
  /// controller doesn't need a second cancel path just for local.
  @override
  Future<void> cancel() async {
    _service.cancelTranscription();
    await _service.cancelRecording();
  }

  @override
  Future<void> dispose() => _service.dispose();
}
