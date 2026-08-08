import 'package:flutter/foundation.dart';

import '../core/constants.dart';
import '../models/ai_model.dart';
import '../models/history_entry.dart';
import '../models/rewrite_output.dart';
import '../models/rewrite_request.dart';
import '../models/rewrite_result.dart';
import '../models/tone_preset.dart';
import '../services/local_llm_service.dart';
import '../services/prompt_builder.dart';
import '../services/settings_service.dart';
import '../services/storage_service.dart';

class RewriteException implements Exception {
  RewriteException(this.message, {this.code});
  final String message;
  final String? code;

  bool get isModelMissing => code == 'model_missing';

  @override
  String toString() => message;
}

/// Orchestrates the full rewrite flow (on-device LLM + history).
class RewriteController extends ChangeNotifier {
  RewriteController({
    required this._llm,
    required this._settings,
    required this._storage,
  });

  final LocalLlmService _llm;
  final SettingsService _settings;
  final StorageService _storage;

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
  bool _isCancelling = false;
  int _operationId = 0;
  int? _cancelledOperationId;
  String _streamingText = '';
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
  bool get isCancelling => _isCancelling;
  String get streamingText => _streamingText;
  RewriteResult? get lastResult => _lastResult;
  String? get lastError => _lastError;

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

  RewriteRequest get _request => RewriteRequest(
    sourceText: _sourceText,
    toneId: _toneId,
    intensity: _intensity,
    length: _length,
    audience: List.of(_audience),
    customInstruction: _customInstruction,
    variantCount: _variantCount,
  );

  /// Runs the on-device rewrite. Throws [RewriteException] on failure.
  Future<RewriteResult> rewrite() async {
    if (_isRunning) return _lastResult ?? RewriteResult.empty(_request);
    if (_sourceText.trim().isEmpty) {
      throw RewriteException('Nothing to rewrite yet.');
    }

    final operationId = ++_operationId;
    final request = _request;
    _isRunning = true;
    _isCancelling = false;
    _cancelledOperationId = null;
    _streamingText = '';
    _lastError = null;
    _lastResult = null;
    notifyListeners();

    try {
      final model = ModelCatalog.byId(_settings.selectedModelId);
      await _llm.loadModel(
        model,
        threads: _settings.threads,
        contextSize: _settings.contextSize,
        useGpu: _settings.useGpu,
      );

      final prompt = PromptBuilder.build(request, modelFamily: model.family);
      final tone = ToneLibrary.byId(_toneId);

      final output = await _llm.generate(
        prompt,
        temperature: tone.temperature,
        maxTokens: AppConstants.defaultMaxTokens,
        onToken: (partial) {
          if (_operationId != operationId ||
              _cancelledOperationId == operationId) {
            return;
          }
          _streamingText = partial;
          notifyListeners();
        },
      );

      if (_cancelledOperationId == operationId) {
        return RewriteResult.empty(request);
      }

      if (output.isEmpty) {
        throw RewriteException(
          'The model returned an empty result. Try a different intensity.',
        );
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
    } on RewriteException {
      rethrow;
    } catch (e) {
      final msg = _describeError(e);
      _lastError = msg;
      throw RewriteException(
        msg,
        code: msg.contains('not downloaded') ? 'model_missing' : null,
      );
    } finally {
      if (_operationId == operationId) {
        _isRunning = false;
        _isCancelling = false;
        _cancelledOperationId = null;
        notifyListeners();
      }
    }
  }

  Future<void> stop() async {
    if (!_isRunning || _isCancelling) return;
    _isCancelling = true;
    _cancelledOperationId = _operationId;
    notifyListeners();
    await _llm.stopGeneration();
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

  String _describeError(Object e) {
    final s = e.toString().toLowerCase();
    if (s.contains('model') && (s.contains('file') || s.contains('found'))) {
      return 'The AI model is not downloaded yet. Open "AI Models" to install it.';
    }
    if (s.contains('out of memory') || s.contains('oom')) {
      return 'Not enough memory on this device. Try a smaller model or lower '
          'context size in Settings.';
    }
    if (s.contains('context') || s.contains('input is too long')) {
      return 'This text is too long for the selected context size. Shorten it '
          'or increase Context size in Settings.';
    }
    return 'Couldn’t complete the rewrite. Try again. If it keeps happening, '
        'restart the app.';
  }
}
