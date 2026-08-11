import 'dart:convert';

import '../../models/provider_config.dart';
import '../engine_exception.dart';
import '../engine_request.dart';
import 'chat_protocol.dart';
import 'sse_decoder.dart';

/// Google Gemini's `streamGenerateContent`.
///
/// `POST {base}/models/{modelRef}:streamGenerateContent?alt=sse` — streaming
/// is a query parameter, not a body field. The key goes in the
/// `x-goog-api-key` header, **never** `?key=`: `NetworkGuard` already
/// refuses any `cloudRewrite` request with a secret in its query string, and
/// `network_guard_test.dart` already pins that behaviour. Gemini is also the
/// only one of the three protocols that takes `topK`.
class GeminiProtocol implements ChatProtocol {
  const GeminiProtocol();

  @override
  Uri pathFor(ProviderConfig provider, String modelRef) {
    final withModel = joinPath(provider.baseUrl, 'models/$modelRef:streamGenerateContent');
    return withModel.replace(
      queryParameters: {...withModel.queryParameters, 'alt': 'sse'},
    );
  }

  @override
  Map<String, String> headers(ProviderConfig provider) => {
    'Content-Type': 'application/json',
    ...provider.preset.extraHeaders,
    ...provider.extraHeaders,
  };

  @override
  MapEntry<String, String> authHeader(ProviderConfig provider, String secret) =>
      MapEntry('x-goog-api-key', secret);

  @override
  Map<String, Object?> body(ProviderConfig provider, EngineRequest request, String modelRef) {
    final preset = provider.preset;
    final options = request.options;
    final stops = preset.maxStopSequences == null
        ? options.stopSequences
        : options.stopSequences.take(preset.maxStopSequences!).toList();
    final temperature = preset.maxTemperature == null
        ? options.temperature
        : options.temperature.clamp(0.0, preset.maxTemperature!).toDouble();

    return {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': request.prompt.user},
          ],
        },
      ],
      'systemInstruction': {
        'parts': [
          {'text': request.prompt.system},
        ],
      },
      'generationConfig': {
        'temperature': temperature,
        'topP': options.topP,
        'topK': options.topK,
        'maxOutputTokens': options.maxOutputTokens,
        if (stops.isNotEmpty) 'stopSequences': stops,
      },
    };
  }

  @override
  ProtocolChunk? decode(SseEvent event) {
    final Object? json;
    try {
      json = jsonDecode(event.data);
    } catch (_) {
      return null;
    }
    if (json is! Map) return null;

    final errorObj = json['error'];
    if (errorObj is Map) {
      return ErrorProtocolChunk(_mapStreamError(json));
    }

    final candidates = json['candidates'];
    if (candidates is! List || candidates.isEmpty) return null;
    final candidate = candidates.first;
    if (candidate is! Map) return null;

    final finishReason = candidate['finishReason'] as String?;
    if (finishReason == 'SAFETY' || finishReason == 'RECITATION') {
      return const ErrorProtocolChunk(ContentFilteredException());
    }

    final content = candidate['content'];
    final parts = content is Map ? content['parts'] : null;
    if (parts is List) {
      final text = parts.whereType<Map>().map((p) => p['text']).whereType<String>().join();
      if (text.isNotEmpty) return TextProtocolChunk(text);
    }

    if (finishReason != null) return DoneProtocolChunk(finishReason: finishReason);
    return null;
  }

  EngineException _mapStreamError(Map json) {
    final status = extractSafeErrorCode(json, ['error', 'status']);
    if (status == 'RESOURCE_EXHAUSTED') return const QuotaExhaustedException();
    return UnknownEngineException(status);
  }

  @override
  EngineException classifyError(ProviderConfig provider, int? statusCode, Object? body) {
    final status = extractSafeErrorCode(body, ['error', 'status']);
    if (status == 'RESOURCE_EXHAUSTED') return const QuotaExhaustedException();
    return UnknownEngineException(status);
  }
}
