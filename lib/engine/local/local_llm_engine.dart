import 'dart:async';

import '../../models/ai_model.dart';
import '../../services/local_llm_service.dart';
import '../../services/settings_service.dart';
import '../engine_capabilities.dart';
import '../engine_exception.dart';
import '../engine_request.dart';
import '../engine_stage.dart';
import '../engine_target.dart';
import '../generation_handle.dart';
import '../rewrite_engine.dart';
import 'chat_template.dart';
import 'llama_error_mapper.dart';
import 'local_engine_host.dart';

/// [RewriteEngine] over the on-device llama.cpp model.
///
/// `prepare()` used to load the model as its own [LocalEngineHost.withEngine]
/// call, cache the resolved [AiModel] on an instance field, and `start()`
/// would read that field back later. Two problems followed from that, both
/// only reachable once a second caller shares this engine — which
/// `WorkflowRunner` now does, alongside `RewriteController`:
///
///  * The load and the generation were two separate, later [LocalEngineHost]
///    queue entries, leaving a gap between "the right model finished
///    loading" and "generation against it was enqueued" long enough for a
///    second caller's `prepare()` to land in between and load a *different*
///    model before this one's `generate` call reached the front of the
///    queue. Fixed by making load-then-generate a single
///    [LocalEngineHost.withEngine] call in [_run].
///  * Even with that fixed, a cached field written by `prepare()` and read
///    by a later `start()` is itself a race across two calls with an
///    `await` between them — nothing stops a second caller's `prepare()`
///    from overwriting it first. `start()` no longer depends on `prepare()`
///    having run at all: it resolves the model straight from
///    `request.target.modelRef`, the same lookup `prepare()` uses, so two
///    concurrent requests can never see each other's target.
class LocalLlmEngine implements RewriteEngine {
  LocalLlmEngine(
    this._host,
    this._settings, {
    this.errorMapper = const LlamaErrorMapper(),
  });

  final LocalEngineHost _host;
  final SettingsService _settings;
  final LlamaErrorMapper errorMapper;

  @override
  String get id => 'local.llama';

  @override
  EngineCapabilities get capabilities =>
      const EngineCapabilities(needsLocalInstall: true, requiresNetwork: false);

  /// Only validates — `start()` re-resolves the model itself, so this has
  /// nothing to hand off. Kept as a real `await`-worthy step (rather than
  /// deleted) so a caller still gets [ModelNotInstalledException] before it
  /// builds a request, and so [RewriteEngine.prepare]'s contract stays the
  /// same for every implementation.
  @override
  Future<void> prepare(EngineTarget target) async {
    if (ModelCatalog.byId(target.modelRef) == null) {
      throw ModelNotInstalledException(target.modelRef);
    }
  }

  @override
  GenerationHandle start(EngineRequest request) {
    final model = ModelCatalog.byId(request.target.modelRef);
    if (model == null) {
      throw ModelNotInstalledException(request.target.modelRef);
    }
    late final StreamGenerationHandle handle;
    handle = StreamGenerationHandle(onCancel: () => _host.requestStop(handle));
    unawaited(_run(handle, model, request));
    return handle;
  }

  Future<void> _run(
    StreamGenerationHandle handle,
    AiModel model,
    EngineRequest request,
  ) async {
    try {
      handle.emitStage(EngineStage.preparing);

      final output = await _host.withEngine((service) async {
        // Cancelled while still queued behind another caller's operation:
        // there is nothing native running for this request yet, so there is
        // nothing to stop — just skip the load and the generation entirely.
        // See LocalEngineHost.requestStop for the other half of this.
        if (handle.isCancelled) {
          throw const GenerationCancelledException();
        }

        await service.loadModel(
          model,
          threads: _settings.threads,
          contextSize: LocalLlmService.effectiveContextSize(
            model,
            _settings.contextSize,
          ),
          useGpu: _settings.useGpu,
        );

        final template = ChatTemplate.forFamily(model.family);
        final prompt = template.render(request.prompt);
        // The template's own markers plus whatever the caller asked for on
        // top — see ChatTemplate's doc for why these used to live apart.
        final stopSequences = {
          ...template.stopSequences,
          ...request.options.stopSequences,
        }.toList();
        final options = request.options.copyWith(
          stopSequences: stopSequences,
        );

        handle.emitStage(EngineStage.submitting);
        handle.emitStage(EngineStage.streaming);
        return service.generate(
          prompt,
          options: options,
          onDelta: handle.emitDelta,
        );
      }, token: handle);

      // The in-flight call above may have returned normally with whatever
      // partial text existed at the moment `stopGeneration()` cut it off —
      // that is a cancelled request, not a successful short one.
      if (handle.isCancelled) {
        handle.completeError(const GenerationCancelledException());
        return;
      }

      handle.emitStage(EngineStage.finalizing);
      if (output.isEmpty) {
        handle.completeError(const EmptyResponseException());
      } else {
        handle.complete(output);
      }
    } catch (e) {
      handle.completeError(
        handle.isCancelled
            ? const GenerationCancelledException()
            : errorMapper.map(e),
      );
    }
  }

  @override
  Future<void> dispose() => _host.dispose();
}
