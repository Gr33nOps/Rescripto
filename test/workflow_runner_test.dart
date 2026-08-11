import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/engine/active_request_registry.dart';
import 'package:rescripto/engine/engine_exception.dart';
import 'package:rescripto/engine/engine_registry.dart';
import 'package:rescripto/engine/engine_target.dart';
import 'package:rescripto/engine/workflow_runner.dart';
import 'package:rescripto/models/rewrite_output.dart';
import 'package:rescripto/models/rewrite_request.dart';
import 'package:rescripto/models/workflow_definition.dart';
import 'package:rescripto/models/workflow_step.dart';
import 'package:rescripto/services/config_store.dart';
import 'package:rescripto/services/db/app_database.dart';
import 'package:rescripto/services/storage_service.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_rewrite_engine.dart';

void main() {
  late Directory tempDir;
  late AppDatabase database;
  late StorageService storage;
  late ConfigStore configStore;
  late FakeRewriteEngine localEngine;
  late FakeRewriteEngine cloudEngine;
  late ActiveRequestRegistry activeRequests;
  late WorkflowRunner runner;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('rescripto_workflow_runner');
    database = AppDatabase(path: '${tempDir.path}${Platform.pathSeparator}test.db');
    storage = StorageService(database);
    configStore = ConfigStore(database);
    await configStore.load();
    localEngine = FakeRewriteEngine(id: 'local.llama');
    cloudEngine = FakeRewriteEngine(id: 'cloud.openaiCompatible');
    activeRequests = ActiveRequestRegistry();
    runner = WorkflowRunner(
      registry: EngineRegistry([localEngine, cloudEngine]),
      configStore: configStore,
      storage: storage,
      activeRequests: activeRequests,
    );
  });

  tearDown(() async {
    await database.close();
    tempDir.deleteSync(recursive: true);
  });

  WorkflowDefinition twoStepWorkflow() {
    final now = DateTime.now();
    return WorkflowDefinition(
      id: 'workflow_1',
      name: 'Polish then formalize',
      steps: const [
        WorkflowStep(
          id: 'step_1',
          toneId: 'casual',
          intensity: RewriteIntensity.light,
          length: RewriteLength.same,
          target: EngineTarget(engineId: 'local.llama', modelRef: 'gemma'),
        ),
        WorkflowStep(
          id: 'step_2',
          toneId: 'professional',
          intensity: RewriteIntensity.full,
          length: RewriteLength.longer,
          target: EngineTarget(
            engineId: 'cloud.openaiCompatible',
            modelRef: 'gpt-4o',
            providerId: 'openai',
          ),
        ),
      ],
      createdAt: now,
      updatedAt: now,
    );
  }

  group('WorkflowRunner.run', () {
    test('feeds step N\'s output as step N+1\'s input, in order', () async {
      final future = runner.run(twoStepWorkflow(), 'rough draft');

      await Future<void>.delayed(Duration.zero);
      expect(runner.isRunning, isTrue);
      expect(runner.currentStepIndex, 0);
      localEngine.lastHandle!.complete(const RewriteOutput(text: 'polished draft'));

      await Future<void>.delayed(Duration.zero);
      expect(runner.currentStepIndex, 1);
      expect(cloudEngine.lastRequest!.prompt.user, 'polished draft');
      cloudEngine.lastHandle!.complete(const RewriteOutput(text: 'Formal Polished Draft.'));

      final result = await future;

      expect(result, 'Formal Polished Draft.');
      expect(runner.stepOutputs, ['polished draft', 'Formal Polished Draft.']);
      expect(runner.isRunning, isFalse);
    });

    test('saves only the final output to history, tagged with the last step', () async {
      final future = runner.run(twoStepWorkflow(), 'rough draft');
      await Future<void>.delayed(Duration.zero);
      localEngine.lastHandle!.complete(const RewriteOutput(text: 'polished draft'));
      await Future<void>.delayed(Duration.zero);
      cloudEngine.lastHandle!.complete(const RewriteOutput(text: 'Formal Polished Draft.'));
      await future;

      final history = await storage.getHistory();
      expect(history, hasLength(1));
      expect(history.first.original, 'rough draft');
      expect(history.first.rewritten, 'Formal Polished Draft.');
      expect(history.first.toneId, 'professional');
    });

    test('builds each step\'s prompt from its own intensity/length, not the other steps\'', () async {
      final future = runner.run(twoStepWorkflow(), 'rough draft');
      await Future<void>.delayed(Duration.zero);
      final firstPrompt = localEngine.lastRequest!.prompt.system;
      expect(firstPrompt, contains('LIGHT POLISH'));
      expect(firstPrompt, isNot(contains('FULL REWRITE')));

      localEngine.lastHandle!.complete(const RewriteOutput(text: 'x'));
      await Future<void>.delayed(Duration.zero);
      final secondPrompt = cloudEngine.lastRequest!.prompt.system;
      expect(secondPrompt, contains('FULL REWRITE'));
      expect(secondPrompt, contains('LONGER'));

      cloudEngine.lastHandle!.complete(const RewriteOutput(text: 'y'));
      await future;
    });

    test('rejects a workflow with no steps', () async {
      final now = DateTime.now();
      final empty = WorkflowDefinition(
        id: 'empty',
        name: 'Empty',
        steps: const [],
        createdAt: now,
        updatedAt: now,
      );
      await expectLater(runner.run(empty, 'text'), throwsArgumentError);
    });

    test('refuses a second concurrent run', () async {
      final first = runner.run(twoStepWorkflow(), 'rough draft');
      await Future<void>.delayed(Duration.zero);

      await expectLater(
        runner.run(twoStepWorkflow(), 'other text'),
        throwsA(isA<StateError>()),
      );

      localEngine.lastHandle!.complete(const RewriteOutput(text: 'polished'));
      await Future<void>.delayed(Duration.zero);
      cloudEngine.lastHandle!.complete(const RewriteOutput(text: 'final'));
      await first;
    });

    test('a step failure aborts the run, records lastError, and writes no history', () async {
      final future = runner.run(twoStepWorkflow(), 'rough draft');
      await Future<void>.delayed(Duration.zero);

      localEngine.lastHandle!.completeError(const ModelLoadFailedException('boom'));

      await expectLater(future, throwsA(isA<ModelLoadFailedException>()));
      expect(runner.lastError, isNotNull);
      expect(runner.isRunning, isFalse);
      expect(await storage.getHistory(), isEmpty);
      expect(cloudEngine.lastRequest, isNull, reason: 'step 2 must never start after step 1 fails');
    });

    test('cancel reaches the active step\'s handle', () async {
      final future = runner.run(twoStepWorkflow(), 'rough draft');
      await Future<void>.delayed(Duration.zero);
      expect(activeRequests.activeCount, 1);

      await runner.cancel();
      expect(localEngine.cancelRequested, isTrue);

      localEngine.lastHandle!.completeError(const GenerationCancelledException());
      await expectLater(future, throwsA(isA<GenerationCancelledException>()));
      expect(activeRequests.activeCount, 0);
    });
  });
}
