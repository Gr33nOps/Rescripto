import 'dart:convert';

/// A named style/tone that the rewrite engine can apply to text.
///
/// Pure Dart: [iconToken] is a string resolved through `IconCatalog`, not an
/// `IconData` directly — see that class for why. This is also what makes the
/// class serializable, which storing it in SQLite requires.
///
/// [topP], [topK], [repeatPenalty], [maxOutputTokens], and [stopSequences]
/// mirror `GenerationOptions`' fields, letting Pro mode tune sampling per
/// tone rather than only via the hardcoded defaults every tone used to
/// share. There is no `seed` field to go with them: the vendored
/// `flutter_llama` plugin's `GenerationParams` has no seed parameter to pass
/// one through to, so exposing a seed slider here would be a control that
/// silently does nothing on-device. Left out rather than shipped broken;
/// adding it needs a change to the vendored plugin, not this class.
class TonePreset {
  const TonePreset({
    required this.id,
    required this.name,
    required this.iconToken,
    required this.description,
    required this.instruction,
    required this.temperature,
    this.topP = 0.95,
    this.topK = 40,
    this.repeatPenalty = 1.1,
    this.maxOutputTokens = 1024,
    this.stopSequences = const [],
    this.isBuiltin = false,
  });

  final String id;
  final String name;
  final String iconToken;
  final String description;

  /// Instruction injected into the prompt describing how to sound.
  final String instruction;

  /// Sampling temperature for this tone (0.0 - 1.0).
  final double temperature;

  final double topP;
  final int topK;
  final double repeatPenalty;
  final int maxOutputTokens;

  /// Merged on top of whatever the engine's own chat template requires.
  final List<String> stopSequences;

  /// Whether this tone ships with the app. Not part of [toMap] — `is_builtin`
  /// is a column `ConfigStore` manages itself (0 on `upsertTone`, 1 when
  /// `ConfigSeeder` writes a seed row), never something the editor's own
  /// `toMap()`/`copyWith()` round-trips as ordinary content. An editor still
  /// needs to *read* it, though, to know whether "Reset to default" applies
  /// — which is the entire reason this field exists on the model at all.
  final bool isBuiltin;

  TonePreset copyWith({
    String? name,
    String? iconToken,
    String? description,
    String? instruction,
    double? temperature,
    double? topP,
    int? topK,
    double? repeatPenalty,
    int? maxOutputTokens,
    List<String>? stopSequences,
  }) {
    return TonePreset(
      id: id,
      name: name ?? this.name,
      iconToken: iconToken ?? this.iconToken,
      description: description ?? this.description,
      instruction: instruction ?? this.instruction,
      temperature: temperature ?? this.temperature,
      topP: topP ?? this.topP,
      topK: topK ?? this.topK,
      repeatPenalty: repeatPenalty ?? this.repeatPenalty,
      maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
      stopSequences: stopSequences ?? this.stopSequences,
      isBuiltin: isBuiltin,
    );
  }

  Map<String, Object?> toMap() => {
    'id': id,
    'name': name,
    'icon_token': iconToken,
    'description': description,
    'instruction': instruction,
    'temperature': temperature,
    'top_p': topP,
    'top_k': topK,
    'repeat_penalty': repeatPenalty,
    'max_output_tokens': maxOutputTokens,
    'stop_sequences': jsonEncode(stopSequences),
  };

  factory TonePreset.fromMap(Map<String, Object?> map) => TonePreset(
    id: map['id'] as String,
    name: map['name'] as String,
    iconToken: map['icon_token'] as String,
    description: map['description'] as String? ?? '',
    instruction: map['instruction'] as String,
    temperature: (map['temperature'] as num).toDouble(),
    topP: (map['top_p'] as num?)?.toDouble() ?? 0.95,
    topK: (map['top_k'] as num?)?.toInt() ?? 40,
    repeatPenalty: (map['repeat_penalty'] as num?)?.toDouble() ?? 1.1,
    maxOutputTokens: (map['max_output_tokens'] as num?)?.toInt() ?? 1024,
    stopSequences: (jsonDecode(map['stop_sequences'] as String? ?? '[]') as List<Object?>)
        .map((s) => s as String)
        .toList(),
    isBuiltin: (map['is_builtin'] as int? ?? 0) != 0,
  );
}

/// The built-in tone catalog, seeded into `tone_preset` by `ConfigSeeder`.
///
/// This used to be the app's only source of tones, read directly at every
/// call site. It's the seed source now — `ConfigStore` is what the rest of
/// the app reads from — kept here verbatim because a `static const` list is
/// still the right shape for content that ships with the app.
class ToneLibrary {
  static const List<TonePreset> builtIns = [
    TonePreset(
      id: 'professional',
      name: 'Professional',
      iconToken: 'business_center_outlined',
      description: 'Polished, competent and workplace-ready.',
      instruction:
          'Rewrite in a professional, competent tone suitable for work. '
          'Be clear, confident, and well-organized. Remove casual filler.',
      temperature: 0.4,
    ),
    TonePreset(
      id: 'casual',
      name: 'Casual',
      iconToken: 'waving_hand_outlined',
      description: 'Relaxed, everyday, friendly conversation.',
      instruction:
          'Rewrite in a casual, relaxed, everyday tone as if texting a friend. '
          'Keep it light and natural. Contractions are fine.',
      temperature: 0.7,
    ),
    TonePreset(
      id: 'friendly',
      name: 'Friendly',
      iconToken: 'sentiment_satisfied_alt_outlined',
      description: 'Warm, approachable and positive.',
      instruction:
          'Rewrite in a warm, friendly, approachable tone. Sound positive and '
          'encouraging, like a helpful acquaintance.',
      temperature: 0.6,
    ),
    TonePreset(
      id: 'formal',
      name: 'Formal',
      iconToken: 'account_balance_outlined',
      description: 'Proper, official and structured.',
      instruction:
          'Rewrite in a formal, official register with complete sentences, '
          'no contractions, and a respectful, structured style.',
      temperature: 0.3,
    ),
    TonePreset(
      id: 'academic',
      name: 'Academic',
      iconToken: 'school_outlined',
      description: 'Scholarly, precise and well-reasoned.',
      instruction:
          'Rewrite in an academic register: precise terminology, logical '
          'structure, cautious hedging, and objective reasoning.',
      temperature: 0.3,
    ),
    TonePreset(
      id: 'creative',
      name: 'Creative',
      iconToken: 'palette_outlined',
      description: 'Imaginative, vivid and expressive.',
      instruction:
          'Rewrite with creativity: vivid language, imagery, and fresh word '
          'choices while keeping the same core meaning.',
      temperature: 0.9,
    ),
    TonePreset(
      id: 'concise',
      name: 'Concise',
      iconToken: 'compress_outlined',
      description: 'Short, punchy and to the point.',
      instruction:
          'Rewrite more concisely. Cut fluff and redundancy. Keep it as short '
          'as possible without losing key information.',
      temperature: 0.4,
    ),
    TonePreset(
      id: 'persuasive',
      name: 'Persuasive',
      iconToken: 'trending_up_outlined',
      description: 'Convincing, compelling and action-oriented.',
      instruction:
          'Rewrite persuasively to convince the reader. Use confident claims, '
          'strong reasoning, and a call to action where appropriate.',
      temperature: 0.6,
    ),
    TonePreset(
      id: 'empathetic',
      name: 'Empathetic',
      iconToken: 'favorite_outline',
      description: 'Kind, caring and understanding.',
      instruction:
          'Rewrite with empathy and sensitivity. Acknowledge the reader\'s '
          'feelings and perspective. Be gentle and supportive.',
      temperature: 0.6,
    ),
    TonePreset(
      id: 'humorous',
      name: 'Humorous',
      iconToken: 'sentiment_very_satisfied_outlined',
      description: 'Light, witty and playful.',
      instruction:
          'Rewrite with light humor and wit. Add a playful, clever twist '
          'without being mean or off-topic.',
      temperature: 0.9,
    ),
    TonePreset(
      id: 'confident',
      name: 'Confident',
      iconToken: 'bolt_outlined',
      description: 'Strong, assertive and decisive.',
      instruction:
          'Rewrite with confidence and authority. Be assertive and decisive. '
          'Remove hesitation and uncertainty.',
      temperature: 0.5,
    ),
    TonePreset(
      id: 'diplomatic',
      name: 'Diplomatic',
      iconToken: 'handshake_outlined',
      description: 'Tactful, polite and balanced.',
      instruction:
          'Rewrite diplomatically: tactful, polite, balanced. Acknowledge '
          'other viewpoints and soften potential disagreements.',
      temperature: 0.5,
    ),
    TonePreset(
      id: 'technical',
      name: 'Technical',
      iconToken: 'memory_outlined',
      description: 'Precise, factual and jargon-friendly.',
      instruction:
          'Rewrite in a technical style: precise, factual, using appropriate '
          'technical terminology. Be specific and unambiguous.',
      temperature: 0.3,
    ),
    TonePreset(
      id: 'marketing',
      name: 'Marketing',
      iconToken: 'campaign_outlined',
      description: 'Energetic, benefit-focused and appealing.',
      instruction:
          'Rewrite in a marketing style: energetic, benefit-focused, and '
          'engaging. Highlight value and appeal to the reader.',
      temperature: 0.8,
    ),
  ];
}
