import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_whisper/flutter_whisper.dart';

import '../engine/cloud/chat_protocol.dart' show joinPath;
import '../engine/cloud/cloud_error_mapper.dart';
import '../engine/cloud/openai_compatible_protocol.dart';
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

  /// OpenAI uses `whisper-1`; Groq exposes Whisper under its own model ids.
  /// This is intentionally selected from the provider preset, not the text
  /// model picker, because speech models are a separate API capability.
  String get _transcriptionModel =>
      _provider.presetId == 'groq' ? 'whisper-large-v3-turbo' : 'whisper-1';

  final Whisper _recorder = Whisper();
  static const _errorMapper = CloudErrorMapper();
  static const _protocol = OpenAiCompatibleProtocol();

  @override
  String get id => 'cloud.openaiCompatible';

  @override
  SpeechCapabilities get capabilities => const SpeechCapabilities(
    requiresNetwork: true,
    auditableEgress: true,
    needsLocalModel: false,
  );

  @override
  Future<void> prepare({void Function(double fraction)? onProgress}) async {
    // Fail before opening the microphone when Cloud is selected without a
    // usable credential. Previously the recording started and the missing
    // key only surfaced after Stop, which looked like a broken microphone.
    final secret = await _credentialStore.read(_provider.credential);
    if (secret == null || secret.trim().isEmpty) {
      throw ProviderNotConfiguredException(_provider.id);
    }
  }

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
      final xaiSpeech = _isXaiSpeechProvider;
      final uri = joinPath(
        _provider.baseUrl,
        xaiSpeech ? 'stt' : 'audio/transcriptions',
      );
      // xAI requires the file to be the final multipart field and uses the
      // /stt endpoint instead of OpenAI's /audio/transcriptions contract.
      final form = xaiSpeech
          ? FormData.fromMap({
              'format': 'true',
              'language': 'en',
              'file': await MultipartFile.fromFile(wavPath, filename: 'audio.wav'),
            })
          : FormData.fromMap({
              'model': _transcriptionModel,
              'file': await MultipartFile.fromFile(wavPath, filename: 'audio.wav'),
            });

      late final Response<Map<String, dynamic>> response;
      try {
        response = await dio.post<Map<String, dynamic>>(
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
      } catch (error) {
        // NetworkGuard deliberately wraps policy blocks in DioException.
        // Classify the wrapped error before it reaches the generic speech
        // fallback, so cloud voice never presents a local-model message.
        throw _errorMapper.map(
          error,
          provider: _provider,
          protocol: _protocol,
        );
      }

      final text = response.data?['text'] as String? ?? '';
      if (text.trim().isEmpty) throw const EmptyResponseException();
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

  bool get _isXaiSpeechProvider =>
      _provider.presetId == 'xai' || _provider.baseUrl.host == 'api.x.ai';
}
