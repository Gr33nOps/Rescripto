import 'engine_capabilities.dart';
import 'engine_request.dart';
import 'engine_target.dart';
import 'generation_handle.dart';

/// Something that can turn a [PromptSpec] into rewritten text.
///
/// Implemented today only by the local llama.cpp engine
/// (`lib/engine/local/local_llm_engine.dart`); a cloud provider implements
/// the same three methods with [EngineCapabilities.needsLocalInstall] false
/// and [prepare] a no-op.
abstract interface class RewriteEngine {
  /// Stable id this engine is registered under, e.g. `'local.llama'`.
  String get id;

  EngineCapabilities get capabilities;

  /// Readies the engine for [target] — for the local engine, loads the
  /// model. Idempotent: preparing the same target twice in a row is cheap.
  Future<void> prepare(EngineTarget target);

  /// Starts generating. Returns immediately; the work happens on the
  /// returned handle's own timeline.
  GenerationHandle start(EngineRequest request);

  Future<void> dispose();
}
