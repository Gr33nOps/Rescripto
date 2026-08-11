import '../../models/provider_config.dart';
import '../engine_exception.dart';
import '../engine_request.dart';
import 'sse_decoder.dart';

/// What decoding one [SseEvent] produced.
///
/// [ErrorProtocolChunk] exists because a provider can fail *inside* an
/// HTTP-200 stream — Anthropic sends `event: error` mid-stream, and a
/// `finish_reason: content_filter` arrives the same way on all three
/// protocols. A status-code-only error path would miss both entirely.
sealed class ProtocolChunk {
  const ProtocolChunk();
}

/// New text since the last chunk — never the accumulated string.
final class TextProtocolChunk extends ProtocolChunk {
  const TextProtocolChunk(this.text);

  final String text;
}

/// The stream ended normally. `finishReason == 'length'` is not an error —
/// the caller completes with whatever text has been accumulated.
final class DoneProtocolChunk extends ProtocolChunk {
  const DoneProtocolChunk({this.finishReason});

  final String? finishReason;
}

/// The provider reported a failure from inside an otherwise-200 stream.
final class ErrorProtocolChunk extends ProtocolChunk {
  const ErrorProtocolChunk(this.error);

  final EngineException error;
}

/// One wire protocol's shape: OpenAI chat-completions, Anthropic messages,
/// or Gemini's `streamGenerateContent`. `CloudRewriteEngine` is the same
/// class for all three; only the [ChatProtocol] implementation differs —
/// mirroring how `ChatTemplate.forFamily` lets one local engine serve three
/// model families.
abstract interface class ChatProtocol {
  /// Where to POST for [provider] + [modelRef].
  Uri pathFor(ProviderConfig provider, String modelRef);

  /// Static headers — content type, protocol version, preset quirk headers
  /// like OpenRouter's `HTTP-Referer`. Never a credential; see [authHeader].
  Map<String, String> headers(ProviderConfig provider);

  /// The one header that carries the credential, kept separate from
  /// [headers] so no header map assembled elsewhere can carry one by
  /// accident, and so a test can assert exactly where a key is sent.
  MapEntry<String, String> authHeader(ProviderConfig provider, String secret);

  /// The JSON request body for [request] against [modelRef].
  Map<String, Object?> body(ProviderConfig provider, EngineRequest request, String modelRef);

  /// Turns one decoded SSE event into a chunk, or null if it carries nothing
  /// this app acts on (a ping, a content-block-start marker, and so on).
  ProtocolChunk? decode(SseEvent event);

  /// Classifies a non-2xx HTTP response that arrived *before* any streaming
  /// began. Mid-stream failures go through [decode] and
  /// [ErrorProtocolChunk] instead, since by then the response was a 200.
  EngineException classifyError(ProviderConfig provider, int? statusCode, Object? body);
}

/// Appends [suffix] to [base]'s path, preserving scheme/host/port/query.
///
/// `Uri.resolve` is the wrong tool here: resolving a relative reference
/// against a base whose path has no trailing slash *replaces* its last
/// segment per RFC 3986, which would silently drop `/v1` from a base like
/// `https://api.openai.com/v1`.
Uri joinPath(Uri base, String suffix) {
  final trimmedBase = base.path.endsWith('/')
      ? base.path.substring(0, base.path.length - 1)
      : base.path;
  final trimmedSuffix = suffix.startsWith('/') ? suffix.substring(1) : suffix;
  return base.replace(path: '$trimmedBase/$trimmedSuffix');
}

/// Digs [path] out of a decoded JSON [body] and returns it only if it looks
/// like a short provider error code, not free text — bounded length,
/// identifier-shaped. `describeEngineError` renders this as user-facing
/// text, and provider error *messages* routinely echo org/project ids and
/// occasionally a truncated key; codes like `context_length_exceeded` or
/// `insufficient_quota` are a small fixed vocabulary the provider controls,
/// which is what makes them safe to allow-list instead of the message body.
final _safeCodePattern = RegExp(r'^[A-Za-z0-9_.\-]{1,64}$');

String? extractSafeErrorCode(Object? body, List<String> path) {
  Object? node = body;
  for (final key in path) {
    if (node is! Map) return null;
    node = node[key];
  }
  if (node is! String) return null;
  return _safeCodePattern.hasMatch(node) ? node : null;
}
