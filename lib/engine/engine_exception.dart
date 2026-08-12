/// Typed failures a [RewriteEngine] can raise.
///
/// Replaces matching on `e.toString().toLowerCase().contains(...)`: the code
/// that knows *why* something failed — a missing file, a load that returned
/// false, a prompt too long for the context window — now says so directly,
/// instead of a caller downstream re-deriving it from an exception's message.
sealed class EngineException implements Exception {
  const EngineException();
}

/// The model this request targets has not been downloaded.
final class ModelNotInstalledException extends EngineException {
  const ModelNotInstalledException(this.modelRef);

  final String modelRef;
}

/// The engine reported it could not load the model.
final class ModelLoadFailedException extends EngineException {
  const ModelLoadFailedException([this.nativeReason]);

  /// Reason text from the native engine, when it provided one.
  final String? nativeReason;
}

/// The prompt leaves too little of the context window for a useful reply.
///
/// Both counts are nullable: the local engine always knows both, but a cloud
/// provider's error body rarely reports both prompt and context size — only
/// whichever one it chose to mention.
final class ContextOverflowException extends EngineException {
  const ContextOverflowException({this.promptTokens, this.contextSize});

  final int? promptTokens;
  final int? contextSize;
}

/// Generation completed but produced no usable text.
final class EmptyResponseException extends EngineException {
  const EmptyResponseException();
}

/// The model declined to rewrite the text, or replied that it could not see
/// any text to rewrite, rather than producing a rewrite.
///
/// Distinct from [ContentFilteredException], which is a provider's own
/// filter blocking the request out of band. This is the model itself
/// answering in prose when it was asked to edit — small instruction-tuned
/// models do it to entirely ordinary drafts (a `$24.50` read as payment
/// credentials, say). `RewriteController` retries once with a stricter
/// prompt before surfacing this; see `RefusalDetector`.
final class ModelRefusedException extends EngineException {
  const ModelRefusedException();
}

/// The request was cancelled before it produced a result.
final class GenerationCancelledException extends EngineException {
  const GenerationCancelledException();
}

/// The device could not satisfy the memory the engine needed.
final class OutOfMemoryException extends EngineException {
  const OutOfMemoryException();
}

/// A failure the engine could not classify more specifically.
final class UnknownEngineException extends EngineException {
  const UnknownEngineException([this.nativeReason]);

  final String? nativeReason;
}

/// No [RewriteEngine] is registered for the requested [EngineTarget.engineId].
///
/// Replaces a bare `StateError` from `EngineRegistry.resolve`, which nothing
/// in the rewrite path could catch — a build-time caller like
/// `RewriteController.capabilities` needs a typed failure it can turn into
/// `EngineRegistry.maybeResolve` returning null instead of crashing `build()`.
final class EngineNotAvailableException extends EngineException {
  const EngineNotAvailableException(this.engineId);

  final String engineId;
}

/// Why a cloud request was refused before it ever reached the network.
///
/// Deliberately its own enum rather than a re-export of
/// `lib/services/network`'s `NetworkBlockReason` — the engine layer stays
/// free of a dependency on the network layer's types, even though a cloud
/// engine's error mapper translates one into the other.
enum CloudBlockReason {
  /// The global "disable all network access" switch is on.
  killSwitch,

  /// The `cloudRewrite` (or `cloudSpeech`) feature is turned off.
  featureDisabled,

  /// The outgoing request carried a secret in its query string, which this
  /// app refuses to send.
  secretInUrl,
}

/// A cloud request was blocked by network policy before it left the device.
///
/// The one case `RewriteController.rewrite()` must never fold into a silent
/// empty result — "your text was blocked from leaving the device" has to
/// reach the user, not disappear the way a bare `GenerationCancelledException`
/// would.
final class CloudAccessBlockedException extends EngineException {
  const CloudAccessBlockedException(this.reason);

  final CloudBlockReason reason;
}

/// The target provider has no credential (or config) saved for it yet.
final class ProviderNotConfiguredException extends EngineException {
  const ProviderNotConfiguredException(this.providerId);

  final String providerId;
}

/// The provider rejected the request's credential (HTTP 401/403).
final class ProviderAuthException extends EngineException {
  const ProviderAuthException(this.providerId);

  final String providerId;
}

/// The provider is rate-limiting this credential (HTTP 429).
final class RateLimitedException extends EngineException {
  const RateLimitedException([this.retryAfter]);

  final Duration? retryAfter;
}

/// The account's quota or balance is exhausted (HTTP 402 / `insufficient_quota`).
final class QuotaExhaustedException extends EngineException {
  const QuotaExhaustedException();
}

/// The provider itself is failing (5xx, `overloaded_error`, HTTP 529).
final class ProviderUnavailableException extends EngineException {
  const ProviderUnavailableException([this.statusCode]);

  final int? statusCode;
}

/// The request could not reach the provider at all (timeout, DNS, connection
/// refused) — distinct from [CloudAccessBlockedException], which never left
/// the device in the first place.
final class NetworkUnavailableException extends EngineException {
  const NetworkUnavailableException();
}

/// The provider refused to generate on content-safety grounds
/// (`content_filter` / `refusal` / `SAFETY` / `RECITATION`).
final class ContentFilteredException extends EngineException {
  const ContentFilteredException();
}
