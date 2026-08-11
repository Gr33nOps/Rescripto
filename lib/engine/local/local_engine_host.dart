import '../../services/local_llm_service.dart';

/// Sole owner of the native llama.cpp engine, serialising every call onto it.
///
/// `FlutterLlama.instance` is a process-wide singleton, and its token stream
/// (`EventChannel('flutter_llama/stream')`) is a *broadcast* channel with no
/// request id — two concurrent `generateStream` calls would interleave
/// tokens into one stream with no way to tell them apart, and
/// `stopGeneration()` is itself global rather than per-request. Routing every
/// call through [withEngine] means there is only ever one call in flight,
/// which is what makes those two facts safe rather than a race.
///
/// Only local↔local access needs this; a cloud engine has no such shared
/// resource and does not go through it. Every caller that can mutate the
/// native engine's state goes through the same instance — `ModelsController`
/// unloads through it too when deleting the active model, rather than
/// holding a `LocalLlmService` of its own — or the serialisation this
/// provides would only be true for generation, not for the unload racing a
/// generation in flight.
///
/// The plan for this host originally called for queued-but-not-yet-started
/// requests to be cancellable without ever touching native. That distinction
/// only matters once something can enqueue a second request while the first
/// is still running, and nothing in the app does that today — one rewrite
/// runs at a time by construction. So this is deliberately just a mutex: it
/// makes concurrent access safe, and cancellation always calls native
/// `stopGeneration()`, exactly like `RewriteController.stop()` did before
/// this refactor. Queued-cancel-without-touching-native is worth adding when
/// a second caller (a multi-step workflow) actually exists to test it against.
class LocalEngineHost {
  LocalEngineHost(this._service);

  final LocalLlmService _service;
  Future<void> _tail = Future.value();
  bool _busy = false;

  bool get isBusy => _busy;

  /// Path of the currently loaded model, if any. A plain field read off the
  /// native wrapper — not mutating, so it does not need to go through
  /// [withEngine].
  String? get loadedModelPath => _service.loadedModelPath;

  /// Runs [body] with exclusive access to the native engine, after every
  /// call already queued ahead of it has finished.
  Future<T> withEngine<T>(Future<T> Function(LocalLlmService service) body) {
    final previous = _tail;
    final result = previous.then((_) {
      _busy = true;
      return body(_service).whenComplete(() => _busy = false);
    });
    // Chain on a version that never throws, so one failed call doesn't wedge
    // every call queued after it.
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> requestStop() => _service.stopGeneration();

  Future<void> dispose() => withEngine((service) => service.dispose());
}
