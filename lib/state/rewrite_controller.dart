import 'package:flutter/foundation.dart';

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

    _isRunning = true;
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

      final prompt = PromptBuilder.build(_request, modelFamily: model.family);
      final tone = ToneLibrary.byId(_toneId);

      final output = await _llm.generate(
        prompt,
        temperature: tone.temperature,
        maxTokens: AppContext.maxTokens,
        onToken: (partial) {
          _streamingText = partial;
          notifyListeners();
        },
      );

      if (output.isEmpty) {
        throw RewriteException(
            'The model returned an empty result. Try a different intensity.');
      }

      final variants = PromptBuilder.parseVariants(
        output.text,
        expected: _variantCount,
      );
      final outputs = variants
          .map((v) => RewriteOutput(
                text: v,
                tokensGenerated: output.tokensGenerated,
                generationTimeMs: output.generationTimeMs,
              ))
          .toList();

      final result = RewriteResult(
        outputs: outputs,
        request: _request,
        createdAt: DateTime.now(),
      );

      await _saveToHistory(result, output.text);
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
      _isRunning = false;
      notifyListeners();
    }
  }

  Future<void> stop() async {
    await _llm.stopGeneration();
    _isRunning = false;
    notifyListeners();
  }

  Future<void> _saveToHistory(RewriteResult result, String primaryText) async {
    try {
      await _storage.insertHistory(HistoryEntry(
        id: 0,
        original: _sourceText,
        rewritten: primaryText,
        toneId: _toneId,
        intensityLabel: _intensity.label,
        lengthLabel: _length.label,
        createdAt: DateTime.now(),
      ));
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
    return 'Rewrite failed: $e';
  }
}

/// Small holder so max tokens can be tuned in one place.
abstract final class AppContext {
  static int maxTokens = 1024;
}
