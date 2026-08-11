import 'dart:convert';

import '../engine/engine_target.dart';
import 'rewrite_request.dart';

/// One step of a [WorkflowDefinition]: which tone/intensity/length/audience/
/// instruction to apply, and which engine to run it on.
///
/// [target] is captured automatically from wherever the app's current
/// processing mode routes to at the moment a step is added, rather than
/// exposed as a per-step engine/model picker in the editor — the data model
/// supports an arbitrary target per step (a later release could add that
/// picker), but the initial workflow editor doesn't ask a user hand-picking
/// tones and instructions to also hand-pick infrastructure. Two consecutive
/// steps that both resolve to the local engine still run sequentially
/// regardless — `LocalEngineHost` is a mutex, because the vendored
/// `EventChannel` has no per-request id to demultiplex concurrent
/// generations by.
class WorkflowStep {
  const WorkflowStep({
    required this.id,
    required this.toneId,
    required this.intensity,
    required this.length,
    this.audience = const [],
    this.customInstruction = '',
    required this.target,
  });

  final String id;
  final String toneId;
  final RewriteIntensity intensity;
  final RewriteLength length;

  /// Audience *ids* — see `RewriteController.audience`'s own doc for why.
  final List<String> audience;
  final String customInstruction;
  final EngineTarget target;

  WorkflowStep copyWith({
    String? toneId,
    RewriteIntensity? intensity,
    RewriteLength? length,
    List<String>? audience,
    String? customInstruction,
    EngineTarget? target,
  }) {
    return WorkflowStep(
      id: id,
      toneId: toneId ?? this.toneId,
      intensity: intensity ?? this.intensity,
      length: length ?? this.length,
      audience: audience ?? this.audience,
      customInstruction: customInstruction ?? this.customInstruction,
      target: target ?? this.target,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'tone_id': toneId,
    'intensity': intensity.name,
    'length': length.name,
    'audience': jsonEncode(audience),
    'custom_instruction': customInstruction,
    'engine_id': target.engineId,
    'model_ref': target.modelRef,
    'provider_id': target.providerId,
  };

  factory WorkflowStep.fromMap(Map<String, Object?> map) => WorkflowStep(
    id: map['id'] as String,
    toneId: map['tone_id'] as String,
    intensity: RewriteIntensity.values.byName(map['intensity'] as String),
    length: RewriteLength.values.byName(map['length'] as String),
    audience: (jsonDecode(map['audience'] as String? ?? '[]') as List<Object?>)
        .map((a) => a as String)
        .toList(),
    customInstruction: map['custom_instruction'] as String? ?? '',
    target: EngineTarget(
      engineId: map['engine_id'] as String,
      modelRef: map['model_ref'] as String,
      providerId: map['provider_id'] as String?,
    ),
  );
}
