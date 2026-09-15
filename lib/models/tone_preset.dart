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
/// share. There is no `seed` field to go with them: the on-device plugin
/// (`packages/rescripto_llama`) seeds each generation itself and takes no
/// seed parameter, so a seed slider here would silently do nothing locally.
/// Adding one needs a change to that plugin first.
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
  // Each instruction says what the tone should sound like and, where the
  // tone invites it, what it must not add. The shared rules in
  // `PromptBuilder` keep every tone from sliding into filler or hype; these
  // lines keep the tones from sounding the same.
  //
  // Marketing and Persuasive name the buzzwords outright. Over four samples
  // each, that took them from 5 of 8 outputs to 0 of 8 on gpt-oss-120b and
  // from 5 of 8 to 2 of 8 on Qwen 2.5 1.5B.
  static const List<TonePreset> builtIns = [
    TonePreset(
      id: 'professional',
      name: 'Professional',
      iconToken: 'business_center_outlined',
      description: 'Clear and polished, ready for work.',
      instruction:
          'Professional, the way a capable colleague writes at work: clear, '
          'direct and polite. Fix slang and sloppy spelling, but keep it '
          'human. Contractions are fine. No corporate filler or buzzwords.',
      temperature: 0.4,
    ),
    TonePreset(
      id: 'casual',
      name: 'Casual',
      iconToken: 'waving_hand_outlined',
      description: 'Relaxed, like a message to a friend.',
      instruction:
          'Casual and relaxed, like a text to a friend. Contractions and '
          'short sentences are good. Do not add slang, emoji or jokes the '
          'draft does not have.',
      temperature: 0.7,
    ),
    TonePreset(
      id: 'friendly',
      name: 'Friendly',
      iconToken: 'sentiment_satisfied_alt_outlined',
      description: 'Warm and approachable.',
      instruction:
          'Warm and friendly, like someone who is glad to help. Kind without '
          'gushing: no extra praise, exclamation marks or excitement the '
          'draft does not have.',
      temperature: 0.6,
    ),
    TonePreset(
      id: 'formal',
      name: 'Formal',
      iconToken: 'account_balance_outlined',
      description: 'Proper and official.',
      instruction:
          'Formal and respectful, with complete sentences and no '
          'contractions or slang. Plain and direct rather than stiff or '
          'wordy.',
      temperature: 0.3,
    ),
    TonePreset(
      id: 'academic',
      name: 'Academic',
      iconToken: 'school_outlined',
      description: 'Precise and well reasoned.',
      instruction:
          'Academic: precise terms, clear logical links and an objective '
          'voice. Keep each claim exactly as certain as the draft makes it. '
          'Plain academic English, not inflated vocabulary.',
      temperature: 0.3,
    ),
    TonePreset(
      id: 'creative',
      name: 'Creative',
      iconToken: 'palette_outlined',
      description: 'Vivid and expressive.',
      instruction:
          'Creative: rework the wording with vivid, concrete, surprising '
          'word choices that make it more enjoyable to read. Keep every fact. '
          'Avoid cliches and stock imagery.',
      temperature: 0.9,
    ),
    TonePreset(
      id: 'concise',
      name: 'Concise',
      iconToken: 'compress_outlined',
      description: 'Short and to the point.',
      instruction:
          'Concise: as short as it can be while keeping every fact, request '
          'and deadline. Cut filler and repetition, but keep natural '
          'sentences, not a telegram.',
      temperature: 0.4,
    ),
    TonePreset(
      id: 'persuasive',
      name: 'Persuasive',
      iconToken: 'trending_up_outlined',
      description: 'Makes a clear case.',
      instruction:
          'Persuasive: lead with the strongest point and make the ask clear. '
          'Use only the reasons and facts in the draft. No hype, invented '
          'benefits or pressure tactics, and avoid words like "seamless", '
          '"effortless" and "powerful".',
      temperature: 0.6,
    ),
    TonePreset(
      id: 'empathetic',
      name: 'Empathetic',
      iconToken: 'favorite_outline',
      description: 'Kind and understanding.',
      instruction:
          'Empathetic: kind, gentle and understanding. Soften blunt wording '
          'and show care, without adding apologies, promises or feelings the '
          'draft does not express.',
      temperature: 0.6,
    ),
    TonePreset(
      id: 'humorous',
      name: 'Humorous',
      iconToken: 'sentiment_very_satisfied_outlined',
      description: 'Light and witty.',
      instruction:
          'Humorous: a light, witty turn of phrase in the wording itself, at '
          'about the same length. Keep every fact and request clear. Never '
          'mean, and no jokes about things the draft does not mention.',
      // 0.9 sent Qwen 2.5 1.5B off into a five-times-longer ramble about a
      // "festive period". Still loose enough for wordplay on cloud models.
      temperature: 0.75,
    ),
    TonePreset(
      id: 'confident',
      name: 'Confident',
      iconToken: 'bolt_outlined',
      description: 'Direct and decisive.',
      instruction:
          'Confident and direct. Drop timid hedges and filler such as "I '
          'think", "maybe", "just" and "sorry to bother you". Keep a doubt '
          'only when the facts themselves are unsure.',
      temperature: 0.5,
    ),
    TonePreset(
      id: 'diplomatic',
      name: 'Diplomatic',
      iconToken: 'handshake_outlined',
      description: 'Tactful and balanced.',
      instruction:
          'Diplomatic: tactful and balanced. Soften criticism and '
          'disagreement so it is easy to hear, while keeping the actual point '
          'clear.',
      temperature: 0.5,
    ),
    TonePreset(
      id: 'technical',
      name: 'Technical',
      iconToken: 'memory_outlined',
      description: 'Exact and factual.',
      instruction:
          'Technical: exact, specific and unambiguous, using the right '
          'technical terms. Keep identifiers, numbers and units exactly as '
          'written. No marketing language.',
      temperature: 0.3,
    ),
    TonePreset(
      id: 'marketing',
      name: 'Marketing',
      iconToken: 'campaign_outlined',
      description: 'Upbeat and benefit-focused.',
      instruction:
          'Marketing: upbeat and benefit-focused, showing the reader what '
          'the product does for them. Only benefits the draft states. No '
          'superlatives or invented claims, and avoid words like "seamless", '
          '"effortless" and "powerful".',
      temperature: 0.8,
    ),
  ];
}
