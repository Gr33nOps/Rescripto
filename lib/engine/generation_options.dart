import '../core/constants.dart';

/// Sampling parameters for a single generation request.
///
/// Collects what used to be split three ways: `temperature` read from the
/// tone at the call site, `maxTokens` from [AppConstants], and
/// `topP`/`topK`/`repeatPenalty` hardcoded inside `LocalLlmService.generate`.
///
/// `topK` and `repeatPenalty` are llama.cpp sampling knobs with no equivalent
/// in most cloud chat-completion APIs — a future cloud engine is free to
/// ignore them.
class GenerationOptions {
  const GenerationOptions({
    this.temperature = 0.5,
    this.topP = 0.95,
    this.topK = 40,
    this.repeatPenalty = 1.1,
    this.maxOutputTokens = AppConstants.defaultMaxTokens,
    this.stopSequences = const [],
  });

  final double temperature;
  final double topP;
  final int topK;
  final double repeatPenalty;
  final int maxOutputTokens;

  /// Merged on top of whatever the engine's own chat template requires.
  final List<String> stopSequences;

  GenerationOptions copyWith({
    double? temperature,
    double? topP,
    int? topK,
    double? repeatPenalty,
    int? maxOutputTokens,
    List<String>? stopSequences,
  }) {
    return GenerationOptions(
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      topK: topK ?? this.topK,
      repeatPenalty: repeatPenalty ?? this.repeatPenalty,
      maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
      stopSequences: stopSequences ?? this.stopSequences,
    );
  }
}
