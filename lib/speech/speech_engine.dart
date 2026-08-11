import '../models/speech_result.dart';

/// What a [SpeechEngine] can and needs, independent of any one session.
///
/// Deliberately small, matching `EngineCapabilities`' own doc on the same
/// point: each flag backs an actual decision made elsewhere.
class SpeechCapabilities {
  const SpeechCapabilities({
    required this.requiresNetwork,
    required this.auditableEgress,
    required this.needsLocalModel,
  });

  final bool requiresNetwork;

  /// Whether `NetworkGuard`/`NetworkLog` can actually see this engine's
  /// traffic. False only for the system recognizer: Android's
  /// `SpeechRecognizer` ships audio from native code, a path nothing in
  /// this app's network layer observes. The UI must say so — the network
  /// log screen must not be allowed to imply completeness it doesn't have.
  final bool auditableEgress;

  final bool needsLocalModel;
}

/// A way to turn a recorded utterance into text.
///
/// Deliberately not built on `RewriteEngine`/`GenerationHandle`. Speech is
/// permission → maybe-download → record → transcribe → one transcript, a
/// different shape from streaming deltas over a four-stage progress model —
/// forcing it through `EngineStage` would mean widening that enum for
/// something only speech uses, the mistake `engine_capabilities.dart`
/// already warns against.
abstract interface class SpeechEngine {
  /// Stable id, e.g. `'local.whisper'`, `'cloud.openaiCompatible'`,
  /// `'system.android'`.
  String get id;

  SpeechCapabilities get capabilities;

  /// Readies the engine — for local, downloads/loads the model. A no-op for
  /// cloud and system. [onProgress] reports 0..1 during a local download;
  /// engines with nothing to download simply never call it.
  Future<void> prepare({void Function(double fraction)? onProgress});

  Future<void> startRecording();

  /// Stops recording and returns the transcript. [onProgress] reports
  /// 0..1 during transcription where the engine can report it.
  Future<SpeechResult> stopAndTranscribe({void Function(double fraction)? onProgress});

  /// Stops recording (or transcription) without returning a result.
  Future<void> cancel();

  Future<void> dispose();
}
