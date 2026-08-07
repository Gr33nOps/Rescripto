import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/speech_result.dart';
import '../services/speech_service.dart';

enum SpeechPhase { idle, requestingPermission, initializing, recording, transcribing }

/// Voice input flow: push-to-talk / continuous dictation.
class SpeechController extends ChangeNotifier {
  SpeechController(this._service);

  final SpeechService _service;

  SpeechPhase _phase = SpeechPhase.idle;
  String _partialText = '';
  String _lastError = '';

  SpeechPhase get phase => _phase;
  String get partialText => _partialText;
  String get lastError => _lastError;
  bool get isBusy => _phase != SpeechPhase.idle;
  bool get isRecording => _phase == SpeechPhase.recording;
  bool get isSupported => _service.isSupported;

  /// Starts a push-to-talk session; returns the final transcript.
  /// UI calls [start] then [stopAndTranscribe] to end dictation.
  Future<void> start() async {
    _lastError = '';
    if (_phase != SpeechPhase.idle) return;

    try {
      _phase = SpeechPhase.requestingPermission;
      notifyListeners();

      if (!await Permission.microphone.request().isGranted) {
        _lastError = 'Microphone permission is required for voice input.';
        _phase = SpeechPhase.idle;
        notifyListeners();
        return;
      }

      _phase = SpeechPhase.initializing;
      notifyListeners();
      await _service.initialize();

      _phase = SpeechPhase.recording;
      await _service.startRecording();
      _partialText = '';
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
    final result = await _service.stopAndTranscribe();
    _partialText = result.text;
    _phase = SpeechPhase.idle;
    notifyListeners();
    return result;
  }

  Future<void> cancel() async {
    await _service.cancelRecording();
    _phase = SpeechPhase.idle;
    notifyListeners();
  }

  void clearPartial() {
    _partialText = '';
    notifyListeners();
  }
}
