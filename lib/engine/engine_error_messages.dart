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
  ContextOverflowException(contextSize: final size) =>
    'This text is too long for the $size-token context. Shorten it or '
        'increase Context size in Settings.',
  EmptyResponseException() =>
    'The model returned an empty result. Try a different intensity.',
  OutOfMemoryException() =>
    'Not enough memory on this device. Try a smaller model or lower '
        'context size in Settings.',
  // Cancellation is a user action, not a failure — nothing calls this for it.
  GenerationCancelledException() => 'Cancelled.',
  UnknownEngineException() =>
    'Couldn’t complete the rewrite. Try again. If it keeps happening, '
        'restart the app.',
};
