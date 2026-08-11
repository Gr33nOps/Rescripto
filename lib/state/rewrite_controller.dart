import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../engine/active_request_registry.dart';
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
import '../services/routing/target_router.dart';
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
    required this._storage,
    required this._configStore,
    required this._router,
    required this._activeRequests,
  });

  final EngineRegistry _registry;
  final StorageService _storage;
  final ConfigStore _configStore;
  final TargetRouter _router;
  final ActiveRequestRegistry _activeRequests;

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

  // Hybrid local→cloud fallback. Only ever set from inside `_run`, and only
  // ever cleared by `dismissFallback`/`retryWithFallback` or the start of
  // the next `rewrite()` call.
  RewriteRequest? _pendingFallbackRequest;
  EngineTarget? _pendingFallback;
  bool _pendingFallbackNeedsConsent = false;

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

  /// Where a rewrite of the current input would run right now, and why —
  /// cheap enough to read on every keystroke (`RoutingDecision` does no
  /// I/O), which is what lets `processing_indicator.dart` recompute it live.
  RoutingDecision get routing => _router.route(inputLength: _sourceText.length);

  /// The other engine to retry on if the last rewrite failed before
  /// producing any text — null unless [rewrite] just set it.
  EngineTarget? get pendingFallback => _pendingFallback;

  /// Whether using [pendingFallback] needs the user's explicit go-ahead.
  /// True only when the failed attempt was local and the fallback is
  /// cloud — that direction sends text the user never chose to send
  /// anywhere. Cloud failing back to local never needs asking.
  bool get pendingFallbackNeedsConsent => _pendingFallbackNeedsConsent;

  /// Capabilities of the engine [routing] currently resolves to — what the
  /// UI's stage copy adapts to.
  ///
  /// Runs inside widget `build()`, so it uses `maybeResolve` rather than
  /// `resolve` — a missing engine here must never throw mid-frame. Falls
  /// back to capabilities with no special-case copy, which is the same
  /// "genuinely unknown" default `stageLabel` already treats correctly.
  EngineCapabilities get capabilities {
    final target = routing.target;
    if (target == null) {
      return const EngineCapabilities(needsLocalInstall: false, requiresNetwork: false);
    }
    return _registry.maybeResolve(target)?.capabilities ??
        const EngineCapabilities(needsLocalInstall: false, requiresNetwork: false);
  }

  bool get canRewrite => _sourceText.trim().isNotEmpty && !_isRunning;

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

  /// Saved Pro-surface values while in Simple mode, restored on [enterProMode].
  _ProValuesSnapshot? _savedProValues;

  /// Pins intensity/length/audience/custom instruction/variant count to
  /// their defaults, saving whatever they were for [enterProMode] to
  /// restore.
  ///
  /// This state survives a mode switch on its own — controller fields don't
  /// reset themselves — so *hiding* the Pro controls without also resetting
  /// them would leave Simple mode silently affected by values the user can
  /// no longer see a control for (a `variantCount: 3` set in Pro still
  /// producing three variants in Simple, say). Pinning is what closes that
  /// gap; merely hiding the widgets would not.
  void enterSimpleMode() {
    _savedProValues = _ProValuesSnapshot(
      intensity: _intensity,
      length: _length,
      audience: List.of(_audience),
      customInstruction: _customInstruction,
      variantCount: _variantCount,
    );
    _intensity = RewriteIntensity.moderate;
    _length = RewriteLength.same;
    _audience.clear();
    _customInstruction = '';
    _variantCount = 1;
    notifyListeners();
  }

  /// Restores whatever [enterSimpleMode] last pinned over, if anything was.
  void enterProMode() {
    final saved = _savedProValues;
    if (saved == null) return;
    _intensity = saved.intensity;
    _length = saved.length;
    _audience
      ..clear()
      ..addAll(saved.audience);
    _customInstruction = saved.customInstruction;
    _variantCount = saved.variantCount;
    _savedProValues = null;
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

  /// Runs the rewrite on whatever [routing] resolves to right now. Throws
  /// [EmptySourceError] or an [EngineException] on failure; resolves to an
  /// empty result if cancelled via [stop].
  Future<RewriteResult> rewrite() async {
    if (_isRunning) return _lastResult ?? RewriteResult.empty(_request);
    if (_sourceText.trim().isEmpty) {
      throw const EmptySourceError();
    }

    final decision = routing;
    final target = decision.target;
    if (target == null) {
      final error = EngineNotAvailableException(decision.reason);
      _lastError = describeEngineError(error);
      notifyListeners();
      throw error;
    }

    _clearFallback();
    return _run(_request, target, fallback: decision.fallback);
  }

  /// Retries the request that just failed against [pendingFallback].
  ///
  /// A distinct, explicit call rather than a loop inside [rewrite] — that
  /// is what keeps the consent gate for local→cloud fallback un-bypassable.
  /// [pendingFallback] is cleared before the retry even starts, so a second
  /// failure doesn't chain into a third target.
  Future<RewriteResult> retryWithFallback() async {
    final target = _pendingFallback;
    final request = _pendingFallbackRequest;
    if (target == null || request == null) {
      throw StateError('retryWithFallback() called with no pending fallback.');
    }
    _clearFallback();
    return _run(request, target, fallback: null);
  }

  /// Discards a pending fallback offer without acting on it.
  void dismissFallback() {
    if (_pendingFallback == null) return;
    _clearFallback();
    notifyListeners();
  }

  void _clearFallback() {
    _pendingFallback = null;
    _pendingFallbackRequest = null;
    _pendingFallbackNeedsConsent = false;
  }

  Future<RewriteResult> _run(
    RewriteRequest request,
    EngineTarget target, {
    required EngineTarget? fallback,
  }) async {
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

    var emittedAnyText = false;
    GenerationHandle? handle;

    try {
      final engine = _registry.resolve(target);
      await engine.prepare(target);

      final tone = _configStore.toneById(request.toneId);
      final prompt = PromptBuilder.build(request, tone: tone);
      final options = GenerationOptions(
        temperature: tone.temperature,
        maxOutputTokens: AppConstants.defaultMaxTokens,
      );

      handle = engine.start(
        EngineRequest(target: target, prompt: prompt, options: options),
      );
      _active = handle;
      // Lets PanicService's kill switch reach an already-open stream, which
      // NetworkPolicy alone cannot — it's only ever checked before a
      // request is dispatched.
      _activeRequests.register(handle);
      notifyListeners();

      final subscription = handle.events.listen((event) {
        switch (event) {
          case StageChanged(:final stage):
            _stage = stage;
          case TokenDelta(:final delta):
            _streamingText += delta;
            emittedAnyText = true;
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
        expected: request.variantCount,
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
      _offerFallbackIfEligible(
        request: request,
        failedTarget: target,
        fallback: fallback,
        error: e,
        emittedAnyText: emittedAnyText,
      );
      rethrow;
    } finally {
      if (handle != null) _activeRequests.unregister(handle);
      _isRunning = false;
      _active = null;
      _elapsed.stop();
      notifyListeners();
    }
  }

  /// Surfaces [fallback] as [pendingFallback] when it's safe to.
  ///
  /// Never after a token has already streamed to the screen — silently
  /// restarting elsewhere is worse than an error once partial output is
  /// visible. Never for [ProviderAuthException] — that hides a
  /// configuration problem the user needs to fix, not route around.
  /// Cancellation never gets a fallback offer either; the user already
  /// chose to stop.
  void _offerFallbackIfEligible({
    required RewriteRequest request,
    required EngineTarget failedTarget,
    required EngineTarget? fallback,
    required EngineException error,
    required bool emittedAnyText,
  }) {
    if (fallback == null || emittedAnyText) return;
    if (error is ProviderAuthException) return;

    // A local target never carries a providerId; only that direction —
    // sending text the user didn't choose to send off-device — needs an
    // explicit go-ahead.
    _pendingFallbackNeedsConsent = failedTarget.providerId == null;
    _pendingFallback = fallback;
    _pendingFallbackRequest = request;
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

/// What [RewriteController.enterSimpleMode] pins over, for
/// [RewriteController.enterProMode] to restore.
class _ProValuesSnapshot {
  const _ProValuesSnapshot({
    required this.intensity,
    required this.length,
    required this.audience,
    required this.customInstruction,
    required this.variantCount,
  });

  final RewriteIntensity intensity;
  final RewriteLength length;
  final List<String> audience;
  final String customInstruction;
  final int variantCount;
}
