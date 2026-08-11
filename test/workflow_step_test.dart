import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/engine/engine_target.dart';
import 'package:rescripto/models/rewrite_request.dart';
import 'package:rescripto/models/workflow_definition.dart';
import 'package:rescripto/models/workflow_step.dart';

void main() {
  group('WorkflowStep.toMap / fromMap', () {
    test('round-trips every field, including a multi-entry audience list', () {
      const step = WorkflowStep(
        id: 'step_1',
        toneId: 'professional',
        intensity: RewriteIntensity.full,
        length: RewriteLength.longer,
        audience: ['coworkers', 'clients'],
        customInstruction: 'keep it terse',
        target: EngineTarget(
          engineId: 'cloud.openaiCompatible',
          modelRef: 'gpt-4o',
          providerId: 'openai',
        ),
      );

      final restored = WorkflowStep.fromMap(step.toMap());

      expect(restored.id, step.id);
      expect(restored.toneId, step.toneId);
      expect(restored.intensity, step.intensity);
      expect(restored.length, step.length);
      expect(restored.audience, step.audience);
      expect(restored.customInstruction, step.customInstruction);
      expect(restored.target, step.target);
    });

    test('round-trips an empty audience list and a null providerId', () {
      const step = WorkflowStep(
        id: 'step_2',
        toneId: 'casual',
        intensity: RewriteIntensity.light,
        length: RewriteLength.shorter,
        target: EngineTarget(engineId: 'local.llama', modelRef: 'gemma'),
      );

      final restored = WorkflowStep.fromMap(step.toMap());

      expect(restored.audience, isEmpty);
      expect(restored.target.providerId, isNull);
      expect(restored.customInstruction, '');
    });

    test('copyWith replaces only the given fields', () {
      const step = WorkflowStep(
        id: 'step_3',
        toneId: 'casual',
        intensity: RewriteIntensity.moderate,
        length: RewriteLength.same,
        target: EngineTarget(engineId: 'local.llama', modelRef: 'gemma'),
      );

      final updated = step.copyWith(toneId: 'formal', audience: ['clients']);

      expect(updated.id, step.id, reason: 'id is never part of copyWith');
      expect(updated.toneId, 'formal');
      expect(updated.audience, ['clients']);
      expect(updated.intensity, step.intensity);
      expect(updated.target, step.target);
    });
  });

  group('WorkflowDefinition.copyWith', () {
    test('preserves id and createdAt, replaces the rest', () {
      final createdAt = DateTime(2026, 1, 1);
      final updatedAt = DateTime(2026, 1, 2);
      const step = WorkflowStep(
        id: 'step_1',
        toneId: 'professional',
        intensity: RewriteIntensity.moderate,
        length: RewriteLength.same,
        target: EngineTarget(engineId: 'local.llama', modelRef: 'gemma'),
      );
      final definition = WorkflowDefinition(
        id: 'workflow_1',
        name: 'Original',
        steps: const [step],
        createdAt: createdAt,
        updatedAt: createdAt,
      );

      final renamed = definition.copyWith(name: 'Renamed', updatedAt: updatedAt);

      expect(renamed.id, 'workflow_1');
      expect(renamed.createdAt, createdAt);
      expect(renamed.name, 'Renamed');
      expect(renamed.updatedAt, updatedAt);
      expect(renamed.steps, [step]);
    });
  });
}
