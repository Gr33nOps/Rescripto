import 'package:flutter/services.dart';

import '../engine_exception.dart';

/// Maps whatever the native channel throws that
/// `LocalLlmService`/`FlutterLlama` didn't already turn into a typed
/// [EngineException] at the source.
///
/// This is the one place substring matching on an error message survives —
/// deliberately narrow, scoped to a single channel's `PlatformException`,
/// rather than the only error path in the app the way it used to be.
class LlamaErrorMapper {
  const LlamaErrorMapper();

  EngineException map(Object error) {
    if (error is EngineException) return error;
    if (error is PlatformException) return _fromPlatformException(error);
    return const UnknownEngineException();
  }

  EngineException _fromPlatformException(PlatformException error) {
    final message = (error.message ?? '').toLowerCase();
    // No native path reports memory pressure with a distinct code; the
    // Android/JVM error that ultimately reports it just says so in its text.
    if (message.contains('memory') || message.contains('oom')) {
      return const OutOfMemoryException();
    }
    return switch (error.code) {
      'MODEL_NOT_FOUND' => ModelNotInstalledException(error.message ?? ''),
      'MODEL_NOT_LOADED' => ModelLoadFailedException(error.message),
      _ => UnknownEngineException(error.message),
    };
  }
}
