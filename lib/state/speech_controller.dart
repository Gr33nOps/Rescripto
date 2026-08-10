import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_whisper/flutter_whisper.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/speech_result.dart';
import '../services/settings_service.dart';
import '../services/speech_service.dart';

enum SpeechPhase {
  idle,
  requestingPermission,
  downloadingModel,
  initializing,
  recording,
  transcribing,
}

/// Voice input flow: push-to-talk / continuous dictation.
class SpeechController extends ChangeNotifier {
  SpeechController(this._service, this._settings);

  final SpeechService _service;
  final SettingsService _settings;

  SpeechPhase _phase = SpeechPhase.idle;
  String _partialText = '';
  String _lastError = '';
  double _progress = 0;
  String _downloadSize = '';
  int _operationId = 0;

  SpeechPhase get phase => _phase;
  String get partialText => _partialText;
  String get lastError => _lastError;
  double get progress => _progress;

  /// Human-readable size of the voice model being fetched, e.g. "141 MB".
  String get downloadSize => _downloadSize;
  bool get isBusy => _phase != SpeechPhase.idle;
  bool get isRecording => _phase == SpeechPhase.recording;
  bool get isSupported => _service.isSupported;

  /// Starts a push-to-talk session; returns the final transcript.
  /// UI calls [start] then [stopAndTranscribe] to end dictation.
  Future<void> start() async {
    _lastError = '';
    if (_phase != SpeechPhase.idle) return;
    if (!isSupported) {
      _lastError =
          'On-device voice input is currently available on Android only.';
      notifyListeners();
      return;
    }
    final operationId = ++_operationId;

    try {
      _phase = SpeechPhase.requestingPermission;
      notifyListeners();

      if (!await Permission.microphone.request().isGranted) {
        if (operationId != _operationId) return;
        _lastError = 'Microphone permission is required for voice input.';
        _phase = SpeechPhase.idle;
        notifyListeners();
        return;
      }

      if (operationId != _operationId) return;
      _phase = SpeechPhase.initializing;
      _progress = 0;
      _downloadSize = SpeechService.downloadSizeFor(_settings.whisperModel);
      notifyListeners();
      await _service.initialize(
        model: _settings.whisperModel,
        onDownloadProgress: (download) {
          if (operationId != _operationId) return;
          // A first-run model download takes minutes; without saying so the
          // spinner is indistinguishable from a hang.
          _phase = SpeechPhase.downloadingModel;
          _progress = download.fraction;
          notifyListeners();
        },
      );
      if (operationId != _operationId) return;
      _phase = SpeechPhase.initializing;
      _progress = 0;
      notifyListeners();

      if (operationId != _operationId) return;
      await _service.startRecording();
      if (operationId != _operationId) {
        await _service.cancelRecording();
        return;
      }
      _phase = SpeechPhase.recording;
      _partialText = '';
      _progress = 0;
      notifyListeners();
    } catch (e) {
      _lastError = e is UnsupportedError
          ? (e.message ?? 'Voice input is not supported on this platform.')
          : _friendlySpeechError(e, starting: true);
      _phase = SpeechPhase.idle;
      notifyListeners();
    }
  }

  /// Ends the session and returns the transcribed text.
  Future<SpeechResult> stopAndTranscribe() async {
    if (_phase != SpeechPhase.recording) {
      return const SpeechResult(text: '', language: '');
    }
    final operationId = _operationId;
    _phase = SpeechPhase.transcribing;
    _progress = 0;
    notifyListeners();
    try {
      final result = await _service.stopAndTranscribe(
        onProgress: (percent) {
          if (operationId != _operationId) return;
          _progress = (percent / 100).clamp(0, 1);
          notifyListeners();
        },
      );
      if (operationId == _operationId) _partialText = result.text;
      return result;
    } catch (e) {
      if (operationId == _operationId) {
        _lastError = _friendlySpeechError(e, starting: false);
      }
      return const SpeechResult(text: '', language: '');
    } finally {
      if (operationId == _operationId) {
        _phase = SpeechPhase.idle;
        _progress = 0;
        notifyListeners();
      }
    }
  }

  String _friendlySpeechError(Object error, {required bool starting}) {
    // Match on the typed failure first. Everything used to collapse into
    // "Couldn't start voice input", which told nobody whether the download
    // failed, the disk was full, or the microphone was busy.
    if (error is WhisperError) {
      switch (error.code) {
        case WhisperErrorCode.modelDownloadFailed:
        case WhisperErrorCode.modelNotFound:
          return 'The voice model couldn’t be downloaded. Check your '
              'connection and free storage, then tap the mic again — it '
              'resumes where it left off.';
        case WhisperErrorCode.downloadPaused:
          return 'Voice model download paused. Tap the mic to resume.';
        case WhisperErrorCode.cancelled:
          return 'Voice input cancelled.';
        case WhisperErrorCode.modelLoadFailed:
        case WhisperErrorCode.initializationFailed:
          return 'The voice model is on this device but couldn’t be opened. '
              'Free some memory, or pick a smaller voice model in Settings.';
        case WhisperErrorCode.permissionDenied:
          return 'Microphone permission is required for voice input.';
        case WhisperErrorCode.audioRecordingFailed:
          return 'The microphone isn’t available. Close other apps that may '
              'be using it and try again.';
        case WhisperErrorCode.transcriptionFailed:
        case WhisperErrorCode.engineNotInitialized:
        case WhisperErrorCode.sessionFailed:
        case WhisperErrorCode.invalidOptions:
        case WhisperErrorCode.unknown:
          break;
      }
    }

    if (error is PlatformException) {
      switch (error.code) {
        case 'NATIVE_NOT_BUILT':
          return 'Voice input isn’t supported on this device’s processor.';
        case 'MODEL_NOT_FOUND':
          return 'The voice model file is missing. Tap the mic to download it '
              'again.';
        case 'MIC_UNAVAILABLE':
        case 'NO_CONTEXT':
          return 'The microphone isn’t available. Close other apps that may '
              'be using it and try again.';
        case 'WRITE_FAILED':
          return 'Couldn’t save the recording. Free some storage and try '
              'again.';
        case 'INITIALIZATION_FAILED':
          return 'The voice model couldn’t be opened. Free some memory, or '
              'pick a smaller voice model in Settings.';
      }
    }

    final text = error.toString().toLowerCase();
    if (text.contains('space') ||
        text.contains('storage') ||
        text.contains('enospc')) {
      return 'Not enough storage for voice input. Free some space and try again.';
    }
    if (text.contains('network') ||
        text.contains('connection') ||
        text.contains('socket') ||
        text.contains('timeout')) {
      return 'Couldn’t download the voice model. Check your connection and try again.';
    }
    return starting
        ? 'Couldn’t start voice input. Try again.'
        : 'Couldn’t transcribe this recording. Try recording again.';
  }

  Future<void> cancel() async {
    final phase = _phase;
    _operationId++;
    if (phase == SpeechPhase.recording) {
      await _service.cancelRecording();
    } else if (phase == SpeechPhase.transcribing) {
      _service.cancelTranscription();
    }
    _phase = SpeechPhase.idle;
    _progress = 0;
    notifyListeners();
  }

  void clearPartial() {
    _partialText = '';
    notifyListeners();
  }
}
