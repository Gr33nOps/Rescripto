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
final class ContextOverflowException extends EngineException {
  const ContextOverflowException({
    required this.promptTokens,
    required this.contextSize,
  });

  final int promptTokens;
  final int contextSize;
}

/// Generation completed but produced no usable text.
final class EmptyResponseException extends EngineException {
  const EmptyResponseException();
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
