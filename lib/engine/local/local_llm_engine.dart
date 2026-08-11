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
class LocalLlmEngine implements RewriteEngine {
  LocalLlmEngine(
    this._host,
    this._settings, {
    this.errorMapper = const LlamaErrorMapper(),
  });

  final LocalEngineHost _host;
  final SettingsService _settings;
  final LlamaErrorMapper errorMapper;

  ChatTemplate? _preparedTemplate;

  @override
  String get id => 'local.llama';

  @override
  EngineCapabilities get capabilities =>
      const EngineCapabilities(needsLocalInstall: true, requiresNetwork: false);

  @override
  Future<void> prepare(EngineTarget target) async {
    final model = ModelCatalog.byId(target.modelRef);
    if (model == null) {
      throw ModelNotInstalledException(target.modelRef);
    }
    await _host.withEngine(
      (service) => service.loadModel(
        model,
        threads: _settings.threads,
        contextSize: LocalLlmService.effectiveContextSize(
          model,
          _settings.contextSize,
        ),
        useGpu: _settings.useGpu,
      ),
    );
    _preparedTemplate = ChatTemplate.forFamily(model.family);
  }

  @override
  GenerationHandle start(EngineRequest request) {
    final template = _preparedTemplate;
    if (template == null) {
      throw StateError(
        'LocalLlmEngine.start() called before a successful prepare().',
      );
    }
    final handle = StreamGenerationHandle(onCancel: _host.requestStop);
    unawaited(_run(handle, template, request));
    return handle;
  }

  Future<void> _run(
    StreamGenerationHandle handle,
    ChatTemplate template,
    EngineRequest request,
  ) async {
    try {
      handle.emitStage(EngineStage.submitting);
      final prompt = template.render(request.prompt);
      // The template's own markers plus whatever the caller asked for on top
      // — see ChatTemplate's doc for why these used to live apart.
      final stopSequences = {
        ...template.stopSequences,
        ...request.options.stopSequences,
      }.toList();
      final options = request.options.copyWith(stopSequences: stopSequences);

      handle.emitStage(EngineStage.streaming);
      final output = await _host.withEngine(
        (service) =>
            service.generate(prompt, options: options, onDelta: handle.emitDelta),
      );

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
