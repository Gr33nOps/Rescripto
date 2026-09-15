import 'engine_exception.dart';

/// User-facing text for an [EngineException].
///
/// Replaces `RewriteController._describeError`, which parsed the *message*
/// of whatever was thrown looking for words like "context" or "memory". The
/// switch below is exhaustive over [EngineException]'s subtypes — the
/// compiler rejects it if a new subtype is added without a case here, where
/// a substring check would just silently fall through to the generic message.
///
/// Every message says what happened and, where there is one, where to fix
/// it, using the screen names the app actually shows.
String describeEngineError(EngineException error) => switch (error) {
  ModelNotInstalledException() =>
    'No on-device model is installed yet. Download one in the Models tab.',
  ModelLoadFailedException(nativeReason: final reason) =>
    reason == null || reason.isEmpty
        ? 'Couldn’t load the model. Try again, and restart the app if it '
              'keeps happening.'
        : reason,
  ModelCorruptedException() =>
    'The model file was damaged, so Rescripto removed it. Download it again '
        'in the Models tab.',
  ContextOverflowException(contextSize: final size) =>
    size == null
        ? 'This text is too long for the model. Shorten it, or raise Context '
              'size in Settings > Performance.'
        : 'This text is too long for a $size-token context. Shorten it, or '
              'raise Context size in Settings > Performance.',
  EmptyResponseException() =>
    'The model didn’t return any text. Try again, or pick a different model.',
  ModelRefusedException() =>
    'The model wouldn’t rewrite this text, even on a second try. Small '
        'on-device models sometimes do that with ordinary writing. A '
        'different model in the Models tab usually helps.',
  OutOfMemoryException() =>
    'There isn’t enough memory for this model. Try a smaller model, or a '
        'smaller context size in Settings > Performance.',
  // Cancellation is a user action, not a failure — nothing calls this for it.
  GenerationCancelledException() => 'Stopped.',
  EngineNotAvailableException() =>
    'Nothing is set up to run this rewrite yet. Check Processing mode in '
        'Settings.',
  CloudAccessBlockedException(reason: final reason) => switch (reason) {
    CloudBlockReason.killSwitch =>
      'The network kill switch is on. Turn it off in Privacy settings to use '
          'cloud rewriting.',
    CloudBlockReason.featureDisabled =>
      'Cloud rewriting is turned off. Turn it on in Privacy settings to send '
          'text to a provider.',
    CloudBlockReason.secretInUrl =>
      'Rescripto stopped this request because it would have put your API key '
          'in the web address. Please report this as a bug.',
  },
  ProviderNotConfiguredException() =>
    'This provider has no API key yet. Add one in Settings > Cloud providers.',
  ProviderAuthException() =>
    'The provider rejected the saved API key. Check it in Settings > Cloud '
        'providers.',
  RateLimitedException(retryAfter: final retryAfter) =>
    retryAfter == null
        ? 'The provider is limiting requests right now. Try again in a moment.'
        : 'The provider is limiting requests right now. Try again in '
              '${retryAfter.inSeconds} seconds.',
  QuotaExhaustedException() =>
    'This provider account is out of credit or quota. Check your plan with '
        'the provider.',
  ProviderUnavailableException() =>
    'The provider is having problems right now. Try again in a few minutes.',
  NetworkUnavailableException() =>
    'Couldn’t reach the provider. Check your internet connection.',
  ContentFilteredException() =>
    'The provider’s content filter blocked this text.',
  UnknownEngineException() =>
    'Couldn’t finish the rewrite. Try again, and restart the app if it keeps '
        'happening.',
};
