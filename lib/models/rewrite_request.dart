/// How strongly the text is rewritten.
enum RewriteIntensity {
  light(0.15, 'Light polish'),
  moderate(0.5, 'Moderate'),
  full(0.85, 'Full rewrite');

  const RewriteIntensity(this.factor, this.label);

  /// 0.0 = only light polish, 1.0 = complete rework.
  final double factor;
  final String label;
}

/// Desired output length relative to the input.
enum RewriteLength {
  shorter(-1, 'Shorter'),
  same(0, 'Same'),
  longer(1, 'Longer');

  const RewriteLength(this.delta, this.label);

  /// -1 = shorter, 0 = keep length, +1 = longer.
  final int delta;
  final String label;
}

/// A complete rewrite request prepared by the UI.
class RewriteRequest {
  const RewriteRequest({
    required this.sourceText,
    required this.toneId,
    required this.intensity,
    required this.length,
    this.audience = const [],
    this.customInstruction = '',
    this.variantCount = 1,
  });

  final String sourceText;
  final String toneId;
  final RewriteIntensity intensity;
  final RewriteLength length;

  /// Audience tags, e.g. ['coworkers'], ['a teacher'], ['customers'].
  final List<String> audience;

  /// Optional user-provided free-text instruction.
  final String customInstruction;

  /// Number of alternative versions to request (1-3).
  final int variantCount;

  RewriteRequest copyWith({
    String? sourceText,
    String? toneId,
    RewriteIntensity? intensity,
    RewriteLength? length,
    List<String>? audience,
    String? customInstruction,
    int? variantCount,
  }) {
    return RewriteRequest(
      sourceText: sourceText ?? this.sourceText,
      toneId: toneId ?? this.toneId,
      intensity: intensity ?? this.intensity,
      length: length ?? this.length,
      audience: audience ?? this.audience,
      customInstruction: customInstruction ?? this.customInstruction,
      variantCount: variantCount ?? this.variantCount,
    );
  }
}
