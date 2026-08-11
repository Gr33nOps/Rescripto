import 'engine_exception.dart';

/// User-facing text for an [EngineException].
///
/// Replaces `RewriteController._describeError`, which parsed the *message*
/// of whatever was thrown looking for words like "context" or "memory". The
/// switch below is exhaustive over [EngineException]'s subtypes — the
/// compiler rejects it if a new subtype is added without a case here, where
/// a substring check would just silently fall through to the generic message.
String describeEngineError(EngineException error) => switch (error) {
  ModelNotInstalledException() =>
    'The AI model is not downloaded yet. Open "AI Models" to install it.',
  ModelLoadFailedException(nativeReason: final reason) =>
    reason == null || reason.isEmpty
        ? 'Couldn’t load the AI model. Try again. If it keeps happening, '
              'restart the app.'
        : reason,
  ContextOverflowException(contextSize: final size) => size == null
      ? 'This text is too long for the model’s context window. Shorten it '
            'or increase Context size in Settings.'
      : 'This text is too long for the $size-token context. Shorten it or '
            'increase Context size in Settings.',
  EmptyResponseException() =>
    'The model returned an empty result. Try a different intensity.',
  OutOfMemoryException() =>
    'Not enough memory on this device. Try a smaller model or lower '
        'context size in Settings.',
  // Cancellation is a user action, not a failure — nothing calls this for it.
  GenerationCancelledException() => 'Cancelled.',
  EngineNotAvailableException() =>
    'That processing target isn’t available right now. Check your '
        'processing mode in Settings.',
  CloudAccessBlockedException(reason: final reason) => switch (reason) {
    CloudBlockReason.killSwitch =>
      'Network access is off (Privacy kill switch). Turn it back on to use '
          'cloud rewriting.',
    CloudBlockReason.featureDisabled =>
      'Cloud rewriting is turned off. Enable it in Privacy settings to send '
          'text to a provider.',
    CloudBlockReason.secretInUrl =>
      'This request was blocked before it left the device — the request '
          'was built incorrectly. Please report this.',
  },
  ProviderNotConfiguredException() =>
    'This provider isn’t set up yet. Add an API key in Providers to use it.',
  ProviderAuthException() =>
    'The provider rejected the saved API key. Check it in Providers.',
  RateLimitedException(retryAfter: final retryAfter) => retryAfter == null
      ? 'The provider is rate-limiting requests. Try again shortly.'
      : 'The provider is rate-limiting requests. Try again in '
            '${retryAfter.inSeconds}s.',
  QuotaExhaustedException() =>
    'The provider account is out of quota or balance. Check your plan with '
        'the provider.',
  ProviderUnavailableException() =>
    'The provider is having trouble right now. Try again shortly.',
  NetworkUnavailableException() =>
    'Couldn’t reach the provider. Check your internet connection.',
  ContentFilteredException() =>
    'The provider declined to generate a response for this text.',
  UnknownEngineException() =>
    'Couldn’t complete the rewrite. Try again. If it keeps happening, '
        'restart the app.',
};
