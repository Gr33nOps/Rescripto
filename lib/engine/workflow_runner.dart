import 'package:flutter/foundation.dart';

import '../models/history_entry.dart';
import '../models/rewrite_request.dart';
import '../models/workflow_definition.dart';
import '../models/workflow_step.dart';
import '../services/config_store.dart';
import '../services/prompt_builder.dart';
import '../services/refusal_detector.dart';
import '../services/storage_service.dart';
import 'active_request_registry.dart';
import 'engine_error_messages.dart';
import 'engine_exception.dart';
import 'engine_registry.dart';
import 'engine_request.dart';
import 'engine_stage.dart';
import 'generation_handle.dart';
import 'generation_options.dart';

/// Runs a [WorkflowDefinition]'s steps in order, feeding step *N*'s output
/// into step *N+1* as input text.
///
/// Deliberately its own class rather than a loop inside
/// `RewriteController.rewrite()`. That method is explicitly single-shot and
/// non-reentrant (`if (_isRunning) return`) and its `finally` block owns a
/// single `_isRunning`/`_active`/`_elapsed` triple — looping it recursively
/// would mean either fighting that guard on every step or quietly breaking
/// it. `WorkflowRunner` owns its own run state instead and drives the
/// engine registry directly, the same way `RewriteController._run` does,
/// rather than calling through `RewriteController` at all.
///
/// Only the final step's output is saved to history. A workflow's
/// intermediate outputs are real ("did step 2 do what I expected") and
/// worth showing live during the run — see [stepOutputs] — but persisting
/// them would need a `workflow_run`/`workflow_run_step` history schema on
/// top of the `workflow`/`workflow_step` definition tables this phase
/// already adds. Accepted as a real gap rather than built speculatively;
/// `HistoryEntry` still has no column for it.
class WorkflowRunner extends ChangeNotifier {
  WorkflowRunner({
    required this._registry,
    required this._configStore,
    required this._storage,
    required this._activeRequests,
  });

  final EngineRegistry _registry;
  final ConfigStore _configStore;
  final StorageService _storage;
  final ActiveRequestRegistry _activeRequests;

  bool _isRunning = false;
  int _currentStepIndex = -1;
  int _totalSteps = 0;
  final List<String> _stepOutputs = [];
  String _currentStreamingText = '';
  EngineStage _stage = EngineStage.preparing;
  String? _lastError;
  GenerationHandle? _active;

  bool get isRunning => _isRunning;
  bool get isCancelling => _active?.isCancelled ?? false;

  /// -1 before a run starts.
  int get currentStepIndex => _currentStepIndex;
  int get totalSteps => _totalSteps;
  List<String> get stepOutputs => List.unmodifiable(_stepOutputs);
  String get currentStreamingText => _currentStreamingText;
  EngineStage get stage => _stage;
  String? get lastError => _lastError;

  /// Runs every step of [definition] against [sourceText] in order, saves a
  /// [HistoryEntry] for the final output, and returns it.
  ///
  /// Throws [StateError] if a run is already in progress — mirrors
  /// `RewriteController.rewrite`'s non-reentrancy, but as a thrown error
  /// rather than a silent early return, since nothing here has an existing
  /// in-flight result to hand back instead.
  Future<String> run(WorkflowDefinition definition, String sourceText) async {
    if (_isRunning) {
      throw StateError('A workflow is already running.');
    }
    if (definition.steps.isEmpty) {
      throw ArgumentError('Workflow "${definition.name}" has no steps.');
    }

    _isRunning = true;
    _currentStepIndex = -1;
    _totalSteps = definition.steps.length;
    _stepOutputs.clear();
    _lastError = null;
    notifyListeners();

    var text = sourceText;
    try {
      for (var i = 0; i < definition.steps.length; i++) {
        _currentStepIndex = i;
        _currentStreamingText = '';
        _stage = EngineStage.preparing;
        notifyListeners();

        text = await _runStep(definition.steps[i], text);
        _stepOutputs.add(text);
        notifyListeners();
      }

      await _saveToHistory(definition, sourceText, text);
      return text;
    } on EngineException catch (e) {
      _lastError = describeEngineError(e);
      rethrow;
    } finally {
      _isRunning = false;
      _active = null;
      notifyListeners();
    }
  }

  Future<void> cancel() async {
    final active = _active;
    if (active == null || active.isCancelled) return;
    await active.cancel();
  }

  Future<String> _runStep(WorkflowStep step, String inputText) async {
    final engine = _registry.resolve(step.target);
    await engine.prepare(step.target);

    final tone = _configStore.toneById(step.toneId);
    final audienceLabels = step.audience.map((id) => _configStore.audienceById(id).label).toList();
    final request = RewriteRequest(
      sourceText: inputText,
      toneId: step.toneId,
      intensity: step.intensity,
      length: step.length,
      audience: step.audience,
      customInstruction: step.customInstruction,
      variantCount: 1,
    );
    final options = GenerationOptions(
      temperature: tone.temperature,
      topP: tone.topP,
      topK: tone.topK,
      repeatPenalty: tone.repeatPenalty,
      maxOutputTokens: tone.maxOutputTokens,
      stopSequences: tone.stopSequences,
    );

    Future<List<String>> attempt({required bool strictRetry}) async {
      final prompt = PromptBuilder.build(
        request,
        tone: tone,
        audienceLabels: audienceLabels,
        strictRetry: strictRetry,
      );
      final handle = engine.start(
        EngineRequest(target: step.target, prompt: prompt, options: options),
      );
      _active = handle;
      _activeRequests.register(handle);

      final subscription = handle.events.listen((event) {
        switch (event) {
          case StageChanged(:final stage):
            _stage = stage;
          case TokenDelta(:final delta):
            _currentStreamingText += delta;
        }
        notifyListeners();
      });

      try {
        final output = await handle.done;
        final variants = PromptBuilder.parseVariants(output.text, expected: 1);
        if (variants.isEmpty) throw const EmptyResponseException();
        return variants;
      } finally {
        await subscription.cancel();
        _activeRequests.unregister(handle);
      }
    }

    var variants = await attempt(strictRetry: false);

    // A refusal arrives as a perfectly normal completion — without this a
    // step's "I can't assist with that…" would flow into the next step as
    // if it were real rewritten text, or be saved as the workflow's final
    // result. Same one-retry-then-give-up treatment as RewriteController;
    // see RefusalDetector.looksLikeRefusal for why it's deliberately
    // conservative about what counts.
    if (RefusalDetector.looksLikeRefusal(variants)) {
      _currentStreamingText = '';
      notifyListeners();
      variants = await attempt(strictRetry: true);
      if (RefusalDetector.looksLikeRefusal(variants)) {
        throw const ModelRefusedException();
      }
    }

    return variants.first;
  }

  Future<void> _saveToHistory(
    WorkflowDefinition definition,
    String original,
    String finalOutput,
  ) async {
    try {
      final lastStep = definition.steps.last;
      await _storage.insertHistory(
        HistoryEntry(
          id: 0,
          original: original,
          rewritten: finalOutput,
          toneId: lastStep.toneId,
          intensityLabel: lastStep.intensity.label,
          lengthLabel: lastStep.length.label,
          createdAt: DateTime.now(),
        ),
      );
    } catch (_) {
      // History is best-effort; never fail the workflow because of it.
    }
  }
}
