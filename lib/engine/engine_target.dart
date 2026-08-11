/// Identifies which engine a request should run on, and which model.
class EngineTarget {
  const EngineTarget({required this.engineId, required this.modelRef});

  /// e.g. `'local.llama'`. Looked up in [EngineRegistry].
  final String engineId;

  /// Engine-specific model identifier — a [ModelCatalog] id for the local
  /// engine, a provider's own model name for a cloud one.
  final String modelRef;

  @override
  bool operator ==(Object other) =>
      other is EngineTarget &&
      other.engineId == engineId &&
      other.modelRef == modelRef;

  @override
  int get hashCode => Object.hash(engineId, modelRef);

  @override
  String toString() => 'EngineTarget($engineId, $modelRef)';
}
