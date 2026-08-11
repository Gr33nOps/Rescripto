import 'engine_exception.dart';
import 'engine_target.dart';
import 'rewrite_engine.dart';

/// Looks up the [RewriteEngine] a request should run on.
class EngineRegistry {
  EngineRegistry(Iterable<RewriteEngine> engines)
    : _byId = {for (final engine in engines) engine.id: engine};

  final Map<String, RewriteEngine> _byId;

  /// Resolves [target], throwing [EngineNotAvailableException] if nothing is
  /// registered for it.
  RewriteEngine resolve(EngineTarget target) {
    final engine = _byId[target.engineId];
    if (engine == null) {
      throw EngineNotAvailableException(target.engineId);
    }
    return engine;
  }

  /// Same as [resolve], but returns null instead of throwing.
  ///
  /// For call sites that run inside widget `build()` — like
  /// `RewriteController.capabilities` — where throwing mid-build would crash
  /// the frame rather than let the UI show "not available" copy.
  RewriteEngine? maybeResolve(EngineTarget target) => _byId[target.engineId];

  Future<void> dispose() async {
    for (final engine in _byId.values) {
      await engine.dispose();
    }
  }
}
