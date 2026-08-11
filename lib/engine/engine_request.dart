import 'engine_target.dart';
import 'generation_options.dart';
import 'prompt_spec.dart';

/// Everything a prepared [RewriteEngine] needs to generate one result.
class EngineRequest {
  const EngineRequest({
    required this.target,
    required this.prompt,
    required this.options,
  });

  /// Which engine and model (and, for cloud, which provider) this request is
  /// bound to. The engine that receives this is always the one
  /// [target.engineId] names — carrying it on the request as well as on the
  /// call to [RewriteEngine.prepare] is what lets one cloud protocol engine
  /// serve every provider that speaks it.
  final EngineTarget target;

  final PromptSpec prompt;
  final GenerationOptions options;
}
