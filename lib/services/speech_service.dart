import 'dart:io';

import 'package:flutter_whisper/flutter_whisper.dart';

import '../models/speech_result.dart';

/// Local speech-to-text (whisper.cpp). No cloud, no API keys.
///
/// Currently fully supported on Android. On other platforms a clear
/// "not yet available" error is surfaced so the UI can guide the user.
class SpeechService {
  Whisper? _whisper;
  bool _initialized = false;
  bool _recording = false;
  String? _loadedModel;

  bool get isRecording => _recording;
  bool get isSupported => Platform.isAndroid;
  bool get isInitialized => _initialized;

  Future<void> initialize({
    String model = 'small',
    void Function(WhisperDownloadProgress)? onDownloadProgress,
  }) async {
    if (!isSupported) {
      throw UnsupportedError(
        'On-device voice input is not available on this platform yet.',
      );
    }
    if (_initialized && _loadedModel == model) return;
    if (_initialized) await dispose();
    _whisper = Whisper();
    await _whisper!.initialize(
      model: _modelFromString(model),
      onProgress: onDownloadProgress,
    );
    _initialized = true;
    _loadedModel = model;
  }

  Future<void> startRecording() async {
    if (!isSupported) throw UnsupportedError('Voice input not supported here.');
    if (!_initialized || _whisper == null) {
      throw StateError('Speech model is not initialized.');
    }
    await _whisper!.startRecording();
    _recording = true;
  }

  /// Stops recording and returns the transcription of what was said.
  Future<SpeechResult> stopAndTranscribe({
    void Function(int)? onProgress,
  }) async {
    if (!_recording) {
      return const SpeechResult(text: '', language: '');
    }
    _recording = false;
    final wavPath = await _whisper!.stopRecording();
    try {
      final result = await _whisper!.transcribeFile(
        wavPath,
        onProgress: onProgress,
      );
      return SpeechResult(text: result.text.trim(), language: result.language);
    } finally {
      await _deleteRecording(wavPath);
    }
  }

  /// Cancels recording without transcribing.
  Future<void> cancelRecording() async {
    if (!_recording) return;
    _recording = false;
    final wavPath = await _whisper!.stopRecording();
    await _deleteRecording(wavPath);
  }

  void cancelTranscription() => _whisper?.cancel();

  Future<void> dispose() async {
    await _whisper?.dispose();
    _whisper = null;
    _initialized = false;
    _recording = false;
    _loadedModel = null;
  }

  static WhisperModel _modelFromString(String model) {
    return switch (model) {
      'tiny' => WhisperModel.tiny,
      'base' => WhisperModel.base,
      'small' => WhisperModel.small,
      'medium' => WhisperModel.medium,
      'large' => WhisperModel.large,
      _ => WhisperModel.small,
    };
  }

  Future<void> _deleteRecording(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
