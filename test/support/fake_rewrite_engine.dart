import 'package:rescripto/engine/engine_capabilities.dart';
import 'package:rescripto/engine/engine_exception.dart';
import 'package:rescripto/engine/engine_request.dart';
import 'package:rescripto/engine/engine_stage.dart';
import 'package:rescripto/engine/engine_target.dart';
import 'package:rescripto/engine/generation_handle.dart';
import 'package:rescripto/engine/rewrite_engine.dart';

/// Test double for [RewriteEngine].
///
/// A real engine drives its handle from inside an async body the caller
/// doesn't control; this one hands the test the handle directly so it can
/// script exactly what a real engine's timing would produce — including the
/// pre-subscribe race that regressed `StreamGenerationHandle` (see
/// `generation_handle.dart`): call [emitStagesSynchronously] to reproduce
/// `LocalLlmEngine._run` emitting `submitting`/`streaming` before `start()`
/// even returns.
class FakeRewriteEngine implements RewriteEngine {
  FakeRewriteEngine({
    this.id = 'fake.engine',
    EngineCapabilities? capabilities,
    this.emitStagesSynchronously = false,
  }) : capabilities =
           capabilities ??
           const EngineCapabilities(
             needsLocalInstall: false,
             requiresNetwork: false,
           );

  @override
  final String id;

  @override
  final EngineCapabilities capabilities;

  /// When true, [start] emits `submitting` and `streaming` stage events
  /// synchronously before returning, before any caller has had a chance to
  /// subscribe to the handle's event stream.
  final bool emitStagesSynchronously;

  int prepareCallCount = 0;
  EngineTarget? lastPreparedTarget;

  /// Set to make the next [prepare] call throw this instead of succeeding.
  EngineException? prepareError;

  int disposeCallCount = 0;

  /// The most recent request passed to [start].
  EngineRequest? lastRequest;

  /// The most recent handle [start] produced. Since a fake has no generation
  /// loop of its own, the test drives it directly — `emitDelta`, `emitStage`,
  /// `complete`, `completeError`.
  StreamGenerationHandle? lastHandle;

  bool cancelRequested = false;

  @override
  Future<void> prepare(EngineTarget target) async {
    prepareCallCount++;
    lastPreparedTarget = target;
    final error = prepareError;
    if (error != null) throw error;
  }

  @override
  GenerationHandle start(EngineRequest request) {
    lastRequest = request;
    final handle = StreamGenerationHandle(
      onCancel: () async {
        cancelRequested = true;
      },
    );
    lastHandle = handle;
    if (emitStagesSynchronously) {
      handle.emitStage(EngineStage.submitting);
      handle.emitStage(EngineStage.streaming);
    }
    return handle;
  }

  @override
  Future<void> dispose() async {
    disposeCallCount++;
  }
}
