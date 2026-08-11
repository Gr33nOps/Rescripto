/// What a [RewriteEngine] can and needs, independent of any one request.
///
/// Deliberately small. Each flag here backs an actual decision made
/// elsewhere today — [needsLocalInstall] and [requiresNetwork] drive the
/// stage copy in `engine_stage.dart`. A flag with no reader yet (streaming
/// support that's never branched on, a context-window limit nothing reads)
/// is the same mistake `TonePreset.warmth`/`complexity` were: a field that
/// looks load-bearing but isn't. Add the next one when a cloud engine
/// actually needs it read somewhere.
class EngineCapabilities {
  const EngineCapabilities({
    required this.needsLocalInstall,
    required this.requiresNetwork,
  });

  /// Whether [RewriteEngine.prepare] must load a model before generating.
  final bool needsLocalInstall;

  /// Whether generating this way sends the request off the device.
  final bool requiresNetwork;
}
