import 'package:flutter/material.dart';

/// A downloadable GGUF model the user can install for rewriting.
class AiModel {
  const AiModel({
    required this.id,
    required this.name,
    required this.family,
    required this.parameters,
    required this.quant,
    required this.fileName,
    required this.downloadUrl,
    required this.sizeMb,
    required this.sizeBytes,
    required this.sha256,
    required this.contextSize,
    required this.isDefault,
    this.languages = const ['English'],
  });

  final String id;
  final String name;
  final String family;

  /// e.g. "1.1B"
  final String parameters;

  /// e.g. "Q4_K_M"
  final String quant;

  final String fileName;
  final String downloadUrl;
  final int sizeMb;
  final int sizeBytes;
  final String sha256;
  final int contextSize;
  final bool isDefault;
  final List<String> languages;

  String get displayName => '$name ($parameters $quant)';

  IconData get familyIcon => switch (family) {
    'llama' => Icons.emoji_nature_outlined,
    'qwen' => Icons.smart_toy_outlined,
    'gemma' => Icons.diamond_outlined,
    'granite' => Icons.terrain_outlined,
    _ => Icons.auto_awesome_outlined,
  };

  /// Local file name used inside the app models directory.
  String get localFileName => fileName;
}

/// Catalog of verified, directly-downloadable GGUF files (HuggingFace).
class ModelCatalog {
  static const List<AiModel> models = [
    AiModel(
      id: 'gemma3-1b',
      name: 'Gemma 3 1B',
      family: 'gemma',
      parameters: '1B',
      quant: 'Q4_K_M',
      fileName: 'gemma-3-1b-it-Q4_K_M.gguf',
      downloadUrl:
          'https://huggingface.co/ggml-org/gemma-3-1b-it-GGUF/resolve/main/gemma-3-1b-it-Q4_K_M.gguf',
      sizeMb: 769,
      sizeBytes: 806058240,
      sha256:
          '8ccc5cd1f1b3602548715ae25a66ed73fd5dc68a210412eea643eb20eb75a135',
      contextSize: 4096,
      isDefault: true,
      languages: ['English', 'Multilingual'],
    ),
    AiModel(
      id: 'llama3.2-1b',
      name: 'Llama 3.2 1B',
      family: 'llama',
      parameters: '1B',
      quant: 'Q4_K_M',
      fileName: 'Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      downloadUrl:
          'https://huggingface.co/bartowski/Llama-3.2-1B-Instruct-GGUF/resolve/main/Llama-3.2-1B-Instruct-Q4_K_M.gguf',
      sizeMb: 770,
      sizeBytes: 807694464,
      sha256:
          '6f85a640a97cf2bf5b8e764087b1e83da0fdb51d7c9fab7d0fece9385611df83',
      contextSize: 4096,
      isDefault: false,
    ),
    AiModel(
      id: 'qwen2.5-1.5b',
      name: 'Qwen 2.5 1.5B',
      family: 'qwen',
      parameters: '1.5B',
      quant: 'Q4_K_M',
      fileName: 'qwen2.5-1.5b-instruct-q4_k_m.gguf',
      downloadUrl:
          'https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf',
      sizeMb: 1066,
      sizeBytes: 1117320736,
      sha256:
          '6a1a2eb6d15622bf3c96857206351ba97e1af16c30d7a74ee38970e434e9407e',
      contextSize: 8192,
      isDefault: false,
      languages: ['English', 'Multilingual'],
    ),
    AiModel(
      id: 'llama3.2-3b',
      name: 'Llama 3.2 3B',
      family: 'llama',
      parameters: '3B',
      quant: 'Q4_K_M',
      fileName: 'Llama-3.2-3B-Instruct-Q4_K_M.gguf',
      downloadUrl:
          'https://huggingface.co/bartowski/Llama-3.2-3B-Instruct-GGUF/resolve/main/Llama-3.2-3B-Instruct-Q4_K_M.gguf',
      sizeMb: 1926,
      sizeBytes: 2019377696,
      sha256:
          '6c1a2b41161032677be168d354123594c0e6e67d2b9227c84f296ad037c728ff',
      contextSize: 4096,
      isDefault: false,
      languages: ['English'],
    ),
  ];

  static AiModel byId(String id) {
    return models.firstWhere((m) => m.id == id, orElse: () => models.first);
  }

  static AiModel get defaultModel => models.first;
}
