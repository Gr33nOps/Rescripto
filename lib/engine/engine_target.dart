/// Identifies which engine a request should run on, and which model.
class EngineTarget {
  const EngineTarget({
    required this.engineId,
    required this.modelRef,
    this.providerId,
  });

  /// e.g. `'local.llama'`, `'cloud.openaiCompatible'`. Looked up in
  /// [EngineRegistry].
  final String engineId;

  /// Engine-specific model identifier — a [ModelCatalog] id for the local
  /// engine, a provider's own model name for a cloud one.
  final String modelRef;

  /// Which configured [ProviderConfig] a cloud engine should use.
  ///
  /// Null for the local engine. A cloud protocol has exactly one registered
  /// [RewriteEngine] instance shared by every provider that speaks it, so
  /// this is how one request picks which provider's credential and base URL
  /// to use — carried on the request rather than on a per-provider engine
  /// instance, so no engine can be disposed while a handle it created is
  /// still live.
  final String? providerId;

  @override
  bool operator ==(Object other) =>
      other is EngineTarget &&
      other.engineId == engineId &&
      other.modelRef == modelRef &&
      other.providerId == providerId;

  @override
  int get hashCode => Object.hash(engineId, modelRef, providerId);

  @override
  String toString() =>
      'EngineTarget($engineId, $modelRef${providerId == null ? '' : ', provider: $providerId'})';
}
