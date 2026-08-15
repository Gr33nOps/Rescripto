part of 'package:flutter_whisper/flutter_whisper.dart';

/// Errors that can occur during Whisper transcription.
class WhisperError implements Exception {
  final String message;
  final WhisperErrorCode code;
  final String? nativeCode;
  final WhisperNativeSupport? nativeSupport;

  WhisperError(
    this.message,
    this.code, {
    this.nativeCode,
    this.nativeSupport,
  });

  @override
  String toString() => 'WhisperError($code): $message';
}

enum WhisperErrorCode {
  modelNotFound,
  modelDownloadFailed,
  initializationFailed,
  permissionDenied,
  audioRecordingFailed,
  transcriptionFailed,
  invalidOptions,
  modelLoadFailed,
  nativeUnavailable,
  engineNotInitialized,
  sessionFailed,
  cancelled,
  downloadPaused,
  unknown,
}
