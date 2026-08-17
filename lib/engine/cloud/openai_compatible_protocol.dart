import 'dart:convert';

import '../../models/provider_config.dart';
import '../engine_exception.dart';
import '../engine_request.dart';
import 'chat_protocol.dart';
import 'sse_decoder.dart';

/// OpenAI's chat-completions shape — also spoken by Groq, OpenRouter,
/// Mistral, Together, Ollama, and any OpenAI-compatible custom endpoint.
///
/// `POST {base}/chat/completions`, `data: [DONE]` terminates the stream,
/// text arrives at `choices[0].delta.content`.
class OpenAiCompatibleProtocol implements ChatProtocol {
  const OpenAiCompatibleProtocol();

  @override
  Uri pathFor(ProviderConfig provider, String modelRef) =>
      joinPath(provider.baseUrl, 'chat/completions');

  @override
  Map<String, String> headers(ProviderConfig provider) => {
    'Content-Type': 'application/json',
    ...provider.preset.extraHeaders,
    ...provider.extraHeaders,
  };

  @override
  MapEntry<String, String> authHeader(ProviderConfig provider, String secret) =>
      MapEntry('Authorization', 'Bearer $secret');

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

    final map = <String, Object?>{
      'model': modelRef,
      'messages': [
        {'role': 'system', 'content': request.prompt.system},
        {'role': 'user', 'content': request.prompt.user},
      ],
      'stream': true,
      'temperature': temperature,
      'top_p': options.topP,
      if (stops.isNotEmpty) 'stop': stops,
    };

    // repeatPenalty and topK are llama.cpp sampling knobs with no
    // equivalent here — dropped rather than mapped onto a differently-shaped
    // parameter, which would make the slider lie about what it does.
    if (preset.usesMaxCompletionTokens) {
      map['max_completion_tokens'] = options.maxOutputTokens;
    } else {
      map['max_tokens'] = options.maxOutputTokens;
    }
    if (preset.supportsUsageInStream) {
      map['stream_options'] = {'include_usage': true};
    }
    return map;
  }

  @override
  ProtocolChunk? decode(SseEvent event) {
    if (event.data == '[DONE]') return const DoneProtocolChunk();

    final Object? json;
    try {
      json = jsonDecode(event.data);
    } catch (_) {
      return null;
    }
    if (json is! Map) return null;

    final choices = json['choices'];
    if (choices is! List || choices.isEmpty) return null;
    final choice = choices.first;
    if (choice is! Map) return null;

    final finishReason = choice['finish_reason'] as String?;
    if (finishReason == 'content_filter') {
      return const ErrorProtocolChunk(ContentFilteredException());
    }

    final delta = choice['delta'];
    final text = delta is Map ? delta['content'] as String? : null;
    if (text != null && text.isNotEmpty) return TextProtocolChunk(text);

    if (finishReason != null) return DoneProtocolChunk(finishReason: finishReason);
    return null;
  }

  @override
  EngineException classifyError(ProviderConfig provider, int? statusCode, Object? body) {
    final code = extractSafeErrorCode(body, ['error', 'code']) ??
        extractSafeErrorCode(body, ['error', 'type']);

    if (code == 'context_length_exceeded') {
      return const ContextOverflowException();
    }
    // OpenAI overloads HTTP 429 for both genuine rate-limiting and running
    // out of billing credits — the two are distinguished only by this body
    // code, never by status code alone. `insufficient_quota` is the older,
    // still-current `error.type`; `credit_balance_exhausted` is the newer
    // `error.code` seen directly from a live "no credits remaining"
    // response. Missing either meant that response fell through to
    // UnknownEngineException below and, at the CloudErrorMapper level, got
    // shown to the user as "rate-limited, try again shortly" — which never
    // resolves a zero-balance account no matter how many times it retries.
    if (code == 'insufficient_quota' || code == 'credit_balance_exhausted') {
      return const QuotaExhaustedException();
    }
    return UnknownEngineException(code);
  }
}
