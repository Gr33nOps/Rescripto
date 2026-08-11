import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../engine/engine_capabilities.dart';
import '../engine/engine_error_messages.dart';
import '../engine/engine_exception.dart';
import '../engine/engine_registry.dart';
import '../engine/engine_request.dart';
import '../engine/engine_stage.dart';
import '../engine/engine_target.dart';
import '../engine/generation_handle.dart';
import '../engine/generation_options.dart';
import '../models/history_entry.dart';
import '../models/rewrite_output.dart';
import '../models/rewrite_request.dart';
import '../models/rewrite_result.dart';
import '../services/config_store.dart';
import '../services/prompt_builder.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';

/// Thrown by [RewriteController.rewrite] when there is no text to act on.
///
/// Not an [EngineException]: the request never reaches an engine, so this is
/// input validation rather than something an engine failed at.
class EmptySourceError implements Exception {
  const EmptySourceError();
}

/// Orchestrates the full rewrite flow (engine dispatch + history).
class RewriteController extends ChangeNotifier {
  RewriteController({
    required this._registry,
    required this._settings,
    required this._storage,
    required this._configStore,
  });

  final EngineRegistry _registry;
  final SettingsService _settings;
  final StorageService _storage;
  final ConfigStore _configStore;

  // Editor state.
  String _sourceText = '';
  String _toneId = 'professional';
  RewriteIntensity _intensity = RewriteIntensity.moderate;
  RewriteLength _length = RewriteLength.same;
  final List<String> _audience = [];
  String _customInstruction = '';
  int _variantCount = 1;

  // Run state.
  bool _isRunning = false;
  GenerationHandle? _active;
  String _streamingText = '';
  EngineStage _stage = EngineStage.preparing;
  final Stopwatch _elapsed = Stopwatch();
  RewriteResult? _lastResult;
  String? _lastError;

  String get sourceText => _sourceText;
  String get toneId => _toneId;
  RewriteIntensity get intensity => _intensity;
  RewriteLength get length => _length;
  List<String> get audience => List.unmodifiable(_audience);
  String get customInstruction => _customInstruction;
  int get variantCount => _variantCount;

  bool get isRunning => _isRunning;
  bool get isCancelling => _active?.isCancelled ?? false;
  String get streamingText => _streamingText;
  EngineStage get stage => _stage;
  Duration get elapsed => _elapsed.elapsed;
  RewriteResult? get lastResult => _lastResult;
  String? get lastError => _lastError;

  /// Capabilities of the engine the current model selection would run on —
  /// what the UI's stage copy adapts to.
  ///
  /// Runs inside widget `build()`, so it uses `maybeResolve` rather than
  /// `resolve` — a missing engine here must never throw mid-frame. Falls
  /// back to capabilities with no special-case copy, which is the same
  /// "genuinely unknown" default `stageLabel` already treats correctly.
  EngineCapabilities get capabilities =>
      _registry.maybeResolve(_target)?.capabilities ??
      const EngineCapabilities(needsLocalInstall: false, requiresNetwork: false);

  bool get canRewrite => _sourceText.trim().isNotEmpty && !_isRunning;

  // Only the local engine exists today; the model id already distinguishes
  // catalog entries, so this is the one place that would change to route by
  // processing mode once a cloud engine is registered alongside it.
  EngineTarget get _target =>
      EngineTarget(engineId: 'local.llama', modelRef: _settings.selectedModelId);

  void setSource(String text) {
    if (text == _sourceText) return;
    _sourceText = text;
    notifyListeners();
  }

  void setTone(String toneId) {
    _toneId = toneId;
    notifyListeners();
  }

  void setIntensity(RewriteIntensity value) {
    _intensity = value;
    notifyListeners();
  }

  void setLength(RewriteLength value) {
    _length = value;
    notifyListeners();
  }

  void toggleAudience(String audience) {
    if (_audience.contains(audience)) {
      _audience.remove(audience);
    } else {
      _audience.add(audience);
    }
    notifyListeners();
  }

  void setCustomInstruction(String value) {
    _customInstruction = value;
    notifyListeners();
  }

  void setVariantCount(int value) {
    _variantCount = value.clamp(1, 3);
    notifyListeners();
  }

  RewriteRequest get _request => RewriteRequest(
    sourceText: _sourceText,
    toneId: _toneId,
    intensity: _intensity,
    length: _length,
    audience: List.of(_audience),
    customInstruction: _customInstruction,
    variantCount: _variantCount,
  );

  /// Runs the rewrite. Throws [EmptySourceError] or an [EngineException] on
  /// failure; resolves to an empty result if cancelled via [stop].
  Future<RewriteResult> rewrite() async {
    if (_isRunning) return _lastResult ?? RewriteResult.empty(_request);
    if (_sourceText.trim().isEmpty) {
      throw const EmptySourceError();
    }

    final request = _request;
    _isRunning = true;
    _active = null;
    _streamingText = '';
    _stage = EngineStage.preparing;
    _elapsed
      ..reset()
      ..start();
    _lastError = null;
    _lastResult = null;
    notifyListeners();

    try {
      final target = _target;
      final engine = _registry.resolve(target);
      await engine.prepare(target);

      final tone = _configStore.toneById(_toneId);
      final prompt = PromptBuilder.build(request, tone: tone);
      final options = GenerationOptions(
        temperature: tone.temperature,
        maxOutputTokens: AppConstants.defaultMaxTokens,
      );

      final handle = engine.start(
        EngineRequest(target: target, prompt: prompt, options: options),
      );
      _active = handle;
      notifyListeners();

      final subscription = handle.events.listen((event) {
        switch (event) {
          case StageChanged(:final stage):
            _stage = stage;
          case TokenDelta(:final delta):
            _streamingText += delta;
        }
        notifyListeners();
      });

      final RewriteOutput output;
      try {
        output = await handle.done;
      } finally {
        await subscription.cancel();
      }

      final variants = PromptBuilder.parseVariants(
        output.text,
        expected: _variantCount,
      );
      final outputs = variants
          .map(
            (v) => RewriteOutput(
              text: v,
              tokensGenerated: output.tokensGenerated,
              generationTimeMs: output.generationTimeMs,
            ),
          )
          .toList();

      final result = RewriteResult(
        outputs: outputs,
        request: request,
        createdAt: DateTime.now(),
      );

      await _saveToHistory(result);
      _lastResult = result;
      _streamingText = '';
      return result;
    } on GenerationCancelledException {
      return RewriteResult.empty(request);
    } on EngineException catch (e) {
      _lastError = describeEngineError(e);
      rethrow;
    } finally {
      _isRunning = false;
      _active = null;
      _elapsed.stop();
      notifyListeners();
    }
  }

  Future<void> stop() async {
    final active = _active;
    if (active == null || active.isCancelled) return;
    final cancelling = active.cancel();
    notifyListeners();
    await cancelling;
  }

  Future<void> _saveToHistory(RewriteResult result) async {
    try {
      final request = result.request;
      await _storage.insertHistory(
        HistoryEntry(
          id: 0,
          original: request.sourceText,
          rewritten: result.primary.text,
          toneId: request.toneId,
          intensityLabel: request.intensity.label,
          lengthLabel: request.length.label,
          createdAt: result.createdAt ?? DateTime.now(),
        ),
      );
    } catch (_) {
      // History is best-effort; never fail the rewrite because of it.
    }
  }
}
