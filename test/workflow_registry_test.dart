import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/engine/engine_target.dart';
import 'package:rescripto/models/rewrite_request.dart';
import 'package:rescripto/models/workflow_definition.dart';
import 'package:rescripto/models/workflow_step.dart';
import 'package:rescripto/services/db/app_database.dart';
import 'package:rescripto/services/workflows/workflow_registry.dart';
import 'package:rescripto/services/workflows/workflow_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory tempDir;
  late AppDatabase database;
  late WorkflowRegistry registry;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('rescripto_workflow_registry');
    database = AppDatabase(path: '${tempDir.path}${Platform.pathSeparator}test.db');
    registry = WorkflowRegistry(WorkflowStore(database));
    await registry.load();
  });

  tearDown(() async {
    await database.close();
    tempDir.deleteSync(recursive: true);
  });

  WorkflowDefinition buildWorkflow({String name = 'My workflow', List<WorkflowStep>? steps}) {
    final now = DateTime.now();
    return WorkflowDefinition(
      id: registry.newId(),
      name: name,
      steps:
          steps ??
          [
            WorkflowStep(
              id: registry.newStepId(),
              toneId: 'professional',
              intensity: RewriteIntensity.moderate,
              length: RewriteLength.same,
              target: const EngineTarget(engineId: 'local.llama', modelRef: 'gemma'),
            ),
          ],
      createdAt: now,
      updatedAt: now,
    );
  }

  group('WorkflowRegistry.load', () {
    test('starts empty and marks isLoaded', () {
      expect(registry.workflows, isEmpty);
      expect(registry.isLoaded, isTrue);
    });
  });

  group('WorkflowRegistry.save', () {
    test('persists a workflow and reflects it immediately in the cache', () async {
      final workflow = buildWorkflow();
      await registry.save(workflow);

      expect(registry.workflows, hasLength(1));
      expect(registry.byId(workflow.id)?.name, 'My workflow');
    });

    test('round-trips step order through workflow_step.sort_order', () async {
      final steps = [
        WorkflowStep(
          id: registry.newStepId(),
          toneId: 'casual',
          intensity: RewriteIntensity.light,
          length: RewriteLength.shorter,
          target: const EngineTarget(engineId: 'local.llama', modelRef: 'gemma'),
        ),
        WorkflowStep(
          id: registry.newStepId(),
          toneId: 'professional',
          intensity: RewriteIntensity.full,
          length: RewriteLength.longer,
          target: const EngineTarget(
            engineId: 'cloud.openaiCompatible',
            modelRef: 'gpt-4o',
            providerId: 'openai',
          ),
        ),
      ];
      final workflow = buildWorkflow(steps: steps);
      await registry.save(workflow);

      final reloaded = registry.byId(workflow.id)!;
      expect(reloaded.steps.map((s) => s.toneId).toList(), ['casual', 'professional']);
    });

    test('survives a reload from a fresh registry over the same database', () async {
      final workflow = buildWorkflow(name: 'Persisted');
      await registry.save(workflow);

      final reopened = WorkflowRegistry(WorkflowStore(database));
      await reopened.load();

      expect(reopened.workflows, hasLength(1));
      expect(reopened.byId(workflow.id)?.name, 'Persisted');
      expect(reopened.byId(workflow.id)?.steps, hasLength(1));
    });

    test('re-saving an existing workflow replaces its steps rather than appending', () async {
      final workflow = buildWorkflow();
      await registry.save(workflow);

      final updated = workflow.copyWith(
        steps: [
          workflow.steps.first,
          WorkflowStep(
            id: registry.newStepId(),
            toneId: 'casual',
            intensity: RewriteIntensity.light,
            length: RewriteLength.shorter,
            target: const EngineTarget(engineId: 'local.llama', modelRef: 'gemma'),
          ),
        ],
      );
      await registry.save(updated);

      expect(registry.workflows, hasLength(1));
      expect(registry.byId(workflow.id)!.steps, hasLength(2));
    });
  });

  group('WorkflowRegistry.delete', () {
    test('removes the workflow and cascades its steps', () async {
      final workflow = buildWorkflow();
      await registry.save(workflow);

      await registry.delete(workflow.id);

      expect(registry.byId(workflow.id), isNull);
      final db = await database.db;
      final remainingSteps = await db.query(
        'workflow_step',
        where: 'workflow_id = ?',
        whereArgs: [workflow.id],
      );
      expect(remainingSteps, isEmpty, reason: 'workflow_step rows must cascade on delete');
    });

    test('a delete for an unknown id is a harmless no-op', () async {
      await registry.delete('does-not-exist');
      expect(registry.workflows, isEmpty);
    });
  });
}
