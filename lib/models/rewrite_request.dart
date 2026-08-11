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

  /// A workflow step needs to persist the request that produced it — see
  /// `workflow_step.step_options` — so this round-trips through JSON rather
  /// than SQLite columns directly, the way `CloudFallbackConsent` does.
  Map<String, Object?> toMap() => {
    'sourceText': sourceText,
    'toneId': toneId,
    'intensity': intensity.name,
    'length': length.name,
    'audience': audience,
    'customInstruction': customInstruction,
    'variantCount': variantCount,
  };

  factory RewriteRequest.fromMap(Map<String, Object?> map) => RewriteRequest(
    sourceText: map['sourceText'] as String,
    toneId: map['toneId'] as String,
    intensity: RewriteIntensity.values.byName(map['intensity'] as String),
    length: RewriteLength.values.byName(map['length'] as String),
    audience: (map['audience'] as List<Object?>? ?? const [])
        .map((a) => a as String)
        .toList(),
    customInstruction: map['customInstruction'] as String? ?? '',
    variantCount: map['variantCount'] as int? ?? 1,
  );

  @override
  bool operator ==(Object other) =>
      other is RewriteRequest &&
      other.sourceText == sourceText &&
      other.toneId == toneId &&
      other.intensity == intensity &&
      other.length == length &&
      _listEquals(other.audience, audience) &&
      other.customInstruction == customInstruction &&
      other.variantCount == variantCount;

  @override
  int get hashCode => Object.hash(
    sourceText,
    toneId,
    intensity,
    length,
    Object.hashAll(audience),
    customInstruction,
    variantCount,
  );

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
