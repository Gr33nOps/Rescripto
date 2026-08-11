import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_whisper/flutter_whisper.dart';

import '../engine/cloud/chat_protocol.dart' show joinPath;
import '../engine/engine_exception.dart';
import '../models/provider_config.dart';
import '../models/speech_result.dart';
import '../services/credentials/credential_store.dart';
import '../services/network/network_feature.dart';
import '../services/network/network_guard.dart';
import 'speech_engine.dart';

/// [SpeechEngine] over a cloud provider's OpenAI-compatible transcription
/// endpoint — reuses [ProviderConfig] rather than a second credential
/// system, gated on [ProviderPreset.supportsSpeech] by whoever constructs
/// this.
///
/// Recording itself still happens on-device via the vendored `Whisper`
/// engine's `startRecording`/`stopRecording` — patched (see
/// `third_party/flutter_whisper/lib/src/whisper.dart`) to work without a
/// local model ever being loaded, since audio capture has no dependency on
/// one. Only the finished WAV leaves the device, uploaded once, not
/// streamed — a live audio API is a different, harder integration this
/// does not attempt.
class CloudSpeechEngine implements SpeechEngine {
  CloudSpeechEngine(this._provider, this._credentialStore, this._networkGuard);

  final ProviderConfig _provider;
  final CredentialStore _credentialStore;
  final NetworkGuard _networkGuard;

  /// Every OpenAI-compatible provider that offers transcription uses this
  /// model name convention. Not yet user-configurable, the way
  /// `cloudModelRef` is for rewriting — a reasonable starting default
  /// rather than a second per-provider model picker.
  static const _transcriptionModel = 'whisper-1';

  final Whisper _recorder = Whisper();

  @override
  String get id => 'cloud.openaiCompatible';

  @override
  SpeechCapabilities get capabilities => const SpeechCapabilities(
    requiresNetwork: true,
    auditableEgress: true,
    needsLocalModel: false,
  );

  @override
  Future<void> prepare({void Function(double fraction)? onProgress}) async {}

  @override
  Future<void> startRecording() => _recorder.startRecording();

  @override
  Future<SpeechResult> stopAndTranscribe({void Function(double fraction)? onProgress}) async {
    final wavPath = await _recorder.stopRecording();
    try {
      final secret = await _credentialStore.read(_provider.credential);
      if (secret == null) {
        throw ProviderNotConfiguredException(_provider.id);
      }

      final dio = _networkGuard.dioFor(
        NetworkFeature.cloudSpeech,
        purpose: 'Cloud speech via ${_provider.displayName}',
      );
      final uri = joinPath(_provider.baseUrl, 'audio/transcriptions');
      final form = FormData.fromMap({
        'model': _transcriptionModel,
        'file': await MultipartFile.fromFile(wavPath, filename: 'audio.wav'),
      });

      final response = await dio.post<Map<String, dynamic>>(
        uri.toString(),
        data: form,
        options: Options(
          headers: {
            ..._provider.preset.extraHeaders,
            ..._provider.extraHeaders,
            'Authorization': 'Bearer $secret',
          },
        ),
      );

      final text = response.data?['text'] as String? ?? '';
      return SpeechResult(text: text.trim(), language: '');
    } finally {
      await _deleteFile(wavPath);
    }
  }

  @override
  Future<void> cancel() async {
    final path = await _recorder.stopRecording();
    await _deleteFile(path);
  }

  @override
  Future<void> dispose() async {}

  Future<void> _deleteFile(String path) async {
    final file = File(path);
    if (await file.exists()) await file.delete();
  }
}
