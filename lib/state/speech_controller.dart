import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/speech_result.dart';
import '../services/settings_service.dart';
import '../services/speech_service.dart';

enum SpeechPhase {
  idle,
  requestingPermission,
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
  int _operationId = 0;

  SpeechPhase get phase => _phase;
  String get partialText => _partialText;
  String get lastError => _lastError;
  double get progress => _progress;
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
      notifyListeners();
      await _service.initialize(
        model: _settings.whisperModel,
        onDownloadProgress: (download) {
          if (operationId != _operationId) return;
          _progress = download.fraction;
          notifyListeners();
        },
      );

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
          : 'Could not start voice input: $e';
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
        _lastError = 'Could not transcribe the recording: $e';
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
