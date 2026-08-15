import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_whisper/flutter_whisper.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/speech_result.dart';
import '../engine/local/local_engine_host.dart';
import '../services/network/network_exceptions.dart';
import '../services/settings_service.dart';
import '../services/speech_service.dart';
import '../speech/speech_engine.dart';
import '../speech/speech_engine_resolver.dart';

enum SpeechPhase {
  idle,
  requestingPermission,
  downloadingModel,
  initializing,
  recording,
  transcribing,
}

/// Device-level voice availability. This is intentionally typed: UI state
/// must never be inferred from words such as "support" in an error message.
enum SpeechAvailability { available, retryableFailure, unsupported }

@visibleForTesting
SpeechAvailability speechAvailabilityForError(Object error) {
  if (error is UnsupportedError) return SpeechAvailability.unsupported;
  if (error is WhisperError &&
      error.code == WhisperErrorCode.nativeUnavailable) {
    return error.nativeCode == 'ABI_UNSUPPORTED'
        ? SpeechAvailability.unsupported
        : SpeechAvailability.retryableFailure;
  }
  if (error is PlatformException) {
    if (error.code == 'ABI_UNSUPPORTED') {
      return SpeechAvailability.unsupported;
    }
    if (error.code == 'NATIVE_NOT_BUILT' ||
        error.code == 'NATIVE_LOAD_FAILED' ||
        error.code == 'NATIVE_CHECK_FAILED' ||
        error.code == 'JNI_SMOKE_TEST_FAILED') {
      return SpeechAvailability.retryableFailure;
    }
  }
  return SpeechAvailability.available;
}

/// Voice input flow: push-to-talk / continuous dictation.
///
/// Runs whichever [SpeechEngine] `SpeechEngineResolver` picks for the
/// current `speechEngine` setting, rather than reaching for [SpeechService]
/// directly. It used to do the latter unconditionally, which meant the
/// Local/Cloud setting was stored, backed up, restorable — and read by
/// nothing, so choosing Cloud transcribed on-device anyway.
class SpeechController extends ChangeNotifier {
  SpeechController(
    this._service,
    this._settings,
    this._resolver,
    this._localEngineHost,
  ) : _availability = _service.isSupported
          ? SpeechAvailability.available
          : SpeechAvailability.unsupported;

  /// Retained only for [isSupported] — the platform check. Every actual
  /// recording/transcription call now goes through [_resolver]'s engine.
  final SpeechService _service;
  final SettingsService _settings;
  final SpeechEngineResolver _resolver;
  final LocalEngineHost _localEngineHost;

  /// The engine for the session in flight. Resolved once at [start] so a
  /// setting changed mid-recording can't strand `stopAndTranscribe` on a
  /// different engine than the one holding the audio.
  SpeechEngine? _engine;

  SpeechPhase _phase = SpeechPhase.idle;
  String _partialText = '';
  String _lastError = '';
  double _progress = 0;
  String _downloadSize = '';
  int _operationId = 0;
  SpeechAvailability _availability;

  SpeechPhase get phase => _phase;
  String get partialText => _partialText;
  String get lastError => _lastError;
  double get progress => _progress;

  /// Human-readable size of the voice model being fetched, e.g. "141 MB".
  String get downloadSize => _downloadSize;
  bool get isBusy => _phase != SpeechPhase.idle;
  bool get isRecording => _phase == SpeechPhase.recording;
  bool get isSupported => _service.isSupported;
  SpeechAvailability get availability => _availability;

  /// Starts a push-to-talk session; returns the final transcript.
  /// UI calls [start] then [stopAndTranscribe] to end dictation.
  Future<void> start() async {
    _lastError = '';
    if (_phase != SpeechPhase.idle) return;
    if (!isSupported) {
      _availability = SpeechAvailability.unsupported;
      _lastError =
          'On-device voice input is currently available on Android only.';
      notifyListeners();
      return;
    }
    _availability = SpeechAvailability.available;
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
      final engine = _resolver.resolve();
      _engine = engine;

      // llama.cpp and whisper.cpp each keep a large model plus working
      // buffers in native memory. Holding both at once can make Android kill
      // the process on otherwise supported phones before either library can
      // return an out-of-memory error. A local voice session does not need
      // the rewrite model, so release it before Whisper allocates anything.
      // The downloaded GGUF file is untouched and is loaded again on the
      // next rewrite.
      if (engine.capabilities.needsLocalModel) {
        await _localEngineHost.releaseLoadedModel();
      }
      if (operationId != _operationId) return;

      _phase = SpeechPhase.initializing;
      _progress = 0;
      _downloadSize = SpeechService.downloadSizeFor(_settings.whisperModel);
      notifyListeners();
      await engine.prepare(
        onProgress: (fraction) {
          if (operationId != _operationId) return;
          // A first-run model download takes minutes; without saying so the
          // spinner is indistinguishable from a hang. Cloud engines have
          // nothing to download and simply never call this.
          _phase = SpeechPhase.downloadingModel;
          _progress = fraction;
          notifyListeners();
        },
      );
      if (operationId != _operationId) return;
      _phase = SpeechPhase.initializing;
      _progress = 0;
      notifyListeners();

      if (operationId != _operationId) return;
      await engine.startRecording();
      if (operationId != _operationId) {
        await engine.cancel();
        return;
      }
      _phase = SpeechPhase.recording;
      _availability = SpeechAvailability.available;
      _partialText = '';
      _progress = 0;
      notifyListeners();
    } catch (e) {
      final failedEngine = _engine;
      _engine = null;
      if (failedEngine != null) {
        try {
          await failedEngine.dispose();
        } catch (_) {
          // Keep the original startup error. Cleanup is best-effort here.
        }
      }
      _availability = speechAvailabilityForError(e);
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
    final engine = _engine;
    if (engine == null) return const SpeechResult(text: '', language: '');
    final operationId = _operationId;
    _phase = SpeechPhase.transcribing;
    _progress = 0;
    notifyListeners();
    try {
      final result = await engine.stopAndTranscribe(
        onProgress: (fraction) {
          if (operationId != _operationId) return;
          _progress = fraction.clamp(0, 1);
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
        _engine = null;
        try {
          await engine.dispose();
        } catch (_) {
          // Transcription has already completed or produced its real error.
          // A cleanup failure must not replace that result.
        }
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
    if (error is SpeechEngineUnavailable) return error.message;

    if (error is NetworkBlockedByPolicyException) {
      // A deliberate block, not a network fault — the generic "check your
      // connection" fallback below would send someone chasing a problem
      // that doesn't exist.
      return error.reason == NetworkBlockReason.killSwitch
          ? 'Network access is turned off. Turn it back on in Settings to '
                'download the voice model.'
          : 'Voice model downloads are turned off in Settings.';
    }

    if (error is WhisperError) {
      switch (error.code) {
        case WhisperErrorCode.modelDownloadFailed:
        case WhisperErrorCode.modelNotFound:
          // flutter_whisper's downloader retries any exception from the
          // client — including a deliberate policy block — up to maxRetries
          // times with exponential backoff before giving up and wrapping
          // whatever it caught into this generic code. There's no hook to
          // stop it retrying something that will never succeed without
          // forking that retry loop, so the best available fix is
          // recognising the wrapped cause here once it does surface.
          if (error.message.contains('NetworkBlockedByPolicyException')) {
            return error.message.contains('killSwitch')
                ? 'Network access is turned off. Turn it back on in Settings '
                      'to download the voice model.'
                : 'Voice model downloads are turned off in Settings.';
          }
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
        case WhisperErrorCode.nativeUnavailable:
          return error.message;
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
        case 'NATIVE_LOAD_FAILED':
        case 'NATIVE_CHECK_FAILED':
        case 'JNI_SMOKE_TEST_FAILED':
          return error.message ??
              'The on-device voice library could not load. Tap Retry.';
        case 'ABI_UNSUPPORTED':
          return error.message ??
              'On-device voice requires a 64-bit ARM Android system.';
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
    final engine = _engine;
    _operationId++;
    if (engine != null &&
        (phase == SpeechPhase.recording || phase == SpeechPhase.transcribing)) {
      // One call for both stages — see LocalWhisperSpeechEngine.cancel for
      // why the engine, not this controller, is the right place to know
      // which underlying call applies.
      await engine.cancel();
    }
    _engine = null;
    if (engine != null) {
      try {
        await engine.dispose();
      } catch (_) {
        // Cancellation still succeeds even if native cleanup reports an
        // error. The next session creates a fresh engine.
      }
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
