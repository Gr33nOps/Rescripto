import 'engine_target.dart';
import 'rewrite_engine.dart';

/// Looks up the [RewriteEngine] a request should run on.
class EngineRegistry {
  EngineRegistry(Iterable<RewriteEngine> engines)
    : _byId = {for (final engine in engines) engine.id: engine};

  final Map<String, RewriteEngine> _byId;

  RewriteEngine resolve(EngineTarget target) {
    final engine = _byId[target.engineId];
    if (engine == null) {
      throw StateError('No engine registered for "${target.engineId}".');
    }
    return engine;
  }

  Future<void> dispose() async {
    for (final engine in _byId.values) {
      await engine.dispose();
    }
  }
}
