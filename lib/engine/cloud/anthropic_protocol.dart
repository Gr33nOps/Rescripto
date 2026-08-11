import 'dart:convert';

import '../../models/provider_config.dart';
import '../engine_exception.dart';
import '../engine_request.dart';
import 'chat_protocol.dart';
import 'sse_decoder.dart';

/// Anthropic's Messages API.
///
/// `POST {base}/messages`, auth via `x-api-key` (never `Authorization`),
/// `max_tokens` is required rather than optional, events are named rather
/// than `data:`-only, and there is **no `[DONE]`** — the stream ends at
/// `message_stop`. Anthropic also sends `event: error` mid-stream on an
/// otherwise-200 response (an overloaded model, most commonly), which is why
/// [decode] can return an [ErrorProtocolChunk] on a code path OpenAI's shape
/// never needs to.
class AnthropicProtocol implements ChatProtocol {
  const AnthropicProtocol();

  static const _apiVersion = '2023-06-01';

  @override
  Uri pathFor(ProviderConfig provider, String modelRef) =>
      joinPath(provider.baseUrl, 'messages');

  @override
  Map<String, String> headers(ProviderConfig provider) => {
    'Content-Type': 'application/json',
    'anthropic-version': _apiVersion,
    ...provider.preset.extraHeaders,
    ...provider.extraHeaders,
  };

  @override
  MapEntry<String, String> authHeader(ProviderConfig provider, String secret) =>
      MapEntry('x-api-key', secret);

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
      'model': modelRef,
      // Anthropic's system prompt is a top-level parameter, not a message
      // with a role — the reason PromptSpec keeps `system` split out at all.
      'system': request.prompt.system,
      'messages': [
        {'role': 'user', 'content': request.prompt.user},
      ],
      'max_tokens': options.maxOutputTokens,
      'stream': true,
      'temperature': temperature,
      'top_p': options.topP,
      if (stops.isNotEmpty) 'stop_sequences': stops,
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

    switch (event.event) {
      case 'error':
        return ErrorProtocolChunk(_mapStreamError(json));
      case 'content_block_delta':
        final delta = json['delta'];
        if (delta is Map && delta['type'] == 'text_delta') {
          final text = delta['text'] as String?;
          if (text != null && text.isNotEmpty) return TextProtocolChunk(text);
        }
        return null;
      case 'message_delta':
        final delta = json['delta'];
        final stopReason = delta is Map ? delta['stop_reason'] as String? : null;
        if (stopReason == 'refusal') {
          return const ErrorProtocolChunk(ContentFilteredException());
        }
        return DoneProtocolChunk(finishReason: stopReason);
      case 'message_stop':
        return const DoneProtocolChunk();
      default:
        // message_start, content_block_start/stop, ping — nothing to act on.
        return null;
    }
  }

  EngineException _mapStreamError(Map json) {
    final errorObj = json['error'];
    final type = errorObj is Map ? errorObj['type'] as String? : null;
    if (type == 'overloaded_error') return const ProviderUnavailableException();
    return UnknownEngineException(extractSafeErrorCode(json, ['error', 'type']));
  }

  @override
  EngineException classifyError(ProviderConfig provider, int? statusCode, Object? body) {
    final code = extractSafeErrorCode(body, ['error', 'type']);
    return UnknownEngineException(code);
  }
}
