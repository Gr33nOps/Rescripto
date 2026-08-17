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
/// A second caller queuing behind the first was originally hypothetical —
/// "nothing in the app does that today — one rewrite runs at a time by
/// construction." `WorkflowRunner` is now that second caller: a workflow step
/// and a rewrite both resolve to this same host, and each drove its own
/// separate `prepare()` (a `withEngine(loadModel)` call) and `start()` (a
/// later, separate `withEngine(generate)` call). Because those were two
/// independent queue entries rather than one, a second caller's `prepare()`
/// could land on [_tail] in the gap between the first caller's `prepare()`
/// resolving and its `generate()` being enqueued — native execution order
/// became load(A) → load(B) → generate(using A's prompt, against B's now-
/// loaded weights). `LocalLlmEngine` now makes prepare-then-generate a single
/// [withEngine] call so that gap cannot exist: nothing can occupy [_tail]
/// between "the right model is loaded" and "generation against it starts",
/// because both happen inside the one queued [body].
///
/// [requestStop] is scoped to a caller-supplied [token] for the matching
/// reason: cancelling a request that is still queued behind another one has
/// nothing native to stop yet, and calling the global `stopGeneration()`
/// then would cut off whatever unrelated operation *is* currently running.
/// A queued request instead checks [isActive] itself, from inside its own
/// [withEngine] body, and bails out before ever touching native.
class LocalEngineHost {
  LocalEngineHost(this._service);

  final LocalLlmService _service;
  Future<void> _tail = Future.value();
  bool _busy = false;
  Object? _activeToken;

  bool get isBusy => _busy;

  /// Path of the currently loaded model, if any. A plain field read off the
  /// native wrapper — not mutating, so it does not need to go through
  /// [withEngine].
  String? get loadedModelPath => _service.loadedModelPath;

  /// True while [token]'s call is the one actually running on native, as
  /// opposed to still waiting in [_tail] behind an earlier caller.
  bool isActive(Object token) => _busy && identical(_activeToken, token);

  /// Runs [body] with exclusive access to the native engine, after every
  /// call already queued ahead of it has finished.
  ///
  /// [token] identifies this call for [requestStop] — pass the same value a
  /// caller will later hand to [requestStop] to cancel this specific
  /// operation. Calls that never need to be stopped (unloading, disposing)
  /// can omit it.
  Future<T> withEngine<T>(
    Future<T> Function(LocalLlmService service) body, {
    Object? token,
  }) {
    final previous = _tail;
    final result = previous.then((_) {
      _busy = true;
      _activeToken = token;
      return body(_service).whenComplete(() {
        _busy = false;
        _activeToken = null;
      });
    });
    // Chain on a version that never throws, so one failed call doesn't wedge
    // every call queued after it.
    _tail = result.then((_) {}, onError: (_) {});
    return result;
  }

  /// Stops generation, but only if [token] is the operation currently
  /// running on native — see the class doc for why a queued-but-not-yet-
  /// started operation must not trigger this at all.
  Future<void> requestStop(Object token) {
    if (!isActive(token)) return Future.value();
    return _service.stopGeneration();
  }

  /// Frees the in-memory rewrite model before another large native engine,
  /// such as Whisper, is initialized. Downloaded model files are untouched.
  Future<void> releaseLoadedModel() =>
      withEngine((service) => service.unloadModel());

  Future<void> dispose() => withEngine((service) => service.dispose());
}
