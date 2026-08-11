import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:rescripto/engine/engine_capabilities.dart';
import 'package:rescripto/engine/engine_exception.dart';
import 'package:rescripto/engine/engine_registry.dart';
import 'package:rescripto/engine/engine_stage.dart';
import 'package:rescripto/engine/engine_target.dart';
import 'package:rescripto/engine/generation_handle.dart';
import 'package:rescripto/models/rewrite_output.dart';
import 'package:rescripto/services/config_store.dart';
import 'package:rescripto/services/db/app_database.dart';
import 'package:rescripto/services/settings_service.dart';
import 'package:rescripto/services/storage_service.dart';
import 'package:rescripto/state/rewrite_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/fake_rewrite_engine.dart';

void main() {
  late Directory tempDir;
  late AppDatabase database;
  late SettingsService settings;
  late StorageService storage;
  late ConfigStore configStore;
  late FakeRewriteEngine engine;
  late RewriteController controller;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync(
      'rescripto_rewrite_controller',
    );
    database = AppDatabase(
      path: '${tempDir.path}${Platform.pathSeparator}test.db',
    );
    SharedPreferences.setMockInitialValues({});
    settings = SettingsService();
    await settings.init();
    storage = StorageService(database);
    configStore = ConfigStore(database);
    await configStore.load();
    // emitStagesSynchronously reproduces LocalLlmEngine's real timing: stage
    // events land before start() returns, before anything has subscribed.
    engine = FakeRewriteEngine(id: 'local.llama', emitStagesSynchronously: true);
    controller = RewriteController(
      registry: EngineRegistry([engine]),
      settings: settings,
      storage: storage,
      configStore: configStore,
    );
    controller.setSource('please rewrite this');
  });

  tearDown(() async {
    await database.close();
    tempDir.deleteSync(recursive: true);
  });

  group('StreamGenerationHandle', () {
    test('events emitted before the caller subscribes are still delivered', () async {
      final handle = StreamGenerationHandle(onCancel: () async {});
      handle.emitStage(EngineStage.submitting);
      handle.emitStage(EngineStage.streaming);

      final received = <EngineStage>[];
      final sub = handle.events.listen((event) {
        if (event is StageChanged) received.add(event.stage);
      });

      // Buffered pre-listen events are flushed as scheduled microtasks, one
      // per turn — give that queue a chance to drain before closing the
      // stream, or `complete()` would race its own `close()` ahead of
      // events that were already queued.
      await Future<void>.delayed(Duration.zero);

      handle.complete(const RewriteOutput(text: 'done'));
      await handle.done;
      await sub.cancel();

      expect(received, [EngineStage.submitting, EngineStage.streaming]);
    });
  });

  group('RewriteController.rewrite', () {
    test(
      'stage reaches streaming while running instead of sticking on preparing',
      () async {
        final future = controller.rewrite();

        // A single macrotask boundary flushes every microtask hop in
        // between: engine.prepare()'s await, start()'s synchronous
        // pre-subscribe emits, and the buffered-event delivery to the
        // subscription set up right after. If this were still backed by a
        // broadcast StreamController, those events would already be gone
        // and stage would still read `preparing`.
        await Future<void>.delayed(Duration.zero);

        expect(controller.isRunning, isTrue);
        expect(controller.stage, EngineStage.streaming);

        engine.lastHandle!.emitDelta('hello');
        await Future<void>.delayed(Duration.zero);
        expect(controller.streamingText, 'hello');

        engine.lastHandle!.complete(const RewriteOutput(text: 'hello there'));
        final result = await future;

        expect(result.primary.text, 'hello there');
        expect(controller.isRunning, isFalse);
      },
    );

    test('surfaces EngineNotAvailableException for an unregistered engine target', () async {
      final orphanController = RewriteController(
        registry: EngineRegistry(const []),
        settings: settings,
        storage: storage,
        configStore: configStore,
      );
      orphanController.setSource('text');

      await expectLater(
        orphanController.rewrite(),
        throwsA(isA<EngineNotAvailableException>()),
      );
      expect(orphanController.lastError, isNotNull);
    });

    test('capabilities falls back safely instead of throwing during build', () {
      final orphanController = RewriteController(
        registry: EngineRegistry(const []),
        settings: settings,
        storage: storage,
        configStore: configStore,
      );
      expect(
        orphanController.capabilities,
        const EngineCapabilities(needsLocalInstall: false, requiresNetwork: false),
      );
    });
  });

  group('EngineTarget', () {
    test('equality and hashCode include providerId', () {
      const a = EngineTarget(engineId: 'cloud.openaiCompatible', modelRef: 'gpt', providerId: 'openai');
      const b = EngineTarget(engineId: 'cloud.openaiCompatible', modelRef: 'gpt', providerId: 'openai');
      const c = EngineTarget(engineId: 'cloud.openaiCompatible', modelRef: 'gpt', providerId: 'groq');
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(c));
    });
  });
}
