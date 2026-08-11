import 'workflow_step.dart';

/// A named, ordered sequence of [WorkflowStep]s — step *N*'s output becomes
/// step *N+1*'s input text, with every other field (tone, audience,
/// instruction) reset per step rather than inherited.
class WorkflowDefinition {
  const WorkflowDefinition({
    required this.id,
    required this.name,
    required this.steps,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final List<WorkflowStep> steps;
  final DateTime createdAt;
  final DateTime updatedAt;

  WorkflowDefinition copyWith({
    String? name,
    List<WorkflowStep>? steps,
    DateTime? updatedAt,
  }) {
    return WorkflowDefinition(
      id: id,
      name: name ?? this.name,
      steps: steps ?? this.steps,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
