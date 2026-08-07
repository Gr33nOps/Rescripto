import 'package:flutter/material.dart';

/// A named style/tone that the rewrite engine can apply to text.
class TonePreset {
  const TonePreset({
    required this.id,
    required this.name,
    required this.icon,
    required this.description,
    required this.instruction,
    required this.temperature,
    this.warmth = 0.5,
    this.complexity = 0.5,
  });

  final String id;
  final String name;
  final IconData icon;
  final String description;

  /// Instruction injected into the prompt describing how to sound.
  final String instruction;

  /// Sampling temperature for this tone (0.0 - 1.0).
  final double temperature;

  /// 0 = cold/detached, 1 = warm/friendly.
  final double warmth;

  /// 0 = simple/everyday, 1 = complex/sophisticated.
  final double complexity;

  TonePreset copyWith({double? warmth, double? complexity}) {
    return TonePreset(
      id: id,
      name: name,
      icon: icon,
      description: description,
      instruction: instruction,
      temperature: temperature,
      warmth: warmth ?? this.warmth,
      complexity: complexity ?? this.complexity,
    );
  }
}

/// The built-in tone library.
class ToneLibrary {
  static const List<TonePreset> all = [
    TonePreset(
      id: 'professional',
      name: 'Professional',
      icon: Icons.business_center_outlined,
      description: 'Polished, competent and workplace-ready.',
      instruction:
          'Rewrite in a professional, competent tone suitable for work. '
          'Be clear, confident, and well-organized. Remove casual filler.',
      temperature: 0.4,
      warmth: 0.4,
      complexity: 0.5,
    ),
    TonePreset(
      id: 'casual',
      name: 'Casual',
      icon: Icons.waving_hand_outlined,
      description: 'Relaxed, everyday, friendly conversation.',
      instruction:
          'Rewrite in a casual, relaxed, everyday tone as if texting a friend. '
          'Keep it light and natural. Contractions are fine.',
      temperature: 0.7,
      warmth: 0.8,
      complexity: 0.2,
    ),
    TonePreset(
      id: 'friendly',
      name: 'Friendly',
      icon: Icons.sentiment_satisfied_alt_outlined,
      description: 'Warm, approachable and positive.',
      instruction:
          'Rewrite in a warm, friendly, approachable tone. Sound positive and '
          'encouraging, like a helpful acquaintance.',
      temperature: 0.6,
      warmth: 0.9,
      complexity: 0.3,
    ),
    TonePreset(
      id: 'formal',
      name: 'Formal',
      icon: Icons.account_balance_outlined,
      description: 'Proper, official and structured.',
      instruction:
          'Rewrite in a formal, official register with complete sentences, '
          'no contractions, and a respectful, structured style.',
      temperature: 0.3,
      warmth: 0.2,
      complexity: 0.6,
    ),
    TonePreset(
      id: 'academic',
      name: 'Academic',
      icon: Icons.school_outlined,
      description: 'Scholarly, precise and well-reasoned.',
      instruction:
          'Rewrite in an academic register: precise terminology, logical '
          'structure, cautious hedging, and objective reasoning.',
      temperature: 0.3,
      warmth: 0.1,
      complexity: 0.9,
    ),
    TonePreset(
      id: 'creative',
      name: 'Creative',
      icon: Icons.palette_outlined,
      description: 'Imaginative, vivid and expressive.',
      instruction:
          'Rewrite with creativity: vivid language, imagery, and fresh word '
          'choices while keeping the same core meaning.',
      temperature: 0.9,
      warmth: 0.7,
      complexity: 0.5,
    ),
    TonePreset(
      id: 'concise',
      name: 'Concise',
      icon: Icons.compress_outlined,
      description: 'Short, punchy and to the point.',
      instruction:
          'Rewrite more concisely. Cut fluff and redundancy. Keep it as short '
          'as possible without losing key information.',
      temperature: 0.4,
      warmth: 0.3,
      complexity: 0.3,
    ),
    TonePreset(
      id: 'persuasive',
      name: 'Persuasive',
      icon: Icons.trending_up_outlined,
      description: 'Convincing, compelling and action-oriented.',
      instruction:
          'Rewrite persuasively to convince the reader. Use confident claims, '
          'strong reasoning, and a call to action where appropriate.',
      temperature: 0.6,
      warmth: 0.6,
      complexity: 0.5,
    ),
    TonePreset(
      id: 'empathetic',
      name: 'Empathetic',
      icon: Icons.favorite_outline,
      description: 'Kind, caring and understanding.',
      instruction:
          'Rewrite with empathy and sensitivity. Acknowledge the reader\'s '
          'feelings and perspective. Be gentle and supportive.',
      temperature: 0.6,
      warmth: 1.0,
      complexity: 0.3,
    ),
    TonePreset(
      id: 'humorous',
      name: 'Humorous',
      icon: Icons.sentiment_very_satisfied_outlined,
      description: 'Light, witty and playful.',
      instruction:
          'Rewrite with light humor and wit. Add a playful, clever twist '
          'without being mean or off-topic.',
      temperature: 0.9,
      warmth: 0.9,
      complexity: 0.4,
    ),
    TonePreset(
      id: 'confident',
      name: 'Confident',
      icon: Icons.bolt_outlined,
      description: 'Strong, assertive and decisive.',
      instruction:
          'Rewrite with confidence and authority. Be assertive and decisive. '
          'Remove hesitation and uncertainty.',
      temperature: 0.5,
      warmth: 0.5,
      complexity: 0.5,
    ),
    TonePreset(
      id: 'diplomatic',
      name: 'Diplomatic',
      icon: Icons.handshake_outlined,
      description: 'Tactful, polite and balanced.',
      instruction:
          'Rewrite diplomatically: tactful, polite, balanced. Acknowledge '
          'other viewpoints and soften potential disagreements.',
      temperature: 0.5,
      warmth: 0.7,
      complexity: 0.5,
    ),
    TonePreset(
      id: 'technical',
      name: 'Technical',
      icon: Icons.memory_outlined,
      description: 'Precise, factual and jargon-friendly.',
      instruction:
          'Rewrite in a technical style: precise, factual, using appropriate '
          'technical terminology. Be specific and unambiguous.',
      temperature: 0.3,
      warmth: 0.2,
      complexity: 0.8,
    ),
    TonePreset(
      id: 'marketing',
      name: 'Marketing',
      icon: Icons.campaign_outlined,
      description: 'Energetic, benefit-focused and appealing.',
      instruction:
          'Rewrite in a marketing style: energetic, benefit-focused, and '
          'engaging. Highlight value and appeal to the reader.',
      temperature: 0.8,
      warmth: 0.8,
      complexity: 0.4,
    ),
  ];

  static TonePreset byId(String id) {
    return all.firstWhere(
      (t) => t.id == id,
      orElse: () => all.first,
    );
  }
}
